import 'package:connectivity_plus/connectivity_plus.dart';

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

/// Sonda real, sobre `connectivity_plus`. Nunca lança: erro vira `unknown`.
NetworkProbe connectivityProbe([Connectivity? connectivity]) {
  return () async {
    try {
      final results = await (connectivity ?? Connectivity()).checkConnectivity();
      return networkKindOf(results);
    } catch (_) {
      return NetworkKind.unknown;
    }
  };
}

/// Prioridade com várias redes: wifi > ethernet > mobile > vpn > other.
/// Lista vazia ou só `none` é `none`.
NetworkKind networkKindOf(List<ConnectivityResult> results) {
  final kinds = {
    for (final r in results)
      switch (r) {
        ConnectivityResult.wifi => NetworkKind.wifi,
        ConnectivityResult.ethernet => NetworkKind.ethernet,
        ConnectivityResult.mobile => NetworkKind.mobile,
        ConnectivityResult.vpn => NetworkKind.vpn,
        ConnectivityResult.none => NetworkKind.none,
        _ => NetworkKind.other,
      },
  };
  for (final k in const [
    NetworkKind.wifi,
    NetworkKind.ethernet,
    NetworkKind.mobile,
    NetworkKind.vpn,
    NetworkKind.other,
  ]) {
    if (kinds.contains(k)) return k;
  }
  return NetworkKind.none;
}
