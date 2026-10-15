import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Esquema de `data_subject_requests` contra Postgres real: as colunas de
/// decisão (#42) existem e são todas anuláveis, para que pedidos já abertos
/// continuem válidos sem backfill.
void main() {
  withServerpod('Dado o esquema de data_subject_requests', (
    sessionBuilder,
    endpoints,
  ) {
    test('tem as colunas de decisão, todas anuláveis', () async {
      final session = sessionBuilder.build();
      final rows = await session.db.unsafeQuery(
        "select column_name, is_nullable from information_schema.columns "
        "where table_name = 'data_subject_requests'",
      );
      final byName = {
        for (final r in rows)
          r.toColumnMap()['column_name']: r.toColumnMap()['is_nullable'],
      };
      for (final c in [
        'decidedAt',
        'decidedBy',
        'resolutionEncrypted',
        'resolutionKeyVersion',
      ]) {
        expect(byName[c], 'YES', reason: c);
      }
    });
  });
}
