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
    required this.cpfHashPepper,
    required this.smsGateway,
    required this.mqttUsername,
    required this.mqttPassword,
    required this.mqttUseTls,
    required this.mqttCaCertificatePath,
    this.mqttClientCertificatePath,
    this.mqttClientKeyPath,
    required this.appEnv,
    required this.enableDevLogin,
    this.requireAcsMfa = false,
    this.gorushUrl,
  });

  final String mqttBroker;

  /// Endereço do Gorush, o relé de push para FCM/APNs (RF14, decisão §3.2), sem
  /// barra final. `null` desliga o envio de avisos: o backend sobe e responde
  /// tudo o mais, e `notices.sendSegmented` recusa com uma mensagem clara.
  final String? gorushUrl;

  /// Tempo máximo de uma chamada ao Gorush, do connect à resposta inteira.
  Duration get gorushTimeout => const Duration(seconds: 5);

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

  /// Pepper do HMAC de `users.cpfHash` e do hash do código OTP (RF01).
  ///
  /// `spec/lgpd_data_audit.md:196` nomeia esta variável e a torna obrigatória:
  /// o CPF tem 10^9 valores possíveis, então um hash sem segredo é revertido
  /// por força bruta em segundos a partir de um dump do banco. Segredo PRÓPRIO,
  /// não derivado de `jwtSecret`/`auditChainSecret`/`healthDataEncryptionKey`:
  /// rotacionar o pepper invalida os hashes de CPF gravados (é uma migração de
  /// dados, não uma operação silenciosa) e não pode arrastar a trilha de
  /// auditoria nem os tokens junto.
  ///
  /// O hash do código OTP usa o MESMO pepper, com campo de domínio próprio. A
  /// independência de segredos que o resto deste arquivo prega existe para
  /// dado de vida longa; um OTP vive 5 minutos, e rotacionar o pepper
  /// simplesmente o invalida — que é o efeito desejado. Ver `HmacCpfHasher`.
  final String cpfHashPepper;

  /// Gateway de SMS do login passwordless (RF01).
  ///
  /// `log` só é aceito em `development`: ele **não envia SMS**, escreve o
  /// código no log do processo para o desenvolvedor conseguir entrar. Fora de
  /// desenvolvimento, ausência ou valor desconhecido falha no boot — um
  /// servidor que sobe sem conseguir enviar código deixa todo paciente sem
  /// login, e falhar cedo é melhor que falhar no primeiro cadastro real.
  final String smsGateway;

  final String? mqttUsername;
  final String? mqttPassword;
  final bool mqttUseTls;
  final String? mqttCaCertificatePath;

  /// Certificado e chave de CLIENTE para o mTLS do broker (`MQTT_CLIENT_CERT_PATH`
  /// e `MQTT_CLIENT_KEY_PATH`). Vêm sempre juntos; fora de `development` com
  /// TLS são obrigatórios.
  final String? mqttClientCertificatePath;
  final String? mqttClientKeyPath;
  final String appEnv;
  final bool enableDevLogin;

  /// `REQUIRE_ACS_MFA`: ACS sem MFA (TOTP) ativa não entra pelo login
  /// institucional; precisa ativá-la antes. Padrão **ligado fora de
  /// `development`** ([resolveRequireAcsMfa]). O default do construtor é
  /// `false` só para as configurações montadas à mão nos testes.
  final bool requireAcsMfa;

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

  /// Pepper de desenvolvimento. Público, como os outros fallbacks — e por isso
  /// restrito a `development` por [_resolveSecret].
  static const developmentCpfHashPepper = 'development-cpf-hash-pepper';

  static const _knownSmsGateways = {'log'};

  /// Aceita apenas os gateways implementados, e `log` apenas em `development`.
  static String _resolveSmsGateway({
    required String? value,
    required String appEnv,
  }) {
    final gateway = value?.trim().toLowerCase();
    final isDevelopment = appEnv == 'development';

    if (gateway == null || gateway.isEmpty) {
      if (isDevelopment) return 'log';
      throw StateError(
        'SMS_GATEWAY é obrigatório quando APP_ENV=$appEnv: sem um gateway '
        'configurado, nenhum paciente consegue receber o código de acesso.',
      );
    }

    if (!_knownSmsGateways.contains(gateway)) {
      throw StateError(
        'SMS_GATEWAY="$gateway" não corresponde a nenhum gateway implementado '
        '(${_knownSmsGateways.join(', ')}).',
      );
    }

    if (gateway == 'log' && !isDevelopment) {
      throw StateError(
        'SMS_GATEWAY=log não envia SMS nenhum e por isso só vale em '
        'development; APP_ENV=$appEnv. Configure um gateway real.',
      );
    }

    return gateway;
  }

  factory AppConfig.fromEnvironment() =>
      AppConfig.fromMap(Platform.environment);

  static String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;

  /// Mesma leitura, a partir de um mapa qualquer.
  ///
  /// `Platform.environment` não é substituível dentro do processo, então as
  /// regras de validação só são testáveis por aqui. `fromEnvironment()` é um
  /// atalho para o ambiente real.
  factory AppConfig.fromMap(Map<String, String> environment) {
    final appEnv = environment['APP_ENV'] ?? 'development';

    final mqttUseTls = environment['MQTT_USE_TLS'] == 'true';
    final mqttClientCert = _blankToNull(environment['MQTT_CLIENT_CERT_PATH']);
    final mqttClientKey = _blankToNull(environment['MQTT_CLIENT_KEY_PATH']);
    if ((mqttClientCert == null) != (mqttClientKey == null)) {
      throw StateError(
        'MQTT_CLIENT_CERT_PATH e MQTT_CLIENT_KEY_PATH devem vir juntos.',
      );
    }
    if (appEnv != 'development' && mqttUseTls && mqttClientCert == null) {
      throw StateError(
        'MQTT_CLIENT_CERT_PATH e MQTT_CLIENT_KEY_PATH são obrigatórios '
        'fora de development com MQTT_USE_TLS=true (mTLS do broker).',
      );
    }

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
      cpfHashPepper: _resolveSecret(
        value: environment['CPF_HASH_PEPPER'],
        appEnv: appEnv,
        envVarName: 'CPF_HASH_PEPPER',
        developmentFallback: developmentCpfHashPepper,
      ),
      smsGateway: _resolveSmsGateway(
        value: environment['SMS_GATEWAY'],
        appEnv: appEnv,
      ),
      mqttUsername: environment['MQTT_USERNAME'],
      mqttPassword: environment['MQTT_PASSWORD'],
      mqttUseTls: mqttUseTls,
      mqttCaCertificatePath: environment['MQTT_CA_CERT_PATH'],
      mqttClientCertificatePath: mqttClientCert,
      mqttClientKeyPath: mqttClientKey,
      appEnv: appEnv,
      enableDevLogin: environment['ENABLE_DEV_LOGIN'] == 'true',
      requireAcsMfa: resolveRequireAcsMfa(
        value: environment['REQUIRE_ACS_MFA'],
        appEnv: appEnv,
      ),
      gorushUrl: _resolveGorushUrl(environment['GORUSH_URL']),
    );
  }

  /// Com a variável presente, só a string exata `true` liga (mesma regra de
  /// `ENABLE_DEV_LOGIN`). Ausente, vale `true` em todo ambiente que não seja
  /// `development`: esquecer a variável em produção não pode desligar a MFA.
  static bool resolveRequireAcsMfa({required String? value, required String appEnv}) =>
      value != null ? value == 'true' : appEnv != 'development';

  static String? _resolveGorushUrl(String? value) {
    var url = value?.trim() ?? '';
    if (url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw StateError('GORUSH_URL deve começar com http:// ou https://.');
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Decide um segredo de assinatura, recusando subir com um valor fraco.
  ///
  /// Regra comum aos quatro segredos (`JWT_SECRET`, `AUDIT_CHAIN_SECRET`,
  /// `CPF_HASH_PEPPER` e `HEALTH_DATA_ENCRYPTION_KEY`, este por
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
