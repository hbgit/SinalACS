/// Endereço do backend, configurável em tempo de compilação.
///
/// O default é o host da máquina de desenvolvimento visto de dentro do
/// emulador Android (`10.0.2.2`). Para outros alvos:
///
///   flutter run --dart-define=SINALACS_HOST=http://localhost:8080/
///   flutter run --dart-define=SINALACS_HOST=http://192.168.0.10:8080/
///
/// Cleartext HTTP só é permitido em builds de debug e só para esses hosts —
/// ver android/app/src/debug/res/xml/network_security_config.xml.
class BackendConfig {
  const BackendConfig._();

  /// A barra final é exigida pelo cliente Serverpod.
  static const String host = String.fromEnvironment(
    'SINALACS_HOST',
    defaultValue: 'http://10.0.2.2:8080/',
  );
}
