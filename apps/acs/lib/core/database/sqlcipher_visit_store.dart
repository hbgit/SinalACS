import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database, DatabaseException;

const _table = 'offline_visits';

/// Abre (e recupera) o banco; uma só instância por processo.
class VisitDatabase {
  VisitDatabase({
    required DatabaseKeyStore keyStore,
    this.databaseName = 'sinalacs_acs.db',
    this.allowUnencryptedForTesting = false,
    @visibleForTesting
    Future<Database> Function(String databaseName, String passphrase, bool allowUnencrypted)?
        opener,
  })  : _keyStore = keyStore,
        _opener = opener ?? _defaultOpener;

  static Future<Database> _defaultOpener(
    String databaseName,
    String passphrase,
    bool allowUnencrypted,
  ) =>
      EncryptedLocalDatabase.open(
        databaseName: databaseName,
        passphrase: passphrase,
        allowUnencryptedForTesting: allowUnencrypted,
      );

  final Future<Database> Function(String, String, bool) _opener;
  final DatabaseKeyStore _keyStore;
  final String databaseName;

  /// Repassado a [EncryptedLocalDatabase.open]. Só os testes de VM passam true.
  final bool allowUnencryptedForTesting;

  Database? _database;
  Future<Database>? _opening;

  /// Abre preguiçosamente, na primeira leitura ou escrita.
  ///
  /// É o que permite a fila continuar sendo construída de forma síncrona pela
  /// UI, sem espalhar `await` pela montagem do app.
  ///
  /// Single-flight: chamadas concorrentes compartilham a MESMA abertura (duas
  /// conexões ao mesmo arquivo, ou duas recuperações apagando o arquivo, são
  /// o que isto evita). Se a abertura falha, o próximo `open()` tenta de novo.
  Future<Database> open() {
    final existing = _database;
    if (existing != null && existing.isOpen) return Future.value(existing);

    final inFlight = _opening;
    if (inFlight != null) return inFlight;

    final attempt = _openOnce();
    _opening = attempt;
    return attempt.whenComplete(() {
      if (identical(_opening, attempt)) _opening = null;
    }).then((_) => attempt);
  }

