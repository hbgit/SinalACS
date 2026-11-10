import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/endpoints/auth_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, o login do participante por credencial de
/// dispositivo (RF24, C-05) e o boot do backend no perfil do piloto **sem**
/// `SMS_GATEWAY` — o critério de aceite da issue #128.
///
/// O convite continua sendo o de `onboarding.generateEnrollmentToken`; o que
/// muda é que a conclusão agora grava a credencial
/// (`patient_device_credentials`) e o acesso seguinte é `auth.loginDevice`
/// com o segredo liberado pelo PIN local (que nunca chega ao servidor — aqui
/// só existe o segredo sintético).
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _patientId = '00000000-0000-4000-8000-000000000005';
const _deviceId = '00000000-0000-4000-8000-0000000000b1';
// Base64url sem padding de 43 caracteres (32 bytes): o formato que
// `generateDeviceSecret` produz no app e que o endpoint passou a exigir.
const _deviceSecret = 'c2luYWxhY3MtZGV2aWNlLXNlY3JldC00Mi1zaW50ZXQ';
const _outroSegredo = 'c2luYWxhY3MtZGV2aWNlLXNlY3JldC00Mi1lcnJhZG8';

AppConfig _devConfig() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      telemetryPseudonymKey: AppConfig.developmentTelemetryPseudonymKey,
      smsGateway: 'log',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

/// Configuração do perfil do piloto, construída **por `fromMap`** (o caminho
/// real do ambiente) e sem `SMS_GATEWAY`: é a prova de que o backend sobe sem
/// a variável fora de `development` (C-05, RNF08).
AppConfig _pilotConfig() => AppConfig.fromMap({
      'APP_ENV': 'production',
      'JWT_SECRET': 'a' * 64,
      'AUDIT_CHAIN_SECRET': 'b' * 64,
      'HEALTH_DATA_ENCRYPTION_KEY': 'c' * 64,
      'CPF_HASH_PEPPER': 'd' * 64,
      'TELEMETRY_PSEUDONYM_KEY': 'e' * 64,
      // Sem SMS_GATEWAY, sem MQTT_USE_TLS: exatamente a ausência que o
      // critério de aceite exige.
    });

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
  // O participante do piloto não informa CPF (RNF09): a coluna é anulável
  // desde a C-05, e este seed a deixa nula de propósito — a conclusão do
  // convite e o login por credencial não podem depender do hash de CPF.
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
      cpfHash: null,
      name: 'Participante do piloto',
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
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
    ),
  );
}

Future<String> _invite(
  TestEndpoints endpoints,
  TestSessionBuilder sessionBuilder,
) async {
  final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
  final generated = await endpoints.onboarding.generateEnrollmentToken(
    sessionBuilder,
    accessToken: login.accessToken,
    patientId: _patientId,
  );
  return generated.token;
}

Future<EnrollmentResult> _enroll(
  TestEndpoints endpoints,
  TestSessionBuilder sessionBuilder,
  String token, {
  String deviceId = _deviceId,
  String deviceSecret = _deviceSecret,
}) =>
    endpoints.onboarding.completeEnrollment(
      sessionBuilder,
      token: token,
      healthDataConsent: true,
      remindersConsent: true,
      pushConsent: true,
      termsAccepted: true,
      deviceId: deviceId,
      deviceSecret: deviceSecret,
    );

