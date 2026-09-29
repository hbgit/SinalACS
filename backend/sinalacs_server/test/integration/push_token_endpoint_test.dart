import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, o registro do token de push (RF14): só com o
/// consentimento `segmentedPush` vigente, sem duplicar, e apagado na revogação.
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
  withServerpod('Dado o registro de token de push do paciente (RF14)', (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    Future<String> patientToken() async =>
        (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;

    Future<int> countToken(Session session, String token) =>
        PushToken.db.count(session, where: (t) => t.token.equals(token));

    Future<void> setPush(String accessToken, bool granted) => endpoints.patients.updateConsent(
          sessionBuilder,
          accessToken: accessToken,
          purpose: ConsentPurpose.segmentedPush,
          granted: granted,
        );

    test('paciente com consentimento registra e repete sem duplicar', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      await setPush(token, true);

      for (var i = 0; i < 2; i++) {
        await endpoints.devices.registerPushToken(
          sessionBuilder,
          accessToken: token,
          token: 'tok-1',
          platform: 'android',
        );
      }

      expect(await countToken(session, 'tok-1'), 1);
    });

    test('sem consentimento a chamada falha e nada é gravado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await expectLater(
        endpoints.devices.registerPushToken(
          sessionBuilder,
          accessToken: token,
          token: 'tok-2',
          platform: 'android',
        ),
        throwsA(isA<DataRightsException>()),
      );
      expect(await countToken(session, 'tok-2'), 0);
    });

    test('revogar segmentedPush apaga os tokens do titular', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      await setPush(token, true);
      await endpoints.devices.registerPushToken(
        sessionBuilder,
        accessToken: token,
        token: 'tok-3',
        platform: 'ios',
      );

      await setPush(token, false);

      expect(await countToken(session, 'tok-3'), 0);
    });

    test('conceder de novo depois de revogar volta a permitir o registro', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();
      await setPush(token, true);
      await setPush(token, false);
      await setPush(token, true);

      await endpoints.devices.registerPushToken(
        sessionBuilder,
        accessToken: token,
        token: 'tok-4',
        platform: 'android',
      );

      expect(await countToken(session, 'tok-4'), 1);
    });

    test('token de acesso inválido é recusado', () async {
      await expectLater(
        endpoints.devices.registerPushToken(
          sessionBuilder,
          accessToken: 'lixo',
          token: 'tok',
          platform: 'android',
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });
  });
}
