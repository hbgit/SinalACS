import 'dart:io';

/// Configuração que **não** vem do Serverpod.
///
/// Banco e servidor são configurados por `config/*.yaml` mais as variáveis
/// `SERVERPOD_*`. O que sobra — MQTT e o segredo de autenticação — é lido aqui.
class AppConfig {
  const AppConfig({
    required this.mqttBroker,
    required this.jwtSecret,
    required this.mqttUsername,
    required this.mqttPassword,
    required this.mqttUseTls,
    required this.mqttCaCertificatePath,
    required this.appEnv,
    required this.enableDevLogin,
  });

  final String mqttBroker;

  /// Chave HMAC que assina os tokens de `auth.developmentLogin`.
  ///
  /// O token carrega o papel e a microárea, então quem conhece este valor forja
  /// um acesso de ACS para qualquer território. Ver [_resolveJwtSecret].
  final String jwtSecret;

  final String? mqttUsername;
  final String? mqttPassword;
  final bool mqttUseTls;
  final String? mqttCaCertificatePath;
  final String appEnv;
  final bool enableDevLogin;

  bool get isProduction => appEnv == 'production';

  /// Segredo usado quando `JWT_SECRET` não é informado em desenvolvimento.
  ///
  /// É público — está neste arquivo versionado — e por isso só pode valer em
  /// `development`. [_resolveJwtSecret] recusa promovê-lo a outro ambiente.
  static const developmentJwtSecret = 'development-secret';

  factory AppConfig.fromEnvironment() =>
      AppConfig.fromMap(Platform.environment);

  /// Mesma leitura, a partir de um mapa qualquer.
  ///
  /// `Platform.environment` não é substituível dentro do processo, então as
  /// regras de validação só são testáveis por aqui. `fromEnvironment()` é um
  /// atalho para o ambiente real.
  factory AppConfig.fromMap(Map<String, String> environment) {
    final appEnv = environment['APP_ENV'] ?? 'development';

    return AppConfig(
      mqttBroker: environment['MQTT_BROKER'] ?? 'localhost:1883',
      jwtSecret: _resolveJwtSecret(environment['JWT_SECRET'], appEnv),
      mqttUsername: environment['MQTT_USERNAME'],
      mqttPassword: environment['MQTT_PASSWORD'],
      mqttUseTls: environment['MQTT_USE_TLS'] == 'true',
      mqttCaCertificatePath: environment['MQTT_CA_CERT_PATH'],
      appEnv: appEnv,
      enableDevLogin: environment['ENABLE_DEV_LOGIN'] == 'true',
    );
  }

  /// Decide o segredo de assinatura, recusando subir com um segredo fraco.
  ///
  /// Só `development` aceita ausência de `JWT_SECRET`. Fora dele a falha é no
  /// boot, e não na primeira requisição: um servidor que sobe assinando com um
  /// segredo público é pior do que um servidor que não sobe.
  ///
  /// A checagem anterior cobria apenas `appEnv == 'production'` e testava só
  /// `== null`, então `JWT_SECRET=""` e `APP_ENV=staging` passavam direto.
  static String _resolveJwtSecret(String? value, String appEnv) {
    final secret = value?.trim();
    final isDevelopment = appEnv == 'development';

    if (secret == null || secret.isEmpty) {
      if (isDevelopment) return developmentJwtSecret;
      throw StateError(
        'JWT_SECRET é obrigatório quando APP_ENV=$appEnv. '
        'Gere um com: openssl rand -hex 32',
      );
    }

    if (secret == developmentJwtSecret && !isDevelopment) {
      throw StateError(
        'JWT_SECRET está usando o valor de desenvolvimento, que é público, '
        'com APP_ENV=$appEnv. Gere um próprio com: openssl rand -hex 32',
      );
    }

    return secret;
  }
}
