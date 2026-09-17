import 'dart:io';

/// Configuração que **não** vem do Serverpod.
///
/// Banco e servidor são configurados por `config/*.yaml` mais as variáveis
/// `SERVERPOD_*`. O que sobra — MQTT e os segredos de autenticação/auditoria —
/// é lido aqui.
class AppConfig {
  const AppConfig({
    required this.mqttBroker,
    required this.jwtSecret,
    required this.auditChainSecret,
    required this.healthDataEncryptionKey,
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

  /// Chave HMAC da cadeia de hash de `audit_logs` (ver `application/audit/`).
  ///
  /// Deliberadamente um segredo PRÓPRIO, não derivado de [jwtSecret]: rotacionar
  /// o JWT é rotina esperada, mas rotacionar este invalida silenciosamente a
  /// verificação de tudo que já foi gravado na trilha. Ver
  /// [_resolveAuditChainSecret].
  final String auditChainSecret;

  /// Chave AES-256-GCM que cifra `patients.chronicConditions`,
  /// `triage_sessions.answers` e `visits.notes` (RNF03, INV-04). Segredo
  /// PRÓPRIO — nunca derivado de `jwtSecret`/`auditChainSecret`: rotacionar
  /// um não pode invalidar o outro.
  final String healthDataEncryptionKey;

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

  /// Segredo usado quando `AUDIT_CHAIN_SECRET` não é informado em
  /// desenvolvimento. Mesma regra de [developmentJwtSecret]: público, e por
  /// isso restrito a `development` por [_resolveAuditChainSecret].
  static const developmentAuditChainSecret = 'development-audit-chain-secret';

  /// Segredo usado quando `HEALTH_DATA_ENCRYPTION_KEY` não é informado em
  /// desenvolvimento. Mesma regra de [developmentJwtSecret]: público, e por
  /// isso restrito a `development` por [_resolveSecret].
  static const developmentHealthDataEncryptionKey =
      'development-health-data-key';

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
      jwtSecret: _resolveSecret(
        value: environment['JWT_SECRET'],
        appEnv: appEnv,
        envVarName: 'JWT_SECRET',
        developmentFallback: developmentJwtSecret,
      ),
      auditChainSecret: _resolveSecret(
        value: environment['AUDIT_CHAIN_SECRET'],
        appEnv: appEnv,
        envVarName: 'AUDIT_CHAIN_SECRET',
        developmentFallback: developmentAuditChainSecret,
      ),
      healthDataEncryptionKey: _resolveSecret(
        value: environment['HEALTH_DATA_ENCRYPTION_KEY'],
        appEnv: appEnv,
        envVarName: 'HEALTH_DATA_ENCRYPTION_KEY',
        developmentFallback: developmentHealthDataEncryptionKey,
      ),
      mqttUsername: environment['MQTT_USERNAME'],
      mqttPassword: environment['MQTT_PASSWORD'],
      mqttUseTls: environment['MQTT_USE_TLS'] == 'true',
      mqttCaCertificatePath: environment['MQTT_CA_CERT_PATH'],
      appEnv: appEnv,
      enableDevLogin: environment['ENABLE_DEV_LOGIN'] == 'true',
    );
  }

  /// Decide um segredo de assinatura, recusando subir com um valor fraco.
  ///
  /// Regra comum a `JWT_SECRET` e `AUDIT_CHAIN_SECRET`: só `development` aceita
  /// ausência da variável. Fora dele a falha é no boot, e não na primeira
  /// requisição — um servidor que sobe assinando com um segredo público é pior
  /// do que um servidor que não sobe.
  ///
  /// A checagem anterior (antes de existir mais de um segredo) cobria apenas
  /// `appEnv == 'production'` e testava só `== null`, então `JWT_SECRET=""` e
  /// `APP_ENV=staging` passavam direto.
  static String _resolveSecret({
    required String? value,
    required String appEnv,
    required String envVarName,
    required String developmentFallback,
  }) {
    final secret = value?.trim();
    final isDevelopment = appEnv == 'development';

    if (secret == null || secret.isEmpty) {
      if (isDevelopment) return developmentFallback;
      throw StateError(
        '$envVarName é obrigatório quando APP_ENV=$appEnv. '
        'Gere um com: openssl rand -hex 32',
      );
    }

    if (secret == developmentFallback && !isDevelopment) {
      throw StateError(
        '$envVarName está usando o valor de desenvolvimento, que é público, '
        'com APP_ENV=$appEnv. Gere um próprio com: openssl rand -hex 32',
      );
    }

    return secret;
  }
}
