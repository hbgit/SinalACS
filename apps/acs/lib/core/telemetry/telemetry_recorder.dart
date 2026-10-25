import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';

/// Grava os eventos de telemetria do app (PRD §1.3) na fila local do dono.
///
/// Só contagens, durações e ids opacos: nunca `notes`, `outcome` da visita ou
/// qualquer texto clínico. Nenhum método lança — telemetria não pode derrubar
/// a sincronização nem o registro da visita.
class TelemetryRecorder {
  TelemetryRecorder({
    required TelemetryStore store,
    required String owner,
    NetworkProbe? probe,
    DateTime Function()? clock,
  })  : _store = store,
        _owner = owner,
        _probe = probe ?? connectivityProbe(),
        _clock = clock ?? DateTime.now;

  final TelemetryStore _store;
  final String _owner;
  final NetworkProbe _probe;
  final DateTime Function() _clock;

  /// Milissegundos em UTC: a ordenação ISO-8601 não inverte com micros.
  DateTime _now() =>
      DateTime.fromMillisecondsSinceEpoch(_clock().millisecondsSinceEpoch, isUtc: true);

  Future<NetworkKind> _network() async {
    try {
      return await _probe();
    } catch (_) {
      return NetworkKind.unknown;
    }
  }

  Future<String?> _append(String name, Map<String, Object?> payload) async {
    try {
      final id = newRandomUuid();
      await _store.append(TelemetryEventRecord(
        eventId: id,
        owner: _owner,
        name: name,
        occurredAt: _now(),
        payload: payload,
      ));
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Devolve o `eventId` (para o `sync_result` ligar) ou `null` se não gravou.
  /// `recordsCount <= 0` não grava: o servidor aceita de 1 a 10000.
  Future<String?> syncAttempt({required int recordsCount}) async {
    if (recordsCount <= 0) return null;
    final kind = await _network();
    return _append('sync_attempt', {
      'records_count': recordsCount > 10000 ? 10000 : recordsCount,
      'network_type': kind.wireName,
      'channel': 'sync',
    });
  }

  Future<void> syncResult({
    required String? attemptEventId,
    required int successCount,
    required int failureCount,
    required int conflictCount,
    required int rejectedCount,
    required String outcome,
    required bool transportError,
    required Duration duration,
  }) async {
    if (attemptEventId == null) return;
    await _append('sync_result', {
      'attempt_event_id': attemptEventId,
      'success_count': successCount,
      'failure_count': failureCount,
      'conflict_count': conflictCount,
      'rejected_count': rejectedCount,
      'outcome': outcome,
      'transport_error': transportError,
      'duration_ms': duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds,
    });
  }

  Future<void> visitRegistered({required OfflineVisitRecord visit, String? alertId}) async {
    final kind = await _network();
    await _append('visit_registered', {
      'local_id': visit.localId,
      'patient_id': visit.patientId,
      'visit_type': alertId == null ? 'routine' : 'alert',
      if (alertId != null) 'alert_id': alertId,
      'offline_flag': kind == NetworkKind.none,
      'network_type': kind.wireName,
      'sync_status': 'queued',
    });
  }
}
