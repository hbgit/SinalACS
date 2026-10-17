import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

/// Reserva por HTTP dos alertas (#80, R2): lê os alertas abertos da microárea
/// pelo RPC e os funde na mesma [AlertQueue] que o MQTT alimenta.
///
/// Só a consulta mora aqui; nenhum `Timer`. Quem agenda é o dono do ciclo de
/// vida (`AcsHomeShell`), que sabe quando o broker caiu e quando o app foi
/// para o segundo plano — mesma divisão de `ReconnectSchedule`.
class AlertHttpFallback {
  AlertHttpFallback({required AcsBackend backend, required AlertQueue queue})
      : _backend = backend,
        _queue = queue;

  final AcsBackend _backend;
  final AlertQueue _queue;

  /// Devolve quantos cartões foram criados ou mudaram. Uma falha do backend
  /// sobe como veio ([BackendFailure]) e não toca na fila.
  Future<int> poll() async {
    final abertos = await _backend.openAlerts();
    return _queue.mergeFromServer(abertos.map(PrioritizedAlert.fromServer));
  }
}