  Future<Database> _openOnce() async {
    final passphrase = await _keyStore.readOrCreate();

    try {
      return _database =
          await _opener(databaseName, passphrase, allowUnencryptedForTesting);
    } on UnsupportedError {
      // Plataforma sem SQLCipher: quem chamou precisa saber, não receber um
      // banco em texto plano por baixo dos panos.
      rethrow;
    } catch (error) {
      // SÓ a chave errada recomeça o arquivo. Qualquer outro erro (migração,
      // E/S, canal da plataforma) sobe: apagar ali destruiria visitas legíveis
      // por um problema passageiro. Quem chama segue em RAM
      // (`persistenceFailed`) e tenta de novo na próxima abertura.
      if (!isWrongDatabaseKeyError(error)) rethrow;
      // A chave não abre este arquivo — tipicamente reinstalação ou restauração
      // de backup, onde o banco veio e a chave do keystore não. Sem isso o app
      // ficaria travado num estado irrecuperável a cada abertura. Descartar o
      // arquivo perde visitas ainda não sincronizadas, mas elas já eram
      // ilegíveis; ficar travado perderia as próximas também.
      await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
      await _keyStore.delete();

      return _database = await _opener(
        databaseName,
        await _keyStore.readOrCreate(),
        allowUnencryptedForTesting,
      );
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// "Limpar este aparelho" (D9), numa só transação: primeiro reconta as
  /// visitas — de QUALQUER dono, inclusive as sem dono (quarentena) — e, se
  /// houver alguma, lança [WipeBlocked] sem apagar nada (toda linha de
  /// `offline_visits` é visita ainda não enviada: a confirmada pelo servidor
  /// sai do disco). Sem visita, apaga as linhas de `offline_visits`,
  /// `sync_cursor`, `micro_area_cache` e `micro_area_cache_meta`.
  ///
  /// O arquivo e a chave do Keystore ficam: é limpeza de dados, não troca de
  /// chave.
  Future<void> wipeAllData() async {
    final database = await open();
    await database.transaction((transaction) async {
      final rows = await transaction.rawQuery('SELECT COUNT(*) AS total FROM $_table');
      final unsent = rows.single['total']! as int;
      if (unsent > 0) throw WipeBlocked(unsent);
      await transaction.delete(_table);
      await transaction.delete('sync_cursor');
      await transaction.delete('micro_area_cache');
      await transaction.delete('micro_area_cache_meta');
    });
  }
}

/// O erro que o SQLCipher dá quando a chave não abre o arquivo.
///
/// - `SQLITE_NOTADB` (código 26, "file is not a database"): iOS e FFI.
/// - `open_failed <caminho>`: o `sqflite_sqlcipher` (3.2.0) no Android
///   converte o "file is not a database" da abertura nisso
///   (`SqfliteSqlCipherPlugin.handleException`), sem o código. A mesma
///   tradução cobre "could not open database"; é o mais estreito que o plugin
///   permite distinguir.
///
/// Erro de migração (SQL), de E/S, `PlatformException` ou qualquer outro tipo
/// NÃO é chave errada.
bool isWrongDatabaseKeyError(Object error) {
  if (error is! DatabaseException) return false;
  if (error.getResultCode() == 26) return true;
  final message = error.toString().toLowerCase();
  return message.contains('file is not a database') || error.isOpenFailedError();
}

OfflineVisitRecord _recordFrom(Map<String, Object?> row) => OfflineVisitRecord(
      patientId: row['patient_id']! as String,
      risk: row['risk']! as String,
      status: row['status']! as String,
      outcome: row['outcome']! as String,
      notes: (row['notes'] as String?) ?? '',
      rejectionReason: row['rejection_reason'] as String?,
      localId: row['local_id']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      version: row['version']! as int,
    );

/// Armazenamento por dono sobre UM [VisitDatabase].
class SqlCipherVisitStorage implements VisitStorage {
  SqlCipherVisitStorage({
    required DatabaseKeyStore keyStore,
    String databaseName = 'sinalacs_acs.db',
    bool allowUnencryptedForTesting = false,
  }) : database = VisitDatabase(
          keyStore: keyStore,
          databaseName: databaseName,
          allowUnencryptedForTesting: allowUnencryptedForTesting,
        );

  final VisitDatabase database;

  @override
  VisitStore forOwner(String ownerId) =>
      SqlCipherVisitStore.on(database, owner: requireOwnerId(ownerId));

  @override
  LegacyVisitStore get legacy => SqlCipherLegacyVisitStore(database);

  /// Só `owner` e `COUNT(*)`: nenhuma coluna de conteúdo é lida.
  @override
  Future<Map<String, int>> countsByOwner() async {
    final db = await database.open();
    final rows = await db.rawQuery(
      'SELECT owner, COUNT(*) AS total FROM $_table WHERE owner IS NOT NULL GROUP BY owner',
    );
    return {for (final row in rows) row['owner']! as String: row['total']! as int};
  }

  @override
  Future<void> wipeAllData() => database.wipeAllData();

  Future<void> close() => database.close();
}

/// Quarentena (D2): linhas com `owner IS NULL`. Só lê e remove por `localId`.
class SqlCipherLegacyVisitStore implements LegacyVisitStore {
  SqlCipherLegacyVisitStore(this._database);

  final VisitDatabase _database;

  @override
  Future<List<OfflineVisitRecord>> load() async {
    final database = await _database.open();
    final rows = await database.query(
      _table,
      where: 'owner IS NULL',
      orderBy: 'created_at ASC, rowid ASC',
    );
    return [for (final row in rows) _recordFrom(row)];
  }

  @override
  Future<void> remove(Iterable<String> localIds) async {
    final ids = localIds.toList();
    if (ids.isEmpty) return;
    final database = await _database.open();
    await database.transaction((transaction) async {
      for (final id in ids) {
        await transaction.delete(
          _table,
          where: 'owner IS NULL AND local_id = ?',
          whereArgs: [id],
        );
      }
    });
  }
}

/// Persistência das visitas offline de UM dono no banco criptografado.
///
/// Implementa o [VisitStore] que a fila já define — mesmo padrão de
/// `application/` + `infrastructure/` usado no backend: a fila não sabe que
/// existe SQLCipher, e este arquivo não sabe o que é uma FSM de sincronização.
class SqlCipherVisitStore implements VisitStore {
  /// Cria o próprio [VisitDatabase].
  SqlCipherVisitStore({
    required DatabaseKeyStore keyStore,
    required String owner,
    String databaseName = 'sinalacs_acs.db',
    bool allowUnencryptedForTesting = false,
  })  : owner = requireOwnerId(owner),
        _database = VisitDatabase(
          keyStore: keyStore,
          databaseName: databaseName,
          allowUnencryptedForTesting: allowUnencryptedForTesting,
        ),
        _ownsDatabase = true;

  /// Visão de [owner] sobre um banco compartilhado.
  SqlCipherVisitStore.on(VisitDatabase database, {required String owner})
      : owner = requireOwnerId(owner),
        _database = database,
        _ownsDatabase = false;

  final VisitDatabase _database;
  final bool _ownsDatabase;
  final String owner;

  /// Só as linhas deste dono. Nunca `owner IS NULL`: a quarentena não é lida
  /// nem adotada por ninguém (D2).
  @override
  Future<List<OfflineVisitRecord>> load() async {
    final database = await _database.open();
    final rows = await database.query(
      _table,
      where: 'owner = ?',
      whereArgs: [owner],
      orderBy: 'created_at ASC, rowid ASC',
    );
    return [for (final row in rows) _recordFrom(row)];
  }

  /// Substitui o conjunto DESTE dono, em transação.
  ///
  /// A fila chama `save([..._pending, ..._rejected])`, então o que sai da
  /// lista sai do disco: uma visita confirmada pelo servidor deixa o
  /// dispositivo aqui. É a minimização de dados acontecendo, e há teste que
  /// trava essa propriedade. Uma visita recusada em definitivo continua no
  /// disco — com `rejection_reason` preenchido — até o ACS descartá-la
  /// explicitamente; só então ela deixa de fazer parte do que é gravado.
  ///
  /// Só apaga `WHERE owner = ?`: linhas de outros donos e da quarentena nunca
  /// são tocadas. `local_id` é chave primária global; se um `localId` já
  /// pertence a outro dono (ou à quarentena), lança [VisitLocalIdConflict] e a
  /// transação inteira é desfeita — a linha alheia fica intacta.
  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    ensureNoRepeatedLocalIds(visits);
    final database = await _database.open();

    await database.transaction((transaction) async {
      await transaction.delete(_table, where: 'owner = ?', whereArgs: [owner]);
      for (final visit in visits) {
        final existing = await transaction.query(
          _table,
          columns: ['local_id'],
          where: 'local_id = ?',
          whereArgs: [visit.localId],
        );
        if (existing.isNotEmpty) throw VisitLocalIdConflict(visit.localId);

        await transaction.insert(_table, {
          'local_id': visit.localId,
          'patient_id': visit.patientId,
          'risk': visit.risk,
          'status': visit.status,
          'outcome': visit.outcome,
          'notes': visit.notes,
          'created_at': visit.createdAt.toIso8601String(),
          'version': visit.version,
          'rejection_reason': visit.rejectionReason,
          'owner': owner,
        });
      }
    });
  }

  /// Fecha o banco só se esta visão o criou; visões de [SqlCipherVisitStorage]
  /// não fecham o banco compartilhado.
  Future<void> close() async {
    if (_ownsDatabase) await _database.close();
  }
}
