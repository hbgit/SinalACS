import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:test/test.dart';

/// Regras de aceitação do segredo de assinatura.
///
/// A validação anterior cobria apenas `APP_ENV=production` e testava só
/// `== null`, então `JWT_SECRET=""` e `APP_ENV=staging` subiam assinando com um
/// valor público — e o `docker-compose.yml` sequer passava a variável.
void main() {
  AppConfig build({required String appEnv, String? jwtSecret}) =>
      AppConfig.fromMap({
        'APP_ENV': appEnv,
        'JWT_SECRET': ?jwtSecret,
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
      final config = build(appEnv: 'production', jwtSecret: 'b' * 64);

      expect(config.jwtSecret, 'b' * 64);
      expect(config.isProduction, isTrue);
    });

    test('espaços em volta do segredo são aparados', () {
      expect(
        build(appEnv: 'production', jwtSecret: '  ${'c' * 64}  ').jwtSecret,
        'c' * 64,
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
