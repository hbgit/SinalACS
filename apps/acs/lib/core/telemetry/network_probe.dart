// Dart puro de propósito: `offline_visit_queue.dart` importa o gravador, que
// importa este arquivo, e a fila roda também na VM (`tool/live_check.dart`,
// instrumento do RNF02). A sonda real, sobre `connectivity_plus` (Flutter),
// mora em `connectivity_network_probe.dart` e só o app a liga —
// `test/session_store_wiring_test.dart` guarda o caminho.

/// Tipo de rede no momento do evento (domínio de `network_type`, PRD §1.3).
enum NetworkKind {
  wifi,
  mobile,
  ethernet,
  vpn,
  none,
  other,
  unknown;

  /// O servidor valida contra estes nomes; é o próprio nome do enum.
  String get wireName => name;
}

typedef NetworkProbe = Future<NetworkKind> Function();
