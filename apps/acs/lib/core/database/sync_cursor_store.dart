import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm, Database;

/// Cursor de `visits.pull` por instalação do app (decisão §5.4: "cursor por
/// dispositivo, não por usuário" — reinstalar não deve perder nem duplicar).
/// Vive no mesmo banco criptografado das visitas offline: é dado
/// operacional do dispositivo, sob a mesma política de proteção.
class SyncCursorStore {
  SyncCursorStore({
    required DatabaseKeyStore keyStore,
    this.databaseName = 'sinalacs_acs.db',
    this.allowUnencryptedForTesting = false,
  }) : _keyStore = keyStore;

  static const _table = 'sync_cursor';
  static const _visitsPullKey = 'visits_pull';

  final DatabaseKeyStore _keyStore;
  final String databaseName;
  final bool allowUnencryptedForTesting;
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    final passphrase = await _keyStore.readOrCreate();
    return _database = await EncryptedLocalDatabase.open(
      databaseName: databaseName,
      passphrase: passphrase,
      allowUnencryptedForTesting: allowUnencryptedForTesting,
    );
  }

  /// Devolve o `since` da última chamada bem-sucedida a `visits.pull`, ou
  /// `null` na primeira sincronização — quem chama trata isso como "desde o
  /// início dos tempos" (ou uma janela inicial definida por produto), nunca
  /// como erro.
  Future<DateTime?> read() async {
    final db = await _open();
    final rows = await db.query(_table, where: 'key = ?', whereArgs: [_visitsPullKey]);
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['value'] as String);
  }

  /// Grava o cursor, substituindo o valor anterior.
  Future<void> write(DateTime since) async {
    final db = await _open();
    await db.insert(
      _table,
      {'key': _visitsPullKey, 'value': since.toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
