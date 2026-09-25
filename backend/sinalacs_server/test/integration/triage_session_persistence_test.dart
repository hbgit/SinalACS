import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_triage_session_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      // Hex de 64 caracteres: HealthDataCipher decodifica byte a byte
      // para montar a chave AES-256 (ver AppConfig).
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
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
    ),
  );
}

void main() {
  withServerpod('Dado a persistência da triagem', (sessionBuilder, endpoints) {
    setUp(() {
      AlertRuntime.instance.overrideConfig(_config());
    });

    tearDown(() {
      AlertRuntime.instance.overrideConfig(null);
    });

    test('a sessão de triagem é gravada de verdade em triage_sessions', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final service = TriageSessionService(
        store: OrmTriageSessionStore(
          session: () => session,
          cipher: testHealthDataCipher(),
        ),
        audit: OrmAuditTrail(
          session: () => session,
          chainSecret: 'test-audit-chain-secret',
        ),
        clock: () => DateTime.utc(2026, 9, 16, 12, 0, 0),
      );

      final risco = await service.evaluateAndRecord(
        user: _patient,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(risco, RiskLevel.red);

      final gravadas = await TriageSession.db.find(session);
      expect(gravadas, hasLength(1));
      expect(gravadas.single.patientId, UuidValue.fromString(_patientId));
      expect(gravadas.single.resultRisk, RiskLevel.red);
      expect(gravadas.single.resultDisplay, 'Vermelho');
      // A coluna guarda ciphertext (RNF03): as respostas só voltam a ser
      // legíveis passando pela cifra, e é isso que este bloco prova — que a
      // ida e volta pelo store preserva as seis respostas.
      final respostas = await decryptedTriageAnswers(gravadas.single);
      expect(respostas, hasLength(6));
      expect(respostas.first.question, 'chestPain');
      expect(respostas.first.answer, 'sim');
      expect(gravadas.single.answersKeyVersion, 1);
    });

    test('a gravação deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final service = TriageSessionService(
        store: OrmTriageSessionStore(
          session: () => session,
          cipher: testHealthDataCipher(),
        ),
        audit: OrmAuditTrail(
          session: () => session,
          chainSecret: 'test-audit-chain-secret',
        ),
      );

      await service.evaluateAndRecord(
        user: _patient,
        chestPain: false,
        difficultyBreathing: false,
        fever: true,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      final logs = await AuditLog.db.find(session);
      expect(logs, hasLength(1));
      expect(logs.single.actionType, 'write');
      expect(logs.single.resourceType, 'triage_session');
      expect(logs.single.result, 'granted');
      expect(logs.single.resourceId, isNotNull);
    });

    test('o endpoint recusa token inválido', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      await expectLater(
        endpoints.triage.evaluate(
          sessionBuilder,
          accessToken: 'token-que-nao-vale',
          chestPain: true,
          difficultyBreathing: false,
          fever: false,
          persistentVomiting: false,
          bleeding: false,
          severeWeakness: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o endpoint recusa quem não é paciente', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.triage.evaluate(
          sessionBuilder,
          accessToken: login.accessToken,
          chestPain: true,
          difficultyBreathing: false,
          fever: false,
          persistentVomiting: false,
          bleeding: false,
          severeWeakness: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o endpoint classifica e grava a triagem do paciente autenticado', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final resultado = await endpoints.triage.evaluate(
        sessionBuilder,
        accessToken: login.accessToken,
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(resultado.risk, RiskLevel.green);

      final gravadas = await TriageSession.db.find(session);
      expect(gravadas, hasLength(1));
      expect(gravadas.single.resultRisk, RiskLevel.green);
    });
  });
}
