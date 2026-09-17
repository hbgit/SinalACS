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
  ///
  /// Hexadecimal de exatamente 64 caracteres, validado no boot por
  /// [_resolveHealthDataEncryptionKey].
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
  ///
  /// Diferente dos outros dois fallbacks, este PRECISA ser hexadecimal de 64
  /// caracteres (32 bytes): ao contrário de [jwtSecret]/[auditChainSecret],
  /// que são chaves HMAC de tamanho livre, este valor é decodificado byte a
  /// byte por `HealthDataCipher` para virar uma chave AES-256. O literal
  /// anterior era a frase `development-health-data-key`, que não é hex — o
  /// primeiro `encrypt()` em desenvolvimento morria com `FormatException` no
  /// `int.parse(..., radix: 16)`. Ver `.env.example`: produção continua
  /// exigindo `openssl rand -hex 32`, exatamente o mesmo formato.
  static const developmentHealthDataEncryptionKey =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

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
      healthDataEncryptionKey: _resolveHealthDataEncryptionKey(
        value: environment['HEALTH_DATA_ENCRYPTION_KEY'],
        appEnv: appEnv,
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
  /// Regra comum aos três segredos (`JWT_SECRET`, `AUDIT_CHAIN_SECRET` e
  /// `HEALTH_DATA_ENCRYPTION_KEY`, este por
  /// [_resolveHealthDataEncryptionKey], que acrescenta a checagem de
  /// formato): só `development` aceita
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

  /// Hexadecimal de exatamente 64 caracteres — 32 bytes, o tamanho de uma
  /// chave AES-256.
  static final _hex32Bytes = RegExp(r'^[0-9a-fA-F]{64}$');

  /// [_resolveSecret] mais a validação de FORMATO, que só esta chave exige.
  ///
  /// `JWT_SECRET`/`AUDIT_CHAIN_SECRET` são chaves HMAC de tamanho livre: uma
  /// string qualquer serve, e por isso a regra genérica basta para elas. Esta
  /// aqui é decodificada byte a byte por `HealthDataCipher` para virar a chave
  /// AES-256, então um valor de 63 ou de 32 caracteres não é "um segredo mais
  /// fraco", é uma chave inválida.
  ///
  /// Sem esta checagem a falha era silenciosa e tardia, na pior combinação
  /// possível: o servidor subia normalmente, e só a PRIMEIRA GRAVAÇÃO quebrava
  /// — e em `TriageSessionService` essa quebra é capturada de propósito
  /// (classificar o risco não pode depender do disco), então o paciente recebia
  /// o resultado da triagem, ninguém via erro nenhum na tela, e o prontuário
  /// simplesmente não era persistido. Aqui vale o mesmo raciocínio já
  /// documentado em [_resolveSecret]: um servidor que sobe com uma chave de
  /// criptografia malformada é pior do que um servidor que não sobe.
  static String _resolveHealthDataEncryptionKey({
    required String? value,
    required String appEnv,
  }) {
    final key = _resolveSecret(
      value: value,
      appEnv: appEnv,
      envVarName: 'HEALTH_DATA_ENCRYPTION_KEY',
      developmentFallback: developmentHealthDataEncryptionKey,
    );

    if (!_hex32Bytes.hasMatch(key)) {
      throw StateError(
        'HEALTH_DATA_ENCRYPTION_KEY precisa ser hexadecimal de exatamente 64 '
        'caracteres (32 bytes, chave AES-256); veio com ${key.length}. '
        'Gere uma com: openssl rand -hex 32',
      );
    }

    return key;
  }
}
