import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';

import 'support/fake_rpc_server.dart';

/// O login por credencial de dispositivo (RF24, C-05) pelo [BackendClient]
/// **real**, contra um servidor RPC falso no protocolo do Serverpod.
///
/// É o único lugar onde três coisas ficam presas: a tradução
/// `DeviceCredentialException → BackendFailure(mensagem do servidor,
/// não recuperável, `credentialRefused`)`, a leitura do TTL do token e a
/// conclusão do onboarding com deviceId/segredo. Nenhum teste durável passava
/// por `loginDevice` antes deste arquivo — a suíte de widgets usa o
/// `FakePatientBackend`, que não tem `_guard` nenhum.
///
/// deviceId/segredos sintéticos; nenhum dado real.
void main() {
  const deviceId = '00000000-0000-4000-8000-0000000000c1';
  const deviceSecret = 'segredo-sintetico-do-aparelho';

  late FakeRpcServer server;
  late BackendClient backend;

  setUp(() async {
    server = await FakeRpcServer.start();
    backend = BackendClient(host: server.host);
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  group('loginDevice', () {
    test('a recusa do servidor vira BackendFailure com a mensagem dele', () async {
      server.rejectLoginDeviceWith = 'Credencial inválida ou revogada.';

      await expectLater(
        backend.loginDevice(deviceId: deviceId, deviceSecret: deviceSecret),
        throwsA(
          isA<BackendFailure>()
              .having((falha) => falha.message, 'mensagem',
                  'Credencial inválida ou revogada.')
              .having((falha) => falha.isRecoverable, 'isRecoverable', isFalse)
              .having((falha) => falha.credentialRefused, 'credentialRefused',
                  isTrue),
        ),
      );
      expect(backend.isAuthenticated, isFalse);
    });

    test('envia deviceId e deviceSecret ao auth.loginDevice', () async {
      await backend.loginDevice(deviceId: deviceId, deviceSecret: deviceSecret);

      final pedido = server.requests.single;
      expect(pedido.endpoint, 'auth');
      expect(pedido.method, 'loginDevice');
      expect(pedido.args['deviceId'], deviceId);
      expect(pedido.args['deviceSecret'], deviceSecret);
    });

    test('a sessão sai com o TTL que está no token, e não com um suposto',
        () async {
      // Dois valores diferentes: o app lê o `exp` do token (é o servidor que
      // decide, e o RF24 decide 1 hora — `AuthEndpoint.patientSessionLifetime`).
      // Um teste só com 1 hora passaria também se o app cravasse a hora, e é
      // essa suposição que o segundo valor mata.
      server.tokenLifetime = const Duration(hours: 1);
      final umaHora = await backend.loginDevice(
          deviceId: deviceId, deviceSecret: deviceSecret);
      expect(
        umaHora.expiresAt.difference(DateTime.now().toUtc()),
        greaterThan(const Duration(minutes: 59)),
      );

      server.tokenLifetime = const Duration(minutes: 15);
      final quinzeMinutos = await backend.loginDevice(
          deviceId: deviceId, deviceSecret: deviceSecret);
      expect(
        quinzeMinutos.expiresAt.difference(DateTime.now().toUtc()),
        lessThan(const Duration(minutes: 16)),
      );

      expect(umaHora.role, 'patient');
      expect(umaHora.microAreaId, server.microAreaId);
      expect(backend.isAuthenticated, isTrue);
    });

    test('token já vencido deixa o app sem sessão utilizável', () async {
      server.tokenLifetime = const Duration(minutes: -1);
      final vencida = await backend.loginDevice(
          deviceId: deviceId, deviceSecret: deviceSecret);

      expect(vencida.isExpired(), isTrue);
      expect(backend.isAuthenticated, isFalse);
    });
  });

  group('completeEnrollment', () {
    test('envia o convite, os consentimentos e a credencial de dispositivo',
        () async {
      final session = await backend.completeEnrollment(
        token: 'convite-sintetico',
        healthDataConsent: true,
        remindersConsent: false,
        pushConsent: true,
        termsAccepted: true,
        deviceId: deviceId,
        deviceSecret: deviceSecret,
      );

      expect(session.role, 'patient');
      final pedido = server.requests.single;
      expect(pedido.endpoint, 'onboarding');
      expect(pedido.method, 'completeEnrollment');
      expect(pedido.args['token'], 'convite-sintetico');
      expect(pedido.args['deviceId'], deviceId);
      expect(pedido.args['deviceSecret'], deviceSecret);
    });

    test('a recusa vira BackendFailure com a mensagem do servidor', () async {
      server.rejectEnrollmentWith = 'Convite inválido, expirado ou já utilizado.';

      await expectLater(
        backend.completeEnrollment(
          token: 'convite-sintetico',
          healthDataConsent: true,
          remindersConsent: false,
          pushConsent: true,
          termsAccepted: true,
          deviceId: deviceId,
          deviceSecret: deviceSecret,
        ),
        throwsA(
          isA<BackendFailure>().having(
            (falha) => falha.message,
            'mensagem',
            'Convite inválido, expirado ou já utilizado.',
          ),
        ),
      );
      expect(backend.isAuthenticated, isFalse);
    });
  });

  /// RNF04/L-08: o host do `--dart-define` não pode voltar para http. A Task 4
  /// mediu que o `network_security_config.xml` não bloqueia o cleartext do
  /// `dart:io`, então esta validação é a única barreira que sobrou — e é aqui
  /// que ela fica vermelha se alguém a apagar.
  group('host do RPC', () {
    test('recusa http — a porta em texto claro não existe mais', () {
      expect(
        () => requireSecureHost('http://10.0.2.2:8080/'),
        throwsA(
          isA<BackendFailure>()
              .having((f) => f.isRecoverable, 'isRecoverable', isFalse)
              .having((f) => f.message, 'message', contains('https')),
        ),
      );
      // Sem host nenhum também é recusa, e não um cliente sem endereço.
      expect(() => requireSecureHost(''), throwsA(isA<BackendFailure>()));
      expect(() => requireSecureHost('10.0.2.2'), throwsA(isA<BackendFailure>()));
    });

    test('aceita https e devolve o mesmo endereço', () {
      expect(requireSecureHost('https://10.0.2.2/'), 'https://10.0.2.2/');
    });

    test('o default de compilação é https', () {
      // O valor que o APK carrega sem nenhum --dart-define.
      expect(BackendConfig.host, startsWith('https://'));
      expect(BackendClient.resolveHost(null), BackendConfig.host);
    });

    test('valida quando o cliente cai no default, não quando o host é explícito', () {
      expect(
        () => BackendClient.resolveHost(null, defaultHost: 'http://10.0.2.2:8080/'),
        throwsA(isA<BackendFailure>()),
      );

      // O caminho dos testes herméticos, que apontam para servidores fake em
      // `http://127.0.0.1:<porta efêmera>/`: passa como veio.
      expect(
        BackendClient.resolveHost('http://127.0.0.1:4444/'),
        'http://127.0.0.1:4444/',
      );
    });
  });
}
