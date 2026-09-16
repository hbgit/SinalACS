import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

/// Persistência das visitas offline no banco criptografado.
///
/// Implementa o [VisitStore] que a fila já define — mesmo padrão de
/// `application/` + `infrastructure/` usado no backend: a fila não sabe que
/// existe SQLCipher, e este arquivo não sabe o que é uma FSM de sincronização.
class SqlCipherVisitStore implements VisitStore {
  SqlCipherVisitStore({
    required DatabaseKeyStore keyStore,
    this.databaseName = 'sinalacs_acs.db',
    this.allowUnencryptedForTesting = false,
  }) : _keyStore = keyStore;

  static const _table = 'offline_visits';

  final DatabaseKeyStore _keyStore;
  final String databaseName;

  /// Repassado a [EncryptedLocalDatabase.open]. Só os testes de VM passam true.
  final bool allowUnencryptedForTesting;

  Database? _database;

  /// Abre preguiçosamente, na primeira leitura ou escrita.
  ///
  /// É o que permite a fila continuar sendo construída de forma síncrona pela
  /// UI, sem espalhar `await` pela montagem do app.
  Future<Database> _open() async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;

    final passphrase = await _keyStore.readOrCreate();

    try {
      return _database = await EncryptedLocalDatabase.open(
        databaseName: databaseName,
        passphrase: passphrase,
        allowUnencryptedForTesting: allowUnencryptedForTesting,
      );
    } on UnsupportedError {
      // Plataforma sem SQLCipher: quem chamou precisa saber, não receber um
      // banco em texto plano por baixo dos panos.
      rethrow;
    } catch (_) {
      // A chave não abre este arquivo — tipicamente reinstalação ou restauração
      // de backup, onde o banco veio e a chave do keystore não. Sem isso o app
      // ficaria travado num estado irrecuperável a cada abertura. Descartar o
      // arquivo perde visitas ainda não sincronizadas, mas elas já eram
      // ilegíveis; ficar travado perderia as próximas também.
      await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
      await _keyStore.delete();

      return _database = await EncryptedLocalDatabase.open(
        databaseName: databaseName,
        passphrase: await _keyStore.readOrCreate(),
        allowUnencryptedForTesting: allowUnencryptedForTesting,
      );
    }
  }

  @override
  Future<List<OfflineVisitRecord>> load() async {
    final database = await _open();
    final rows = await database.query(_table, orderBy: 'created_at ASC');

    return [
      for (final row in rows)
        OfflineVisitRecord(
          patientId: row['patient_id']! as String,
          risk: row['risk']! as String,
          status: row['status']! as String,
          outcome: row['outcome']! as String,
          notes: (row['notes'] as String?) ?? '',
          rejectionReason: row['rejection_reason'] as String?,
          localId: row['local_id']! as String,
          createdAt: DateTime.parse(row['created_at']! as String),
          version: row['version']! as int,
        ),
    ];
  }

  /// Substitui o conjunto inteiro, em transação.
  ///
  /// A fila chama `save([..._pending, ..._rejected])`, então o que sai da
  /// lista sai do disco: uma visita confirmada pelo servidor deixa o
  /// dispositivo aqui. É a minimização de dados acontecendo, e há teste que
  /// trava essa propriedade. Uma visita recusada em definitivo continua no
  /// disco — com `rejection_reason` preenchido — até o ACS descartá-la
  /// explicitamente; só então ela deixa de fazer parte do que é gravado.
  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    final database = await _open();

    await database.transaction((transaction) async {
      await transaction.delete(_table);
      for (final visit in visits) {
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
        });
      }
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
