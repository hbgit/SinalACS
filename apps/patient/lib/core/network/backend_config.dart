/// Endereço do backend, configurável em tempo de compilação.
///
/// O default é o host da máquina de desenvolvimento visto de dentro do
/// emulador Android (`10.0.2.2`). Para outros alvos:
///
///   flutter run --dart-define=SINALACS_HOST=https://localhost/
///   flutter run --dart-define=SINALACS_HOST=https://192.168.0.10/
///
/// O RPC é **HTTPS na 443** (RNF04/L-08): a porta 8080 em texto claro deixou de
/// ser publicada e quem termina TLS é o Traefik, com um certificado de
/// desenvolvimento assinado por [rpcCaAsset]. A exceção de cleartext que existia
/// em android/app/src/debug/res/xml/network_security_config.xml foi REMOVIDA,
/// não restringida: não há mais caminho sem criptografia para liberar.
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

  /// CA que assina o certificado do Traefik em :443 (RNF04).
  ///
  /// Copiada para cá por `scripts/dev/sync_dev_ca.sh`; o arquivo é gerado pelo
  /// `traefik-init`, não é versionado e só existe depois do sync. É passada ao
  /// `BackendClient` como **única** raiz confiável — o armazenamento do sistema
  /// não conhece esta CA.
  static const String rpcCaAsset = 'assets/certs/dev_rpc_ca.crt';
}
