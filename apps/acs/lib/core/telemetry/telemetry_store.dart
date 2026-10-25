import 'package:sinalacs_acs/core/services/owner_id.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';

/// Teto da fila local, por dono: acima disso o `append` apaga os mais antigos
/// DO MESMO dono (aparelho offline por muito tempo não cresce sem limite).
const maxTelemetryEventsPerOwner = 5000;

/// Fila local de eventos de telemetria, separada por dono.
abstract interface class TelemetryStore {
  /// Grava o evento. `eventId` já existente é ignorado, sem lançar.
  Future<void> append(TelemetryEventRecord e);

  /// Os [limit] eventos mais antigos do [owner] (por `occurredAt`).
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit});

  /// Remove os eventos com esses ids; id desconhecido é ignorado.
  Future<void> deleteByIds(Iterable<String> ids);

  Future<int> countForOwner(String owner);
}

class InMemoryTelemetryStore implements TelemetryStore {
  InMemoryTelemetryStore({this.maxPerOwner = maxTelemetryEventsPerOwner});

  final int maxPerOwner;
  final List<TelemetryEventRecord> _events = [];

  @override
  Future<void> append(TelemetryEventRecord e) async {
    requireOwnerId(e.owner);
    if (_events.any((x) => x.eventId == e.eventId)) return;
    _events.add(e);
    final doDono = _sorted(e.owner);
    final excesso = doDono.length - maxPerOwner;
    if (excesso > 0) doDono.take(excesso).forEach(_events.remove);
  }

  List<TelemetryEventRecord> _sorted(String owner) {
    // `sort` do Dart não é estável: o índice de inserção desempata.
    final indexed = [
      for (var i = 0; i < _events.length; i++)
        if (_events[i].owner == owner) (i, _events[i]),
    ]..sort((a, b) {
        final byTime = a.$2.occurredAt.compareTo(b.$2.occurredAt);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, e) in indexed) e];
  }

  @override
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}) async =>
      _sorted(requireOwnerId(owner)).take(limit).toList();

  @override
  Future<void> deleteByIds(Iterable<String> ids) async {
    final set = ids.toSet();
    _events.removeWhere((e) => set.contains(e.eventId));
  }

  @override
  Future<int> countForOwner(String owner) async => _sorted(requireOwnerId(owner)).length;
}
