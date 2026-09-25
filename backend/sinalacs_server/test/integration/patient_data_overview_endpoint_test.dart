import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, a agregação do painel "Meus Dados" (LGPD)
/// através de `patients`, `users`, `consent_logs`, `triage_sessions` e
/// `alerts` — `patient_data_overview_service_test.dart` só prova a mesma
/// coisa com um fake de store, sem exercitar as quatro consultas de verdade.
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
  await ConsentLog.db.insertRow(
    session,
    ConsentLog(
      userId: UuidValue.fromString(_patientId),
      purpose: 'healthDataProcessing',
      action: 'granted',
      version: '2026.1',
      timestamp: DateTime.utc(2026, 1, 1),
      ipHash: 'hash-de-teste',
      userAgent: 'teste',
      signature: 'assinatura-de-teste',
    ),
  );
  await TriageSession.db.insertRow(
    session,
    TriageSession(
      patientId: UuidValue.fromString(_patientId),
      resultRisk: RiskLevel.yellow,
      resultDisplay: 'Risco: Amarelo',
      createdAt: DateTime.utc(2026, 2, 1),
      deviceId: 'device-de-teste',
    ),
  );
  await Alert.db.insertRow(
    session,
    Alert(
      patientId: UuidValue.fromString(_patientId),
      microAreaId: UuidValue.fromString(_microAreaId),
      triggeredAt: DateTime.utc(2026, 3, 1),
      riskLevel: RiskLevel.red,
      locationHash: 'hash-de-localizacao',
      status: AlertStatus.pending,
      mqttTopic: 'sinalacs/v1/microareas/$_microAreaId/alerts',
      deviceId: 'device-de-teste',
      retryCount: 0,
      version: 0,
    ),
  );
}

void main() {
  withServerpod('Dado o painel "Meus Dados" do próprio paciente', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test('patients.myData agrega cadastro, condições, consentimentos e histórico de risco, via Postgres real',
        () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final result = await endpoints.patients.myData(
        sessionBuilder,
        accessToken: login.accessToken,
      );

      expect(result.name, 'Paciente de desenvolvimento');
      expect(result.birthDate, DateTime.utc(1990, 1, 1));
      expect(result.emergencyContact, 'Contato de desenvolvimento');
      expect(result.isChronic, isTrue);
      expect(result.chronicConditions, ['hipertensão']);

      expect(result.consents, hasLength(1));
      expect(result.consents.single.purpose, 'healthDataProcessing');
      expect(result.consents.single.action, 'granted');

      // Mais recente primeiro: o alerta (2026-03-01) vem antes da triagem
      // (2026-02-01).
      expect(result.riskHistory, hasLength(2));
      expect(result.riskHistory[0].source, 'alert');
      expect(result.riskHistory[0].riskLevel, RiskLevel.red);
      expect(result.riskHistory[1].source, 'triage');
      expect(result.riskHistory[1].riskLevel, RiskLevel.yellow);
    });

    test('um ACS não pode consultar o painel "Meus Dados" de um paciente', () async {
      await _seed(sessionBuilder.build());
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.patients.myData(sessionBuilder, accessToken: login.accessToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('a leitura deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      await endpoints.patients.myData(sessionBuilder, accessToken: login.accessToken);

      final rows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('patient_data_overview'),
      );
      expect(rows, hasLength(1));
      expect(rows.single.result, 'granted');
      expect(rows.single.userId, UuidValue.fromString(_patientId));
    });
  });
}
