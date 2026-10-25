import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';

// Puxa o Flutter (`connectivity_plus`): fora do caminho da fila de visitas e do
// gravador, que rodam também na VM. Quem liga esta sonda é a fábrica de
// produção (`visit_queue_factory.dart`).

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
