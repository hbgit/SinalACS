/// Endereços do backend e do broker, configuráveis em tempo de compilação.
///
/// Os defaults apontam para o host da máquina de desenvolvimento visto de
/// dentro do emulador Android (`10.0.2.2`). Para outros alvos:
///
///   flutter run --dart-define=SINALACS_HOST=https://localhost/ \
///               --dart-define=SINALACS_MQTT_HOST=localhost
///
/// O RPC é **HTTPS na 443** (RNF04/L-08): a porta 8080 em texto claro deixou de
/// ser publicada e quem termina TLS é o Traefik, com um certificado de
/// desenvolvimento assinado por [rpcCaAsset]. A exceção de cleartext que existia
/// em android/app/src/debug/res/xml/network_security_config.xml foi REMOVIDA,
/// não restringida: não há mais caminho sem criptografia para liberar.
///
/// O broker não tem senha para o ACS (#94): o aparelho se autentica pelo
/// certificado de cliente que o backend emite para ele
/// (`DeviceCertificateEnroller`) e que fica no Keystore. Nenhum segredo do
/// broker viaja dentro do binário.
class BackendConfig {
  const BackendConfig._();

  /// A barra final é exigida pelo cliente Serverpod.
  ///
  /// O default é **https na 443**: a porta 8080 em texto claro deixou de ser
  /// publicada (RNF04/L-08), e quem termina TLS é o Traefik. Continua sendo o
  /// host da máquina de desenvolvimento visto de dentro do emulador.
  static const String host = String.fromEnvironment(
    'SINALACS_HOST',
    defaultValue: 'https://10.0.2.2/',
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

  /// CA que assina o certificado do broker local.
  ///
  /// Copiada para cá por `scripts/dev/sync_dev_ca.sh`; é regerada pelo
  /// mosquitto-init e não é versionada.
  static const String mqttCaAsset = 'assets/certs/dev_ca.crt';

  /// CA que assina o certificado do Traefik em :443 (RNF04).
  ///
  /// Não confundir com [mqttCaAsset], que é a CA do broker. São duas, e o
  /// `sync_dev_ca.sh` copia as duas.
  static const String rpcCaAsset = 'assets/certs/dev_rpc_ca.crt';
}
