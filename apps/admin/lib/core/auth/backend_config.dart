/// Endereço do backend, configurável em tempo de compilação.
///
///   flutter run --dart-define=SINALACS_HOST=https://localhost/
///
/// O default é o host da máquina de desenvolvimento visto de dentro do
/// emulador Android. O RPC é **HTTPS** (RNF04): [requireSecureHost] recusa
/// `http://`, para que um `--dart-define` em texto claro não suba calado.
class AdminBackendConfig {
  const AdminBackendConfig._();

  /// A barra final é exigida pelo cliente Serverpod.
  static const String host = String.fromEnvironment(
    'SINALACS_HOST',
    defaultValue: 'https://10.0.2.2/',
  );

  /// Devolve [host] se for https; senão lança [FormatException].
  /// Função pura de propósito: é onde o defeito "aceitar http" fica
  /// vermelho num teste hermético (a constante acima é de compilação).
  static String requireSecureHost(String host) {
    final uri = Uri.tryParse(host);
    if (uri == null || !uri.isScheme('https')) {
      throw FormatException(
        'O endereço do backend ($host) não está em HTTPS. '
        'Use https://… em SINALACS_HOST (RNF04).',
      );
    }
    return host;
  }
}
