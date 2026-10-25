import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_service.dart';

/// [TelemetryStore] sobre SQL parametrizado do Serverpod (#83).
///
/// Idempotente: o índice único `telemetry_events_event_id_key` faz o reenvio
/// do mesmo `eventId` cair em `ON CONFLICT DO NOTHING`. Sem transação própria:
/// participa da [transaction] quando ela é fornecida.
class OrmTelemetryStore implements TelemetryStore {
  OrmTelemetryStore(this._session, {Transaction? transaction})
    : _transaction = transaction;

  final Session _session;
  final Transaction? _transaction;

  /// 13 parâmetros por linha; 500 linhas ficam muito abaixo do teto do Postgres.
  static const _chunk = 500;

  @override
  Future<Set<String>> insertIgnoringDuplicates(
    List<TelemetryRecord> records,
  ) async {
    if (records.isEmpty) return <String>{};

    final present = <String>{};
    for (var start = 0; start < records.length; start += _chunk) {
      final end = start + _chunk > records.length
          ? records.length
          : start + _chunk;
      final chunk = records.sublist(start, end);

      final params = <String, Object?>{};
      final rows = <String>[];
      for (var i = 0; i < chunk.length; i++) {
        final r = chunk[i];
        params['id$i'] = r.eventId;
        params['name$i'] = r.eventName;
        params['src$i'] = r.source.name;
        params['occ$i'] = r.occurredAt.toUtc();
        params['rec$i'] = r.receivedAt.toUtc();
        params['skew$i'] = r.clockSkewMs;
        params['actor$i'] = r.actorId;
        params['dev$i'] = r.devicePseudonym;
        params['pat$i'] = r.patientPseudonym;
        params['alert$i'] = r.alertId;
        params['ver$i'] = r.appVersion;
        params['pay$i'] = jsonEncode(r.payload);
        rows.add(
          '(@id$i::uuid, @name$i::text, 1, @src$i::text, @occ$i::timestamp, '
          '@rec$i::timestamp, @skew$i::bigint, @actor$i::uuid, @dev$i::text, '
          '@pat$i::text, @alert$i::uuid, @ver$i::text, @pay$i::text)',
        );
      }

      await _session.db.unsafeExecute(
        'INSERT INTO telemetry_events ("eventId", "eventName", "schemaVersion", '
        '"source", "occurredAt", "receivedAt", "clockSkewMs", "actorId", '
        '"devicePseudonym", "patientPseudonym", "alertId", "appVersion", '
        '"payload") VALUES ${rows.join(', ')} '
        'ON CONFLICT ("eventId") DO NOTHING',
        parameters: QueryParameters.named(params),
        transaction: _transaction,
      );

      final found = await _session.db.unsafeQuery(
        'SELECT "eventId"::text AS id FROM telemetry_events '
        'WHERE "eventId" = ANY(@ids::uuid[])',
        parameters: QueryParameters.named({
          'ids': [for (final r in chunk) r.eventId],
        }),
        transaction: _transaction,
      );
      present.addAll(found.map((row) => row.toColumnMap()['id']! as String));
    }
    return present;
  }
}
