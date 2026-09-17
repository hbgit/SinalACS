import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:test/test.dart';

/// Regras de aceitação dos segredos de assinatura.
///
/// A validação anterior cobria apenas `APP_ENV=production` e testava só
/// `== null`, então `JWT_SECRET=""` e `APP_ENV=staging` subiam assinando com um
/// valor público — e o `docker-compose.yml` sequer passava a variável.
/// `AUDIT_CHAIN_SECRET` segue exatamente a mesma regra, para a cadeia de hash
/// de `audit_logs`.
void main() {
  AppConfig build({
    required String appEnv,
    String? jwtSecret,
    String? auditChainSecret,
    String? healthDataEncryptionKey,
  }) =>
      AppConfig.fromMap({
        'APP_ENV': appEnv,
        'JWT_SECRET': ?jwtSecret,
        'AUDIT_CHAIN_SECRET': ?auditChainSecret,
        'HEALTH_DATA_ENCRYPTION_KEY': ?healthDataEncryptionKey,
      });

  group('JWT_SECRET', () {
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').jwtSecret,
        AppConfig.developmentJwtSecret,
      );
    });

    test('development aceita um segredo próprio', () {
      expect(
        build(appEnv: 'development', jwtSecret: 'a' * 64).jwtSecret,
        'a' * 64,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production'),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('JWT_SECRET é obrigatório'),
        )),
      );
    });

    test('staging sem a variável também não sobe', () {
      // A checagem anterior cobria só production.
      expect(() => build(appEnv: 'staging'), throwsA(isA<StateError>()));
    });

    test('string vazia conta como ausente', () {
      expect(
        () => build(appEnv: 'production', jwtSecret: ''),
        throwsA(isA<StateError>()),
      );
    });

    test('string só de espaços conta como ausente', () {
      expect(
        () => build(appEnv: 'production', jwtSecret: '   '),
        throwsA(isA<StateError>()),
      );
    });

    test('o segredo de desenvolvimento não pode ser promovido', () {
      // Está neste repositório versionado: usá-lo fora de development é assinar
      // token com chave pública, e o token carrega papel e microárea.
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: AppConfig.developmentJwtSecret,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('valor de desenvolvimento'),
        )),
      );
    });

    test('production com segredo próprio sobe', () {
      final config = build(
        appEnv: 'production',
        jwtSecret: 'b' * 64,
        auditChainSecret: 'd' * 64,
        healthDataEncryptionKey: 'e' * 64,
      );

      expect(config.jwtSecret, 'b' * 64);
      expect(config.isProduction, isTrue);
    });

    test('espaços em volta do segredo são aparados', () {
      expect(
        build(
          appEnv: 'production',
          jwtSecret: '  ${'c' * 64}  ',
          auditChainSecret: 'd' * 64,
          healthDataEncryptionKey: 'e' * 64,
        ).jwtSecret,
        'c' * 64,
      );
    });
  });

  group('AUDIT_CHAIN_SECRET', () {
    // Mesmas regras de JWT_SECRET, testadas de novo porque cada segredo é
    // resolvido de forma independente: um poderia estar certo e o outro
    // esquecido sem que os testes de JWT_SECRET percebessem.
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').auditChainSecret,
        AppConfig.developmentAuditChainSecret,
      );
    });

    test('development aceita um segredo próprio', () {
      expect(
        build(appEnv: 'development', auditChainSecret: 'a' * 64)
            .auditChainSecret,
        'a' * 64,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production', jwtSecret: 'b' * 64),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('AUDIT_CHAIN_SECRET é obrigatório'),
        )),
      );
    });

    test('string vazia conta como ausente', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'b' * 64,
          auditChainSecret: '',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('o segredo de desenvolvimento não pode ser promovido', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'b' * 64,
          auditChainSecret: AppConfig.developmentAuditChainSecret,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('valor de desenvolvimento'),
        )),
      );
    });

    test('production com segredo próprio sobe, independente do JWT_SECRET',
        () {
      final config = build(
        appEnv: 'production',
        jwtSecret: 'b' * 64,
        auditChainSecret: 'd' * 64,
        healthDataEncryptionKey: 'e' * 64,
      );

      expect(config.auditChainSecret, 'd' * 64);
      expect(config.jwtSecret, 'b' * 64);
    });
  });

  group('HEALTH_DATA_ENCRYPTION_KEY', () {
    test('development sem a variável usa o fallback conhecido', () {
      expect(
        build(appEnv: 'development').healthDataEncryptionKey,
        AppConfig.developmentHealthDataEncryptionKey,
      );
    });

    test('production sem a variável não sobe', () {
      expect(
        () => build(appEnv: 'production'),
        throwsA(isA<StateError>()),
      );
    });

    test('production com o valor de desenvolvimento não sobe', () {
      expect(
        () => build(
          appEnv: 'production',
          jwtSecret: 'a' * 64,
          auditChainSecret: 'b' * 64,
          healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('defaults', () {
    test('um ambiente vazio produz a configuração de desenvolvimento', () {
      final config = AppConfig.fromMap(const {});

      expect(config.appEnv, 'development');
      expect(config.mqttBroker, 'localhost:1883');
      expect(config.mqttUseTls, isFalse);
      // Gate do auth.developmentLogin: desligado quando não pedido.
      expect(config.enableDevLogin, isFalse);
    });

    test('ENABLE_DEV_LOGIN só liga com a string exata "true"', () {
      expect(AppConfig.fromMap(const {'ENABLE_DEV_LOGIN': 'true'}).enableDevLogin, isTrue);
      expect(AppConfig.fromMap(const {'ENABLE_DEV_LOGIN': 'TRUE'}).enableDevLogin, isFalse);
      expect(AppConfig.fromMap(const {'ENABLE_DEV_LOGIN': '1'}).enableDevLogin, isFalse);
    });
  });
}
