import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

/// Estes testes rodam na VM, onde o SQLCipher não existe — por isso passam
/// `allowUnencryptedForTesting`. Eles provam a LÓGICA (chave, schema, round-trip,
/// minimização), **não** a criptografia.
///
/// A prova de que o arquivo está cifrado só é possível em dispositivo e vive em
/// `integration_test/encrypted_storage_test.dart`. Foi exatamente essa confusão
/// que produziu o defeito original: havia um teste chamado "deve abrir banco
/// criptografado" que, no Linux, exercitava o caminho sem criptografia nenhuma.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('custódia da chave', () {
    test('gera uma chave de 256 bits em hexadecimal', () {
      final key = generateDatabaseKey();

      expect(key, hasLength(64));
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('duas chaves geradas são diferentes', () {
      expect(generateDatabaseKey(), isNot(generateDatabaseKey()));
    });

    test('a chave é estável entre leituras', () async {
      final store = InMemoryDatabaseKeyStore();

      expect(await store.readOrCreate(), await store.readOrCreate());
    });

    test('apagar a chave faz a próxima leitura gerar outra', () async {
      final store = InMemoryDatabaseKeyStore();
      final first = await store.readOrCreate();

      await store.delete();

      expect(await store.readOrCreate(), isNot(first));
    });
  });

  group('INV-04: nunca persistir em texto plano', () {
    test('recusa abrir fora de Android/iOS sem a flag explícita', () async {
      // Este é o teste que trava a regressão. Antes, o caminho sem criptografia
      // era o comportamento PADRÃO fora de mobile.
      expect(
        () => EncryptedLocalDatabase.open(
          databaseName: 'inv04_test.db',
          passphrase: generateDatabaseKey(),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('abre com a flag explícita, que só o teste passa', () async {
      final db = await EncryptedLocalDatabase.open(
        databaseName: 'inv04_allowed_test.db',
        passphrase: generateDatabaseKey(),
        allowUnencryptedForTesting: true,
      );

      expect(db.isOpen, isTrue);
      await db.close();
    });

    test('recusa passphrase vazia', () async {
      expect(
        () => EncryptedLocalDatabase.open(
          databaseName: 'inv04_empty_test.db',
          passphrase: '',
          allowUnencryptedForTesting: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('migração do schema', () {
    // O passo de maior risco da mudança: um app já instalado abre um arquivo
    // v1 com o código v2. Sem `onUpgrade`, a tabela que a fila lê simplesmente
    // não existe, e o ACS vê "as visitas não estão sendo salvas" para sempre.
    //
    // Estes testes chamam `EncryptedLocalDatabase.open` DIRETO, nunca através
    // do `SqlCipherVisitStore`: o `catch` do store apaga o arquivo ilegível e
    // recomeça, então uma migração quebrada passaria despercebida por ele.
    const nome = 'migracao_test.db';
    final chave = 'a' * 64;

    Future<Database> abrirV1(String create) async {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        await EncryptedLocalDatabase.pathFor(nome),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => db.execute(create),
        ),
      );
    }

    Future<Set<String>> tabelas(Database db) async {
      final rows = await db.query('sqlite_master', columns: ['name'], where: "type = 'table'");
      return {for (final row in rows) row['name']! as String};
    }

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(nome));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(nome));

    test('o esquema antigo local_queue dá lugar a offline_visits', () async {
      final legado = await abrirV1(
        'CREATE TABLE IF NOT EXISTS local_queue (id TEXT PRIMARY KEY)',
      );
      await legado.insert('local_queue', {'id': 'antigo'});
      await legado.close();

      final atual = await EncryptedLocalDatabase.open(
        databaseName: nome,
        passphrase: chave,
        allowUnencryptedForTesting: true,
      );

      final nomes = await tabelas(atual);
      expect(nomes, contains('offline_visits'));
      expect(nomes, isNot(contains('local_queue')));
      await atual.close();
    });

    test('a offline_visits v1 com patient_name é recriada com patient_id', () async {
      // O rótulo antigo era 'Paciente ' + 8 dos 32 dígitos do UUID: não há como
      // recuperar o identificador, então preservar a linha só produziria uma
      // pendência que o servidor recusa a cada tentativa.
      final legado = await abrirV1('''
CREATE TABLE IF NOT EXISTS offline_visits (
  local_id TEXT PRIMARY KEY,
  patient_name TEXT NOT NULL,
  risk TEXT NOT NULL,
  status TEXT NOT NULL,
  outcome TEXT NOT NULL,
  created_at TEXT NOT NULL,
  version INTEGER NOT NULL
)''');
      await legado.insert('offline_visits', {
        'local_id': '00000000-0000-4000-8000-00000000000a',
        'patient_name': 'Paciente 00000000',
        'risk': 'red',
        'status': 'PENDENTE',
        'outcome': 'realizada',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'version': 1,
      });
      await legado.close();

      final atual = await EncryptedLocalDatabase.open(
        databaseName: nome,
        passphrase: chave,
        allowUnencryptedForTesting: true,
      );

      final colunas = [
        for (final row in await atual.rawQuery('PRAGMA table_info(offline_visits)'))
          row['name']! as String,
      ];
      expect(colunas, contains('patient_id'));
      expect(colunas, isNot(contains('patient_name')));
      expect(await atual.query('offline_visits'), isEmpty);
      await atual.close();
    });

    test('abrir de novo na mesma versão não apaga o que está gravado', () async {
      // A migração roda uma vez. Se rodasse a cada abertura, ela apagaria a
      // fila do dia toda vez que o app abrisse.
      final store = SqlCipherVisitStore(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );
      await store.save([
        OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'),
      ]);
      await store.close();

      expect((await store.load()).single.patientId, seedPatientId);
      await store.close();
    });
  });

  group('SqlCipherVisitStore', () {
    late SqlCipherVisitStore store;

    OfflineVisitRecord visit(String patientId) => OfflineVisitRecord(
          patientId: patientId,
          risk: 'red',
          status: 'PENDENTE',
          outcome: 'realizada',
        );

    setUp(() async {
      await EncryptedLocalDatabase.deleteDatabaseFile('store_test.db');
      store = SqlCipherVisitStore(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: 'store_test.db',
        allowUnencryptedForTesting: true,
      );
    });

    tearDown(() => store.close());

    test('grava e relê preservando os campos', () async {
      final original = visit(seedPatientId);
      await store.save([original]);

      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.localId, original.localId);
      expect(loaded.single.patientId, original.patientId);
      expect(loaded.single.risk, 'red');
      expect(loaded.single.outcome, 'realizada');
      expect(loaded.single.version, original.version);
    });

    test('save substitui o conjunto inteiro', () async {
      await store.save([visit(syntheticPatientId(1)), visit(syntheticPatientId(2))]);
      await store.save([visit(syntheticPatientId(3))]);

      final loaded = await store.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.patientId, syntheticPatientId(3));
    });

    test('sobrevive a fechar e reabrir o banco', () async {
      await store.save([visit(seedPatientId)]);
      await store.close();

      expect((await store.load()).single.patientId, seedPatientId);
    });
  });

  group('fila persistente', () {
    late SqlCipherVisitStore store;

    OfflineVisitQueue queueOn(SqlCipherVisitStore store, {VisitSynchronizer? sender}) =>
        OfflineVisitQueue(store: store, synchronizer: sender);

    setUp(() async {
      await EncryptedLocalDatabase.deleteDatabaseFile('queue_test.db');
      store = SqlCipherVisitStore(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: 'queue_test.db',
        allowUnencryptedForTesting: true,
      );
    });

    tearDown(() => store.close());

    test('a visita sobrevive a recriar a fila', () async {
      // É o que "offline-first" significa: fechar o app não pode perder o
      // trabalho de campo.
      final first = queueOn(store);
      await first.add(OfflineVisitRecord(
        patientId: seedPatientId,
        risk: 'red',
        status: 'PENDENTE',
      ));

      final second = queueOn(store);
      await second.restore();

      expect(second.pendingCount, 1);
      expect(second.pendingVisits.single.patientId, seedPatientId);
      expect(second.persistenceFailed, isFalse);
    });

    test('a visita confirmada pelo servidor SAI do disco', () async {
      // Minimização (LGPD-RF07 / seção 5.6): o que já chegou ao servidor não
      // precisa continuar no aparelho que pode ser perdido ou roubado.
      final queue = queueOn(store, sender: _SyncedSynchronizer());
      await queue.add(OfflineVisitRecord(
        patientId: seedPatientId,
        risk: 'red',
        status: 'PENDENTE',
      ));
      expect(await store.load(), hasLength(1));

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.synced);
      expect(await store.load(), isEmpty);
    });

    test('a visita em conflito PERMANECE no disco', () async {
      // Conflito precisa de resolução; descartá-lo perderia o registro.
      final queue = queueOn(store, sender: _ConflictSynchronizer());
      await queue.add(OfflineVisitRecord(
        patientId: syntheticPatientId(2),
        risk: 'yellow',
        status: 'PENDENTE',
      ));

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.conflict);
      expect(await store.load(), hasLength(1));
    });

    test('armazenamento indisponível não derruba o registro em campo', () async {
      // Travar o registro de visita seria pior do que não persistir. A fila
      // segue em memória e acende o sinalizador para a UI avisar.
      final queue = OfflineVisitQueue(store: FailingVisitStore());

      await queue.restore();
      await queue.add(OfflineVisitRecord(
        patientId: syntheticPatientId(3),
        risk: 'green',
        status: 'PENDENTE',
      ));

      expect(queue.pendingCount, 1);
      expect(queue.persistenceFailed, isTrue);
    });
  });
}

class _SyncedSynchronizer implements VisitSynchronizer {
  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async => [
        for (final visit in visits)
          VisitSyncOutcome(localId: visit.localId, status: 'synced', serverVersion: 1),
      ];
}

class _ConflictSynchronizer implements VisitSynchronizer {
  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async => [
        for (final visit in visits)
          VisitSyncOutcome(localId: visit.localId, status: 'conflict', serverVersion: 9),
      ];
}


