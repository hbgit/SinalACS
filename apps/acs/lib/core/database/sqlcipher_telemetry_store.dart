import 'dart:convert';

import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart' show requireOwnerId;
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

const _table = 'telemetry_events';

/// Fila de telemetria na base SQLCipher das visitas (schema v9). Uma linha de
/// telemetria nunca conta para a recusa de "Limpar este aparelho"
/// (`WipeBlocked` olha só `offline_visits`); o wipe a apaga.
class SqlCipherTelemetryStore implements TelemetryStore {
  SqlCipherTelemetryStore(this._database, {this.maxPerOwner = maxTelemetryEventsPerOwner});

  final VisitDatabase _database;
  final int maxPerOwner;

  @override
  Future<void> append(TelemetryEventRecord e) async {
    requireOwnerId(e.owner);
    final db = await _database.open();
    await db.transaction((txn) async {
      await txn.insert(
        _table,
        {
          'event_id': e.eventId,
          'owner': e.owner,
          'name': e.name,
          'occurred_at': e.occurredAt.toUtc().toIso8601String(),
          'payload': jsonEncode(e.payload),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.rawDelete(
        'DELETE FROM $_table WHERE event_id IN ('
        'SELECT event_id FROM $_table WHERE owner = ? '
        'ORDER BY occurred_at DESC, rowid DESC LIMIT -1 OFFSET ?)',
        [e.owner, maxPerOwner],
      );
    });
  }

  @override
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}) async {
    requireOwnerId(owner);
    final db = await _database.open();
    final rows = await db.query(
      _table,
      where: 'owner = ?',
      whereArgs: [owner],
      orderBy: 'occurred_at, rowid',
      limit: limit,
    );
    return [
      for (final row in rows)
        TelemetryEventRecord(
          eventId: row['event_id']! as String,
          owner: row['owner']! as String,
          name: row['name']! as String,
          occurredAt: DateTime.parse(row['occurred_at']! as String).toUtc(),
          payload: Map<String, Object?>.from(jsonDecode(row['payload']! as String) as Map),
        ),
    ];
  }

  @override
  Future<void> deleteByIds(Iterable<String> ids) async {
    final lista = ids.toList();
    if (lista.isEmpty) return;
    final db = await _database.open();
    await db.transaction((txn) async {
      // Lotes abaixo do limite de variáveis do SQLite.
      for (var i = 0; i < lista.length; i += 500) {
        final lote = lista.sublist(i, i + 500 > lista.length ? lista.length : i + 500);
        await txn.delete(_table, where: 'event_id IN (${List.filled(lote.length, '?').join(',')})', whereArgs: lote);
      }
    });
  }

  @override
  Future<int> countForOwner(String owner) async {
    requireOwnerId(owner);
    final db = await _database.open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $_table WHERE owner = ?', [owner]);
    return rows.single['total']! as int;
  }
}