void main() {
  withServerpod('Dado o backend no perfil do piloto (sem SMS_GATEWAY)',
      (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_pilotConfig()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test('o backend sobe sem SMS_GATEWAY e o caminho do OTP fica desligado',
        () async {
      expect(AlertRuntime.instance.config.smsGateway, isNull);

      final health = await endpoints.health.check(sessionBuilder);
      expect(health.status, 'ok');

      // RF01 é Futuro: sem gateway o pedido de código é recusado
      // explicitamente, nunca um envio silencioso para lugar nenhum.
      await expectLater(
        endpoints.auth.requestOtp(
          sessionBuilder,
          cpf: '52998224725',
          birthDate: DateTime.utc(1980, 1, 1),
        ),
        throwsA(isA<EndpointDisabledException>()),
      );

      // A verificação também tem a guarda: sem ela, o serviço era construído
      // sem gateway e a chamada caía num StateError (500) em vez da recusa.
      await expectLater(
        endpoints.auth.verifyOtp(
          sessionBuilder,
          cpf: '52998224725',
          code: '123456',
        ),
        throwsA(isA<EndpointDisabledException>()),
      );
    });
  });

  withServerpod('Dado o login por credencial de dispositivo (RF24)',
      (sessionBuilder, endpoints) {
    setUp(() => AlertRuntime.instance.overrideConfig(_devConfig()));
    tearDown(() => AlertRuntime.instance.overrideConfig(null));

    test(
        'convite concluído cria a credencial e auth.loginDevice devolve a sessão',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final token = await _invite(endpoints, sessionBuilder);
      await _enroll(endpoints, sessionBuilder, token);

      final result = await endpoints.auth.loginDevice(
        sessionBuilder,
        deviceId: _deviceId,
        deviceSecret: _deviceSecret,
      );

      final user = AlertRuntime.instance.auth.verifyToken(result.accessToken);
      expect(user, isNotNull);
      expect(user!.id, _patientId);
      expect(user.role, UserRole.patient);
      expect(user.microAreaId, _microAreaId);
      expect(user.deviceId, _deviceId);
      expect(
        AlertRuntimeHarness.tokenLifetime(result.accessToken),
        AuthEndpoint.patientSessionLifetime,
      );

      final credential = await PatientDeviceCredential.db.findFirstRow(
        session,
        where: (t) => t.deviceId.equals(_deviceId),
      );
      expect(credential, isNotNull);
      expect(credential!.lastUsedAt, isNotNull);
    });

    test(
        'segredo errado, aparelho desconhecido e deviceId malformado recebem a MESMA recusa',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await _invite(endpoints, sessionBuilder);
      await _enroll(endpoints, sessionBuilder, token);

      const message = 'Credencial inválida ou revogada.';
      Future<void> attempt(String deviceId, String secret) =>
          endpoints.auth.loginDevice(
            sessionBuilder,
            deviceId: deviceId,
            deviceSecret: secret,
          );

      await expectLater(
        attempt(_deviceId, _outroSegredo),
        throwsA(isA<DeviceCredentialException>()
            .having((e) => e.message, 'message', message)),
      );
      await expectLater(
        attempt('00000000-0000-4000-8000-0000000000ff', _deviceSecret),
        throwsA(isA<DeviceCredentialException>()
            .having((e) => e.message, 'message', message)),
      );
      await expectLater(
        attempt('nao-e-um-uuid', _deviceSecret),
        throwsA(isA<DeviceCredentialException>()
            .having((e) => e.message, 'message', message)),
      );
      // Formato do segredo também é recusado com a MESMA mensagem: o
      // servidor não aceita mais um segredo de baixa entropia vindo de um
      // cliente com defeito.
      await expectLater(
        attempt(_deviceId, 'segredo-curto'),
        throwsA(isA<DeviceCredentialException>()
            .having((e) => e.message, 'message', message)),
      );

      // A recusa de credencial conhecida entra na trilha de auditoria.
      final auditRows = await AuditLog.db.find(
        session,
        where: (t) =>
            t.resourceType.equals('patient_device_credential') &
            t.result.equals('denied_credential'),
      );
      expect(auditRows, isNotEmpty);
    });

    test('deviceId fora do formato UUID não consome o convite', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await _invite(endpoints, sessionBuilder);

      await expectLater(
        _enroll(
          endpoints,
          sessionBuilder,
          token,
          deviceId: 'aparelho-sem-uuid',
        ),
        throwsA(isA<EnrollmentException>()),
      );

      // O convite continua válido: a recusa foi antes do consumo.
      final result = await _enroll(endpoints, sessionBuilder, token);
      expect(result.accessToken, isNotEmpty);

      final credentials = await PatientDeviceCredential.db.find(
        session,
        where: (t) => t.patientId.equals(UuidValue.fromString(_patientId)),
      );
      expect(credentials, hasLength(1));
      expect(credentials.single.deviceId, _deviceId);
    });

    test('deviceSecret fora do formato não consome o convite', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await _invite(endpoints, sessionBuilder);

      await expectLater(
        _enroll(
          endpoints,
          sessionBuilder,
          token,
          deviceSecret: 'segredo-curto',
        ),
        throwsA(isA<EnrollmentException>()),
      );

      // O convite continua válido: a recusa foi antes do consumo, como na
      // validação do deviceId.
      final result = await _enroll(endpoints, sessionBuilder, token);
      expect(result.accessToken, isNotEmpty);
    });

    test(
        'titular sem microárea recebe a recusa de território, não a de credencial',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await _invite(endpoints, sessionBuilder);
      await _enroll(endpoints, sessionBuilder, token);

      // O vínculo territorial do cadastro some — estado administrativo, e
      // possivelmente transitório. A credencial continua válida, então a
      // recusa é a própria do território (o app não pode apagá-la).
      final paciente = await User.db.findFirstRow(
        session,
        where: (t) => t.id.equals(UuidValue.fromString(_patientId)),
      );
      await User.db.updateRow(
        session,
        paciente!.copyWith(microAreaId: null),
      );

      await expectLater(
        endpoints.auth.loginDevice(
          sessionBuilder,
          deviceId: _deviceId,
          deviceSecret: _deviceSecret,
        ),
        throwsA(isA<DeviceCredentialTerritoryException>().having(
          (e) => e.message,
          'message',
          'Este acesso não está vinculado a uma microárea.',
        )),
      );

      final auditRows = await AuditLog.db.find(
        session,
        where: (t) =>
            t.resourceType.equals('patient_device_credential') &
            t.result.equals('denied_no_territory'),
      );
      expect(auditRows, hasLength(1));
      expect(auditRows.single.userId.uuid, _patientId);
    });

    test('o login bem-sucedido entra na trilha como granted', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await _invite(endpoints, sessionBuilder);
      await _enroll(endpoints, sessionBuilder, token);
      await endpoints.auth.loginDevice(
        sessionBuilder,
        deviceId: _deviceId,
        deviceSecret: _deviceSecret,
      );

      final auditRows = await AuditLog.db.find(
        session,
        where: (t) =>
            t.resourceType.equals('patient_device_credential') &
            t.result.equals('granted'),
      );
      expect(auditRows, hasLength(1));
      expect(auditRows.single.userId.uuid, _patientId);
    });
  });
}
