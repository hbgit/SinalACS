import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_telemetry_store.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Idempotência do store de telemetria (#83). Dados sintéticos.
String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

TelemetryRecord _rec(int n) => TelemetryRecord(
  eventId: _id(n),
  eventName: 'sync_result',
  source: TelemetrySource.acsApp,
  occurredAt: DateTime.utc(2026, 10, 25, 12),
  receivedAt: DateTime.utc(2026, 10, 25, 12, 0, 1),
  clockSkewMs: 1000,
  devicePseudonym: 'dev$n',
  appVersion: '1.0.0',
  payload: {'n': n, 'ok': true},
);

void main() {
  withServerpod('OrmTelemetryStore', (sessionBuilder, _) {
    late Session session;
    late OrmTelemetryStore store;

    Future<int> count() async {
      final r = await session.db.unsafeQuery(
        'SELECT count(*) AS c FROM telemetry_events',
      );
      return r.single.toColumnMap()['c']! as int;
    }

    setUp(() {
      session = sessionBuilder.build();
      store = OrmTelemetryStore(session);
    });

    test('lote vazio devolve vazio', () async {
      expect(await store.insertIgnoringDuplicates([]), isEmpty);
    });

    test('grava o lote e devolve todos os ids', () async {
      final ids = await store.insertIgnoringDuplicates([_rec(1), _rec(2)]);
      expect(ids, {_id(1), _id(2)});
      expect(await count(), 2);
    });

    test('reenvio do mesmo eventId não duplica', () async {
      final a = await store.insertIgnoringDuplicates([_rec(1), _rec(2)]);
      final b = await store.insertIgnoringDuplicates([_rec(1), _rec(2)]);
      expect(b, a);
      expect(await count(), 2);
    });

    test('lote misto novo+repetido grava só os novos', () async {
      await store.insertIgnoringDuplicates([_rec(1)]);
      final ids = await store.insertIgnoringDuplicates([_rec(1), _rec(2)]);
      expect(ids, {_id(1), _id(2)});
      expect(await count(), 2);
    });

    test('payload sai como JSON válido', () async {
      await store.insertIgnoringDuplicates([_rec(1)]);
      final r = await session.db.unsafeQuery(
        'SELECT payload::jsonb->>\'n\' AS n, "schemaVersion" AS v, source AS s '
        'FROM telemetry_events',
      );
      final m = r.single.toColumnMap();
      expect(m['n'], '1');
      expect(m['v'], 1);
      expect(m['s'], 'acsApp');
    });
  });
}
