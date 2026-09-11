/// Endereços do backend e do broker, configuráveis em tempo de compilação.
///
/// Os defaults apontam para o host da máquina de desenvolvimento visto de
/// dentro do emulador Android (`10.0.2.2`). Para outros alvos:
///
///   flutter run --dart-define=SINALACS_HOST=http://localhost:8080/ \
///               --dart-define=SINALACS_MQTT_HOST=localhost
///
/// As credenciais abaixo são as do `docker-compose.yml` de desenvolvimento e
/// não valem fora dele. Em produção o ACS não deveria carregar segredo do
/// broker embutido no binário — ver a lacuna de mTLS registrada em spec/.
class BackendConfig {
  const BackendConfig._();

  /// A barra final é exigida pelo cliente Serverpod.
  static const String host = String.fromEnvironment(
    'SINALACS_HOST',
    defaultValue: 'http://10.0.2.2:8080/',
  );

  static const String mqttHost = String.fromEnvironment(
    'SINALACS_MQTT_HOST',
    defaultValue: '10.0.2.2',
  );

  /// 8883 é a única porta que o broker publica: TLS, sem WebSocket.
  static const int mqttPort = int.fromEnvironment(
    'SINALACS_MQTT_PORT',
    defaultValue: 8883,
  );

  static const String mqttUsername = String.fromEnvironment(
    'SINALACS_MQTT_USER',
    defaultValue: 'acs-area-12',
  );

  /// Senha do broker.
  ///
  /// **`String.fromEnvironment` é resolvido em tempo de COMPILAÇÃO**: este valor
  /// vira uma constante dentro do binário e é extraível de qualquer APK. O
  /// default existe para que `flutter run` e scripts/qa/e2e.sh funcionem sem
  /// argumentos em desenvolvimento — é uma escolha consciente, não um descuido,
  /// e a senha correspondente do broker local é gerada por
  /// scripts/dev/bootstrap_env.sh, não é esta.
  ///
  /// Em produção credencial de broker não pode viajar dentro do app. A correção
  /// é credencial por dispositivo / mTLS, lacuna registrada em spec/ — o
  /// mosquitto.conf atual nem sequer tem `require_certificate`.
  static const String mqttPassword = String.fromEnvironment(
    'SINALACS_MQTT_PASSWORD',
    defaultValue: 'development-acs-password',
  );

  /// CA que assina o certificado do broker local.
  ///
  /// Copiada para cá por `scripts/dev/sync_dev_ca.sh`; é regerada pelo
  /// mosquitto-init e não é versionada.
  static const String mqttCaAsset = 'assets/certs/dev_ca.crt';
}
