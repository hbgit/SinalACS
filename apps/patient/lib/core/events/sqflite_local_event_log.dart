import '../storage/patient_local_database.dart';
import 'local_event_log.dart';

/// [LocalEventLog] sobre a tabela `local_events` do banco cifrado do paciente
/// (schema v2, #127).
///
/// Toda operação abre (ou reaproveita) o banco por [PatientLocalDatabase.open]
/// e propaga `LocalDatabaseUnavailableException` quando ele não abre, como as
/// outras lojas do banco.
class SqfliteLocalEventLog implements LocalEventLog {
  SqfliteLocalEventLog(this._database);

  static const table = 'local_events';
  final PatientLocalDatabase _database;

  @override
  Future<void> record(LocalEvent event) async {
    final db = await _database.open();
    await db.insert(table, {
      'kind': event.kind.code,
      'occurred_at': event.occurredAt.toUtc().toIso8601String(),
      'engine_version': event.engineVersion,
    });
  }

  @override
  Future<List<LocalEvent>> list() async {
    final db = await _database.open();
    final rows = await db.query(table, orderBy: 'id');
    return [
      for (final row in rows)
        if (LocalEventKind.fromCode(row['kind'] as String) case final kind?)
          LocalEvent(
            kind: kind,
            occurredAt: DateTime.parse(row['occurred_at'] as String),
            engineVersion: row['engine_version'] as String,
          ),
    ];
  }
}
