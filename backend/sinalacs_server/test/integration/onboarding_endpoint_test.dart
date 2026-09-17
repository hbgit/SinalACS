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

// Prefixo `9000` (em vez de `8000`): fixtures do grupo sem rollback
// automático (teste de corrida, no fim do arquivo). Precisam ser distintos
// dos IDs fixos acima e dos de `auth.developmentLogin` — como aquele grupo
// não desfaz suas escritas sozinho, uma colisão de ID com outro arquivo de
// teste de integração (que reusa `...002`/`...003`/`...005` sob rollback
// automático) quebraria a violação de chave única de forma intermitente.
const _raceUbsId = '00000000-0000-4000-9000-000000000001';
const _raceMicroAreaId = '00000000-0000-4000-9000-000000000002';
const _raceAcsId = '00000000-0000-4000-9000-000000000003';
const _racePatientId = '00000000-0000-4000-9000-000000000004';

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

/// Seed isolado do teste de corrida (grupo com rollback desligado) — mesma
/// forma de [_seed], mas com os IDs `9000` que esse grupo limpa manualmente.
Future<void> _seedRace(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_raceUbsId),
      name: 'UBS Desenvolvimento (corrida)',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_raceMicroAreaId),
      name: 'Microárea de corrida',
      ubsId: UuidValue.fromString(_raceUbsId),
      geoJsonBoundary: '{}',
    ),
  );

  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_raceAcsId),
      cpfHash: 'development-acs-corrida',
      name: 'ACS de corrida',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_raceMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_racePatientId),
      cpfHash: 'development-patient-corrida',
      name: 'Paciente de corrida',
      birthDate: DateTime.utc(1975, 3, 10),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_raceMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  ]);

  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_raceAcsId),
      enrollmentId: 'ACS-CORRIDA-001',
      ubsId: UuidValue.fromString(_raceUbsId),
      active: true,
    ),
  );
  await Patient.db.insertRow(
    session,
    Patient(
      id: UuidValue.fromString(_racePatientId),
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: [],
    ),
  );
}

/// Desfaz manualmente tudo que [_seedRace] e o teste de corrida gravam —
/// necessário porque esse grupo roda com `RollbackDatabase.disabled` (ver
/// comentário no `withServerpod` correspondente), então nada some sozinho.
/// Ordem inversa às FKs: filhos antes dos pais.
Future<void> _cleanupRace(Session session) async {
  await ConsentLog.db.deleteWhere(
    session,
    where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
  );
  await EnrollmentToken.db.deleteWhere(
    session,
    where: (t) => t.patientId.equals(UuidValue.fromString(_racePatientId)),
  );
  await Patient.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_racePatientId)),
  );
  await Acs.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceAcsId)),
  );
  await User.db.deleteWhere(
    session,
    where: (t) => t.id.inSet({
          UuidValue.fromString(_raceAcsId),
          UuidValue.fromString(_racePatientId),
        }.cast<UuidValue>()),
  );
  await MicroArea.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceMicroAreaId)),
  );
  await Ubs.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceUbsId)),
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

  // Grupo separado, com rollback desligado: o grupo principal (acima) faz
  // todas as chamadas dentro da MESMA transação externa que `withServerpod`
  // abre para poder desfazê-la ao fim de cada teste (`RollbackDatabase.afterEach`,
  // o padrão). `completeEnrollment` agora abre sua própria `session.db.transaction`
  // (fix round 1, para consumir o convite atomicamente) — chamá-lo duas vezes ao
  // mesmo tempo dentro dessa transação externa compartilhada faz o harness
  // recusar com `InvalidConfigurationException` ("Concurrent calls to
  // transaction are not supported when database rollbacks are enabled").
  // Só com o rollback desligado cada chamada abre uma transação de Postgres de
  // verdade, independente — o que a corrida exige para ser provada. Usa
  // identificadores próprios (prefixo `9000`, distintos dos `8000` do grupo
  // principal e dos IDs fixos de `auth.developmentLogin`) e limpa tudo que
  // grava, para não deixar linha permanente num Postgres de teste compartilhado
  // entre arquivos.
  withServerpod(
    'Dado o onboarding por convite do ACS, sem rollback automático (corrida)',
    (sessionBuilder, endpoints) {
      setUp(() => AlertRuntime.instance.overrideConfig(_config()));
      tearDown(() => AlertRuntime.instance.overrideConfig(null));

      test(
          'duas chamadas concorrentes com o mesmo token: exatamente uma consome, a outra falha (fix round 1)',
          () async {
        final session = sessionBuilder.build();
        await _seedRace(session);

        try {
          final acsToken = AlertRuntime.instance.auth.issueToken(
            const AuthenticatedUser(
              id: _raceAcsId,
              role: UserRole.acs,
              microAreaId: _raceMicroAreaId,
              deviceId: 'acs-corrida-device',
            ),
          );
          final generated = await endpoints.onboarding.generateEnrollmentToken(
            sessionBuilder,
            accessToken: acsToken,
            patientId: _racePatientId,
          );

          // Cada chamada ao endpoint constrói sua própria `Session` internamente
          // (`InternalTestSessionBuilder.internalBuild`, por método), então
          // `Future.wait` aqui dispara duas transações independentes contra o
          // mesmo Postgres real — é isso que exercita a janela de corrida que
          // `consumeIfValid` fecha: sem o `UPDATE` condicional atômico, as duas
          // conseguiam passar pela validação antes de qualquer uma consumir.
          Future<Object> attempt() async {
            try {
              return await endpoints.onboarding.completeEnrollment(
                sessionBuilder,
                token: generated.token,
                healthDataConsent: true,
                remindersConsent: true,
                pushConsent: true,
              );
            } catch (error) {
              return error;
            }
          }

          final results = await Future.wait([attempt(), attempt()]);

          final successes = results.whereType<EnrollmentResult>().toList();
          final failures = results.whereType<EnrollmentException>().toList();
          expect(successes, hasLength(1),
              reason: 'só uma das duas chamadas deve consumir o token');
          expect(failures, hasLength(1),
              reason: 'a outra deve falhar de forma auditável, não silenciosa');

          // 3 linhas, não 6: a chamada perdedora nunca chega a gravar consentimento.
          final rows = await ConsentLog.db.find(
            session,
            where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId)),
          );
          expect(rows, hasLength(3));
        } finally {
          // Sem rollback automático neste grupo: a limpeza é manual, e roda
          // mesmo se uma asserção acima falhar, para o teste ficar repetível.
          await _cleanupRace(session);
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
