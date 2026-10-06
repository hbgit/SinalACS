import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart' show requireOwnerId;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

/// Cursor de `visits.pull` POR DONO (usuário/microárea), no mesmo banco
/// criptografado das visitas offline.
///
/// Antes era um cursor global do aparelho: o ACS B herdava o `since` do ACS A
/// e nunca receberia as visitas anteriores a ele. Agora cada dono tem o seu,
/// na chave `visits_pull|<dono>`.
///
/// A chave legada `visits_pull` (global) fica ÓRFÃ DE PROPÓSITO (D3): nunca
/// mais é lida nem apagada. Adotá-la daria o cursor de um ACS a outro; começar
/// do epoch só custa um pull completo, idempotente pelo dedupe de `localId`.
class SyncCursorStore {
  /// Cria o próprio [VisitDatabase].
  SyncCursorStore({
    required DatabaseKeyStore keyStore,
    required String owner,
    String databaseName = 'sinalacs_acs.db',
    bool allowUnencryptedForTesting = false,
  })  : _key = _keyFor(owner),
        _database = VisitDatabase(
          keyStore: keyStore,
          databaseName: databaseName,
          allowUnencryptedForTesting: allowUnencryptedForTesting,
        );

  /// Visão de [owner] sobre um banco compartilhado com a fila de visitas.
  SyncCursorStore.on(VisitDatabase database, {required String owner})
      : _key = _keyFor(owner),
        _database = database;

  static const _table = 'sync_cursor';

  static String _keyFor(String owner) => 'visits_pull|${requireOwnerId(owner)}';

  final String _key;
  final VisitDatabase _database;

  /// Devolve o `since` da última chamada bem-sucedida a `visits.pull` deste
  /// dono, ou `null` na primeira sincronização — quem chama trata isso como
  /// "desde o início dos tempos", nunca como erro.
  Future<DateTime?> read() async {
    final db = await _database.open();
    final rows = await db.query(_table, where: 'key = ?', whereArgs: [_key]);
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['value'] as String);
  }

  /// Grava o cursor deste dono, substituindo o valor anterior.
  Future<void> write(DateTime since) async {
    final db = await _database.open();
    await db.insert(
      _table,
      {'key': _key, 'value': since.toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
