import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, os direitos do titular exercidos pelo app
/// (LGPD-RF05/RF08): a linha assinada em `consent_logs`, o pedido cifrado em
/// `data_subject_requests` e o reflexo de ambos em `patients.myData`.
/// `data_subject_rights_service_test.dart` prova as regras com fakes.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _chainSecret = 'test-audit-chain-secret';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: _chainSecret,
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
      isChronic: false,
      chronicConditions: const [],
    ),
  );
}

void main() {
  withServerpod('Dados os direitos do titular exercidos pelo app', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<String> patientToken() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;

    test('updateConsent grava linha assinada em consent_logs e myData passa a mostrá-la', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final record = await endpoints.patients.updateConsent(
        sessionBuilder,
        accessToken: token,
        purpose: ConsentPurpose.localReminders,
        granted: false,
      );
      expect(record.action, 'denied');

      final row = (await ConsentLog.db.find(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_patientId)),
      ))
          .single;
      expect(row.purpose, 'localReminders');
      expect(row.action, 'denied');
      expect(row.ipHash, 'nao-aplicavel-painel-titular');
      expect(
        row.signature,
        ConsentSignature(secret: _chainSecret).compute(
          userId: _patientId,
          purpose: row.purpose,
          action: row.action,
          version: row.version,
          timestamp: row.timestamp,
        ),
      );

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.consents.last.purpose, 'localReminders');
      expect(overview.consents.last.action, 'denied');
    });

    test('updateConsent recusa a finalidade obrigatória sem gravar nada', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await expectLater(
        endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: token,
          purpose: ConsentPurpose.healthDataProcessing,
          granted: false,
        ),
        throwsA(isA<DataRightsException>()),
      );
      expect(await ConsentLog.db.count(session), 0);
    });

    test('requestDataDeletion repetido deixa um pedido só, com prazo de 15 dias, visível em myData', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      final first = await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);
      final second = await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);

      expect(second.createdAt, first.createdAt);
      expect(first.dueAt.difference(first.createdAt), const Duration(days: 15));
      expect(first.status, DataSubjectRequestStatus.open);
      expect(await DataSubjectRequest.db.count(session), 1);

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.requests.single.type, DataSubjectRequestType.deletion);
      expect(overview.requests.single.status, DataSubjectRequestStatus.open);
    });

    test('requestDataCorrection guarda o texto cifrado e myData devolve o texto decifrado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.requestDataCorrection(
        sessionBuilder,
        accessToken: token,
        details: 'Meu contato de emergência mudou.',
      );

      final row = (await DataSubjectRequest.db.find(session)).single;
      expect(row.detailsEncrypted, isNot(contains('contato')));
      expect(row.detailsEncrypted, isNotEmpty);

      final overview = await endpoints.patients.myData(sessionBuilder, accessToken: token);
      expect(overview.requests.single.type, DataSubjectRequestType.correction);
      expect(overview.requests.single.details, 'Meu contato de emergência mudou.');
    });

    test('um ACS não chama nenhuma das três', () async {
      await _seed(sessionBuilder.build());
      final token =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: token,
          purpose: ConsentPurpose.localReminders,
          granted: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.patients.requestDataCorrection(sessionBuilder, accessToken: token, details: 'x'),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('cada escrita deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.updateConsent(
        sessionBuilder,
        accessToken: token,
        purpose: ConsentPurpose.segmentedPush,
        granted: true,
      );
      await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);

      final consentRows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('consent_log'),
      );
      final requestRows = await AuditLog.db.find(
        session,
        where: (t) => t.resourceType.equals('data_subject_request'),
      );
      expect(consentRows, hasLength(1));
      expect(requestRows, hasLength(1));
      expect(requestRows.single.userId, UuidValue.fromString(_patientId));
    });
  });
}
