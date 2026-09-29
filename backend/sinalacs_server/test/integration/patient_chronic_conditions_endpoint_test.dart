import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres e o `HealthDataCipher` reais, a leitura e a escrita
/// do perfil clínico do próprio paciente ("Perfil clínico" do app) —
/// `patient_directory_service_test.dart` só prova a mesma coisa com um fake
/// de store, sem exercitar o ciclo cifrar/gravar/ler/decifrar de verdade.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
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
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insert(session, [
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980, 1, 1),
      role: UserRole.acs,
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
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: true,
      chronicConditions: const ['hipertensão'],
    ),
  );
}

void main() {
  withServerpod('Dado o perfil clínico do próprio paciente', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test('myChronicConditions devolve a lista decifrada de verdade', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final result = await endpoints.patients.myChronicConditions(
        sessionBuilder,
        accessToken: login.accessToken,
      );

      expect(result, ['hipertensão']);
    });

    test('updateChronicConditions grava de verdade — cifra, persiste e uma leitura seguinte decifra igual',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await endpoints.patients.updateChronicConditions(
        sessionBuilder,
        accessToken: login.accessToken,
        conditions: const ['asma', 'diabetes'],
      );

      // Contra a linha real do Postgres: nunca ficou vazio em claro, e não é
      // igual ao JSON puro — é o ciphertext base64 que `HealthDataCipher`
      // produz.
      final patient = await Patient.db.findById(session, UuidValue.fromString(_patientId));
      expect(patient!.chronicConditionsEncrypted, isNotEmpty);
      expect(patient.chronicConditionsEncrypted, isNot(contains('asma')));

      final result = await endpoints.patients.myChronicConditions(
        sessionBuilder,
        accessToken: login.accessToken,
      );
      expect(result, ['asma', 'diabetes']);
    });

    test('substitui a lista inteira — não faz merge com o que já estava lá', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await endpoints.patients.updateChronicConditions(
        sessionBuilder,
        accessToken: login.accessToken,
        conditions: const ['asma'],
      );

      final result = await endpoints.patients.myChronicConditions(
        sessionBuilder,
        accessToken: login.accessToken,
      );
      // 'hipertensão', do seed, não sobrevive: quem decide o conjunto final é
      // a chamada, não uma união com o estado anterior.
      expect(result, ['asma']);
    });

    test('um ACS não pode ler o perfil clínico de paciente (só o papel patient pode)', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.patients.myChronicConditions(sessionBuilder, accessToken: login.accessToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('um ACS não pode escrever no perfil clínico de paciente', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.patients.updateChronicConditions(
          sessionBuilder,
          accessToken: login.accessToken,
          conditions: const ['asma'],
        ),
        throwsA(isA<AlertPermissionException>()),
      );

      // A tentativa recusada não deixou rastro na linha do paciente.
      final patient = await Patient.db.findById(
        sessionBuilder.build(),
        UuidValue.fromString(_patientId),
      );
      expect(patient!.chronicConditionsEncrypted, isNotEmpty);
    });

    test('a escrita deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await endpoints.patients.updateChronicConditions(
        sessionBuilder,
        accessToken: login.accessToken,
        conditions: const ['asma'],
      );

      final rows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('patient_profile') & t.actionType.equals('write'),
      );
      expect(rows, hasLength(1));
      expect(rows.single.result, 'granted');
      expect(rows.single.userId, UuidValue.fromString(_patientId));
    });
  });
}
