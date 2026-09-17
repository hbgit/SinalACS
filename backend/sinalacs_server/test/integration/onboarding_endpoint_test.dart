import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, o primeiro escritor de `consent_logs` e o
/// convite de uso único de `enrollment_tokens` — mesmo objetivo de
/// `patient_directory_and_territory_test.dart` para `audit_logs`: os fakes de
/// `onboarding_service_test.dart` só provam a lógica de aplicação, não o SQL
/// gerado (FKs de `enrollment_tokens.created_by_acs_id`/`patient_id` contra
/// `acs`/`patients`, o índice único de `token_hash`).
///
/// `auth.developmentLogin(role: 'acs')` sempre devolve o ACS fixo de
/// desenvolvimento (id `...002`, microárea `...003`) — para o caso de
/// território cruzado, o token de um segundo ACS é forjado diretamente via
/// `AlertRuntime.instance.auth.issueToken`, o mesmo mecanismo que o endpoint
/// usa para emitir sessão ao concluir o onboarding.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _otherMicroAreaId = '00000000-0000-4000-8000-000000000099';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _patientId = '00000000-0000-4000-8000-000000000005';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insert(session, [
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
    MicroArea(
      id: UuidValue.fromString(_otherMicroAreaId),
      name: 'Microárea vizinha',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  ]);

  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient-05',
      name: 'Fulano de Tal',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  ]);

  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await Patient.db.insertRow(
    session,
    Patient(
      id: UuidValue.fromString(_patientId),
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: [],
    ),
  );
}

void main() {
  withServerpod('Dado o onboarding por convite do ACS', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test('ACS gera convite para paciente da própria microárea', () async {
      await _seed(sessionBuilder.build());

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final result = await endpoints.onboarding.generateEnrollmentToken(
        sessionBuilder,
        accessToken: login.accessToken,
        patientId: _patientId,
      );

      expect(result.token, isNotEmpty);
      expect(result.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('ACS de outra microárea recebe AlertPermissionException ao gerar convite', () async {
      await _seed(sessionBuilder.build());

      final outraAreaToken = AlertRuntime.instance.auth.issueToken(
        const AuthenticatedUser(
          id: '00000000-0000-4000-8000-000000000077',
          role: UserRole.acs,
          microAreaId: _otherMicroAreaId,
          deviceId: 'acs-outra-area-device',
        ),
      );

      await expectLater(
        endpoints.onboarding.generateEnrollmentToken(
          sessionBuilder,
          accessToken: outraAreaToken,
          patientId: _patientId,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test(
        'completeEnrollment com token válido grava 3 consent_logs e devolve sessão do paciente',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final generated = await endpoints.onboarding.generateEnrollmentToken(
        sessionBuilder,
        accessToken: login.accessToken,
        patientId: _patientId,
      );

      final result = await endpoints.onboarding.completeEnrollment(
        sessionBuilder,
        token: generated.token,
        healthDataConsent: true,
        remindersConsent: false,
        pushConsent: true,
      );

      final rows = await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      );
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.version == '2026.1'), isTrue);
      final byPurpose = {for (final r in rows) r.purpose: r.action};
      expect(byPurpose['healthDataProcessing'], 'granted');
      expect(byPurpose['localReminders'], 'denied');
      expect(byPurpose['segmentedPush'], 'granted');

      final user = AlertRuntime.instance.auth.verifyToken(result.accessToken);
      expect(user, isNotNull);
      expect(user!.id, _patientId);
      expect(user.role, UserRole.patient);
      expect(user.microAreaId, _microAreaId);
    });

    test('segundo uso do mesmo token falha com EnrollmentException', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final generated = await endpoints.onboarding.generateEnrollmentToken(
        sessionBuilder,
        accessToken: login.accessToken,
        patientId: _patientId,
      );

      await endpoints.onboarding.completeEnrollment(
        sessionBuilder,
        token: generated.token,
        healthDataConsent: true,
        remindersConsent: true,
        pushConsent: true,
      );

      await expectLater(
        endpoints.onboarding.completeEnrollment(
          sessionBuilder,
          token: generated.token,
          healthDataConsent: true,
          remindersConsent: true,
          pushConsent: true,
        ),
        throwsA(isA<EnrollmentException>()),
      );
    });

    test(
        'recusa do consentimento obrigatório falha e não grava nenhuma linha em consent_logs',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
      final generated = await endpoints.onboarding.generateEnrollmentToken(
        sessionBuilder,
        accessToken: login.accessToken,
        patientId: _patientId,
      );

      await expectLater(
        endpoints.onboarding.completeEnrollment(
          sessionBuilder,
          token: generated.token,
          healthDataConsent: false,
          remindersConsent: true,
          pushConsent: true,
        ),
        throwsA(isA<EnrollmentException>()),
      );

      final rows = await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      );
      expect(rows, isEmpty);
    });
  });
}
