import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

/// `offline_visits` exatamente como a v6 a criava: sem a coluna `owner`.
const createOfflineVisitsV6 = '''
CREATE TABLE IF NOT EXISTS offline_visits (
  local_id TEXT PRIMARY KEY,
  patient_id TEXT NOT NULL,
  risk TEXT NOT NULL,
  status TEXT NOT NULL,
  outcome TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  version INTEGER NOT NULL,
  rejection_reason TEXT
)''';

/// Uma linha de visita no formato da v6 (sem dono). Dado SINTÉTICO.
Map<String, Object?> legacyV6Row({
  required String localId,
  required String patientId,
  String notes = '',
  String? rejectionReason,
  DateTime? createdAt,
}) =>
    {
      'local_id': localId,
      'patient_id': patientId,
      'risk': 'yellow',
      'status': 'PENDENTE',
      'outcome': '',
      'notes': notes,
      'created_at': (createdAt ?? DateTime.utc(2026, 9, 1, 12)).toIso8601String(),
      'version': 1,
      'rejection_reason': rejectionReason,
    };

/// Cria NO APARELHO, com o SQLCipher real e a [passphrase] dada, um banco com
/// o schema completo da v6 (`offline_visits` sem `owner`, `sync_cursor`,
/// `micro_area_cache`, `micro_area_cache_meta`, `user_version` = 6) e grava
/// [rows] em `offline_visits` e [cacheRows] em `micro_area_cache`. É o arquivo
/// que um aparelho com o app anterior tem; o app novo o abre e migra para a v7.
Future<void> createV6Database({
  required String databaseName,
  required String passphrase,
  required List<Map<String, Object?>> rows,
  List<Map<String, Object?>> cacheRows = const [],
  Map<String, String> cursor = const {},
}) async {
  final path = await EncryptedLocalDatabase.pathFor(databaseName);
  final db = await sqlcipher.openDatabase(
    path,
    password: passphrase,
    version: 6,
    onCreate: (db, version) async {
      await db.execute(createOfflineVisitsV6);
      await db.execute(EncryptedLocalDatabase.createSyncCursor);
      await db.execute(EncryptedLocalDatabase.createMicroAreaCache);
      await db.execute(EncryptedLocalDatabase.createMicroAreaCacheMeta);
    },
  );
  for (final row in rows) {
    await db.insert('offline_visits', row);
  }
  for (final row in cacheRows) {
    await db.insert('micro_area_cache', row);
  }
  for (final MapEntry(:key, :value) in cursor.entries) {
    await db.insert('sync_cursor', {'key': key, 'value': value});
  }
  await db.close();
}
