/// #151: o `open_failed` do `sqflite_sqlcipher` 3.2.0 é ambíguo.
///
/// No Android, `SqfliteSqlCipherPlugin.handleException` devolve o mesmo
/// `DatabaseException(open_failed <caminho>)` para chave errada, permissão
/// negada, arquivo inacessível e E/S na abertura (provado no emulador pela
/// #136: chave errada e `chmod 000` dão o mesmo erro). Estes testes simulam o
/// plugin com um `opener` que lança exatamente esse erro — o que a VM não tem
/// como produzir sozinha — e provam que, com a chave presente, nada é movido
/// nem apagado.
library;

import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

class _PluginError extends DatabaseException {
  _PluginError(super.message);

  @override
  Object? get result => null;

  @override
  int? getResultCode() {
    final m = RegExp(r'code (\d+)').firstMatch(toString());
    return m == null ? null : int.parse(m.group(1)!);
  }
}

/// O que o plugin devolve no Android para permissão negada, E/S ou chave errada.
DatabaseException _openFailed() => _PluginError('open_failed /data/user/0/app/databases/x.db');

/// O sinal inequívoco (iOS/FFI).
DatabaseException _notADatabase() => _PluginError('file is not a database (code 26)');

OfflineVisitRecord _visit(String localId) => OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      outcome: 'realizada',
      localId: localId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'open_failed_ambiguity_test.db';
  final key = 'c' * 64;

  setUp(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(name);
    await EncryptedLocalDatabase.deleteRecoveryCopy(name);
  });

  tearDown(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(name);
    await EncryptedLocalDatabase.deleteRecoveryCopy(name);
  });

  Future<String> path() => EncryptedLocalDatabase.pathFor(name);
  Future<File> recoveryCopy() async => File('${await path()}.recuperado');

  /// Banco com uma visita pendente do ACS `acs-a`, gravado com a chave [key].
  Future<List<int>> fileWithPendingVisit() async {
    final storage = SqlCipherVisitStorage(
      keyStore: InMemoryDatabaseKeyStore(initialKey: key),
      databaseName: name,
      allowUnencryptedForTesting: true,
    );
    await storage.forOwner('acs-a').save([_visit('nao-enviada')]);
    await storage.close();
    return File(await path()).readAsBytes();
  }

  /// [failures] são lançados pelo "plugin" em ordem; depois ele abre de verdade.
  VisitDatabase database(List<Object> failures, {required InMemoryDatabaseKeyStore keys, List<String>? calls}) =>
      VisitDatabase(
        keyStore: keys,
        databaseName: name,
        allowUnencryptedForTesting: true,
        retryDelay: Duration.zero,
        opener: (n, p, u) async {
          calls?.add('abrir');
          if (failures.isNotEmpty) throw failures.removeAt(0);
          return EncryptedLocalDatabase.open(databaseName: n, passphrase: p, allowUnencryptedForTesting: u);
        },
      );

  test('open_failed persistente (E/S ou permissão): falha fechada, fila e chave intactas', () async {
    final before = await fileWithPendingVisit();
    final keys = InMemoryDatabaseKeyStore(initialKey: key);
    final calls = <String>[];
    final db = database([_openFailed(), _openFailed()], keys: keys, calls: calls);

    await expectLater(db.open(), throwsA(isA<VisitDatabaseOpenFailed>()));

    expect(calls, ['abrir', 'abrir'], reason: 'uma nova tentativa, nenhuma recriação');
    expect(await keys.readOrCreate(), key, reason: 'a chave não é apagada');
    expect(await File(await path()).readAsBytes(), before, reason: 'o arquivo da fila não é tocado');
    expect((await recoveryCopy()).existsSync(), isFalse, reason: 'a fila não é posta de lado');
  });

  test('a cada abertura do app o open_failed se repete e nada muda; quando passa, a visita está lá', () async {
    final before = await fileWithPendingVisit();
    final keys = InMemoryDatabaseKeyStore(initialKey: key);
    final failures = <Object>[for (var i = 0; i < 10; i++) _openFailed()];
    final db = database(failures, keys: keys);

    for (var start = 0; start < 5; start++) {
      await expectLater(db.open(), throwsA(isA<VisitDatabaseOpenFailed>()));
    }
    expect(await keys.readOrCreate(), key);
    expect(await File(await path()).readAsBytes(), before);

    final opened = await db.open();
    expect((await opened.query('offline_visits')).map((r) => r['local_id']), ['nao-enviada']);
    await db.close();
  });

  test('chave errada inequívoca seguida de open_failed: também não recupera', () async {
    final before = await fileWithPendingVisit();
    final keys = InMemoryDatabaseKeyStore(initialKey: key);
    final db = database([_notADatabase(), _openFailed()], keys: keys);

    await expectLater(db.open(), throwsA(isA<VisitDatabaseOpenFailed>()));

    expect(await keys.readOrCreate(), key);
    expect(await File(await path()).readAsBytes(), before);
    expect((await recoveryCopy()).existsSync(), isFalse);
  });

  test('open_failed seguido de outro erro: sobe o outro erro, nada apagado', () async {
    final before = await fileWithPendingVisit();
    final keys = InMemoryDatabaseKeyStore(initialKey: key);
    final other = PlatformException(code: 'sqlite_error', message: 'canal indisponível');
    final db = database([_openFailed(), other], keys: keys);

    await expectLater(db.open(), throwsA(same(other)));

    expect(await keys.readOrCreate(), key);
    expect(await File(await path()).readAsBytes(), before);
  });

  group('a fila com o disco ilegível', () {
    test('não grava por cima das visitas que não leu; quando o banco volta, junta as duas', () async {
      final before = await fileWithPendingVisit();
      final keys = InMemoryDatabaseKeyStore(initialKey: key);
      // restore (2) + a gravação do 1º registro em campo (2): ainda ilegível.
      final db = database([_openFailed(), _openFailed(), _openFailed(), _openFailed()], keys: keys);
      final queue = OfflineVisitQueue(store: SqlCipherVisitStore.on(db, owner: 'acs-a'));

      await queue.restore();
      expect(queue.persistenceFailed, isTrue);

      await queue.add(_visit('em-campo-1'));
      expect(queue.persistenceFailed, isTrue, reason: 'a fila segue em RAM');
      expect(queue.pendingVisits.map((v) => v.localId), ['em-campo-1']);
      expect(await File(await path()).readAsBytes(), before, reason: 'nenhuma gravação sobre o disco não lido');
      expect(await keys.readOrCreate(), key);

      // O "plugin" volta a abrir (a permissão voltou, o E/S passou).
      await queue.add(_visit('em-campo-2'));

      expect(queue.persistenceFailed, isFalse);
      expect(
        queue.pendingVisits.map((v) => v.localId),
        ['nao-enviada', 'em-campo-1', 'em-campo-2'],
        reason: 'a visita do disco volta para a fila, antes das novas',
      );
      final onDisk = await SqlCipherVisitStore.on(db, owner: 'acs-a').load();
      expect(onDisk.map((v) => v.localId), ['nao-enviada', 'em-campo-1', 'em-campo-2']);
      await db.close();
    });

    test('uma visita já enviada nesta execução não volta do disco', () async {
      await fileWithPendingVisit();
      final keys = InMemoryDatabaseKeyStore(initialKey: key);
      // restore (2) + gravação do registro em campo (2): o disco segue ilegível
      // até o envio terminar.
      final db = database([for (var i = 0; i < 4; i++) _openFailed()], keys: keys);
      final store = SqlCipherVisitStore.on(db, owner: 'acs-a');
      final queue = OfflineVisitQueue(store: store, synchronizer: FakeVisitSynchronizer());

      await queue.restore();
      // Mesmo `localId` da linha do disco: a visita foi enviada pela RAM.
      await queue.add(_visit('nao-enviada'));
      await queue.sync();
      expect(queue.syncedVisits.map((v) => v.localId), contains('nao-enviada'));

      await queue.add(_visit('depois'));
      expect(queue.pendingVisits.map((v) => v.localId), ['depois'], reason: 'não reenvia o que já subiu');
      expect((await store.load()).map((v) => v.localId), ['depois']);
      await db.close();
    });
  });

  test('saída para uma chave de fato perdida: a limpeza remota (#81) apaga arquivo e chave', () async {
    await fileWithPendingVisit();
    final keys = InMemoryDatabaseKeyStore(initialKey: key);
    final db = database([_openFailed(), _openFailed()], keys: keys);
    await expectLater(db.open(), throwsA(isA<VisitDatabaseOpenFailed>()));

    await db.destroy();

    expect(File(await path()).existsSync(), isFalse);
    expect(await keys.readOrCreate(), isNot(key), reason: 'chave nova depois da limpeza');
    expect(await (await db.open()).query('offline_visits'), isEmpty);
    await db.close();
  });

  group('chave comprovadamente ausente com o arquivo presente (o outro sinal inequívoco)', () {
    test('põe a fila de lado e recomeça, sem nem tentar abrir com uma chave recém-criada', () async {
      final before = await fileWithPendingVisit();
      final keys = InMemoryDatabaseKeyStore(); // a chave se perdeu; o arquivo veio
      final calls = <String>[];
      final db = database([], keys: keys, calls: calls);

      final opened = await db.open();

      expect(calls, ['abrir'], reason: 'só a abertura do banco novo');
      expect(await keys.read(), isNotNull, reason: 'chave nova criada');
      expect(await opened.query('offline_visits'), isEmpty);
      expect(await (await recoveryCopy()).readAsBytes(), before, reason: 'a cópia forense fica');
      await db.close();
    });

    test('falha ao LER a chave: o erro sobe e nada é tocado', () async {
      final before = await fileWithPendingVisit();
      final keys = _UnreadableKeyStore();
      final calls = <String>[];
      final db = VisitDatabase(
        keyStore: keys,
        databaseName: name,
        allowUnencryptedForTesting: true,
        retryDelay: Duration.zero,
        opener: (n, p, u) async {
          calls.add('abrir');
          return EncryptedLocalDatabase.open(databaseName: n, passphrase: p, allowUnencryptedForTesting: u);
        },
      );

      await expectLater(db.open(), throwsA(isA<StateError>()));

      expect(calls, isEmpty);
      expect(keys.deletes, 0);
      expect(await File(await path()).readAsBytes(), before);
      expect((await recoveryCopy()).existsSync(), isFalse);
    });
  });

  test('classificação: só o código 26 / "file is not a database" é chave errada', () {
    expect(classifyDatabaseOpenError(_notADatabase()), DatabaseOpenErrorKind.wrongKey);
    expect(classifyDatabaseOpenError(_PluginError('file is not a database')), DatabaseOpenErrorKind.wrongKey);
    expect(classifyDatabaseOpenError(_openFailed()), DatabaseOpenErrorKind.ambiguousOpenFailure);
    expect(classifyDatabaseOpenError(_PluginError('disk I/O error (code 10)')), DatabaseOpenErrorKind.other);
    expect(classifyDatabaseOpenError(StateError('x')), DatabaseOpenErrorKind.other);
    expect(isWrongDatabaseKeyError(_openFailed()), isFalse);
  });
}

/// Custódia que não consegue ler (Keystore indisponível): nunca é "ausente".
class _UnreadableKeyStore implements DatabaseKeyStore {
  var deletes = 0;

  @override
  Future<String?> read() async => throw StateError('Keystore indisponível');

  @override
  Future<String> readOrCreate() async => throw StateError('Keystore indisponível');

  @override
  Future<void> delete() async => deletes++;
}
