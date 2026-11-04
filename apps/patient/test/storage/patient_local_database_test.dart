import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sinalacs_patient/core/storage/patient_local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mesma forma do erro do plugin: `DatabaseException` com `open_failed <path>`.
class _OpenFailed extends DatabaseException {
  _OpenFailed(super.message);

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;
}

void main() {
  late Directory dir;
  late String path;
  late InMemoryDatabaseKeyProvider keys;
  var lostCalls = 0;
  var opens = 0;
  const name = 'teste.db';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('patient_local_db');
    databaseFactoryFfi.setDatabasesPath(dir.path);
    path = '${dir.path}/$name';
    keys = InMemoryDatabaseKeyProvider();
    lostCalls = 0;
    opens = 0;
  });

  final made = <PatientLocalDatabase>[];

  tearDown(() async {
    // Fecha todo handle antes de apagar o diretório temporário.
    for (final db in made) {
      await db.close();
    }
    made.clear();
    await dir.delete(recursive: true);
  });

  PatientLocalDatabase make({
    Future<Database> Function(String, String)? openOverride,
    Future<void> Function()? onKeyLost,
  }) {
    final db = PatientLocalDatabase(
      keys: keys,
      databaseName: name,
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
      onKeyLost: onKeyLost ?? () async => lostCalls++,
      openOverride: openOverride,
    );
    made.add(db);
    return db;
  }

  Future<void> gravar(PatientLocalDatabase db, String valor) async {
    final conn = await db.open();
    await conn.insert('reminders', {
      'label': valor,
      'hour': 8,
      'minute': 0,
      'active': 1,
    });
  }

  Future<List<String>> ler(PatientLocalDatabase db) async {
    final conn = await db.open();
    final rows = await conn.query('reminders');
    return [for (final r in rows) r['label'] as String];
  }

  test(
    'abre, grava, fecha e reabre com a mesma chave: dado persiste',
    () async {
      final db = make();
      await gravar(db, 'remédio');
      await db.close();
      final db2 = make();
      expect(await ler(db2), ['remédio']);
      expect(db2.recoveredFromLostKey, isFalse);
      await db2.close();
    },
  );

  test('fora do celular sem o flag: UnsupportedError', () async {
    final db = PatientLocalDatabase(keys: keys, databaseName: name);
    await expectLater(db.open(), throwsUnsupportedError);
  });

  test(
    'fora do celular sem o flag: UnsupportedError mesmo com openOverride',
    () async {
      final db = PatientLocalDatabase(
        keys: keys,
        databaseName: name,
        openOverride: (p, k) async => databaseFactoryFfi.openDatabase(p),
      );
      await expectLater(db.open(), throwsUnsupportedError);
    },
  );

  test(
    'duas aberturas concorrentes: provedor chamado uma vez e mesma instância',
    () async {
      final db = make(
        openOverride: (p, k) async {
          opens++;
          return databaseFactoryFfi.openDatabase(p);
        },
      );
      final results = await Future.wait([db.open(), db.open()]);
      expect(identical(results[0], results[1]), isTrue);
      expect(keys.obtainCalls, 1);
      expect(opens, 1);
      await db.close();
    },
  );

  test(
    'arquivo existe e chave sumiu: recomeça vazio, chama onKeyLost, recoveredFromLostKey',
    () async {
      final db = make();
      await gravar(db, 'antigo');
      await db.close();
      await keys.destroy();

      final db2 = make();
      expect(await ler(db2), isEmpty);
      expect(db2.recoveredFromLostKey, isTrue);
      expect(lostCalls, 1);
      await db2.close();
    },
  );

  test(
    'leitura da chave lança duas vezes: LocalDatabaseUnavailableException, arquivo e chave intactos',
    () async {
      final db = make();
      await gravar(db, 'x');
      await db.close();

      keys.forceNext([KeyUnavailable(), KeyUnavailable()]);
      final db2 = make();
      await expectLater(
        db2.open(),
        throwsA(isA<LocalDatabaseUnavailableException>()),
      );
      expect(File(path).existsSync(), isTrue);
      expect(lostCalls, 0);
      expect(await ler(make()), ['x']);
    },
  );

  test(
    'leitura lança na 1ª abertura e funciona na 2ª: dados preservados',
    () async {
      final db = make();
      await gravar(db, 'preservado');
      await db.close();

      keys.forceNext([KeyUnavailable()]);
      final db2 = make();
      expect(await ler(db2), ['preservado']);
      expect(db2.recoveredFromLostKey, isFalse);
      await db2.close();
    },
  );

  test('leitura lança uma vez e passa no retry: abre sem erro', () async {
    keys.forceNext([KeyUnavailable()]);
    final db = make();
    await db.open();
    expect(keys.obtainCalls, 2);
    await db.close();
  });

  test(
    'abertura falha duas vezes com chave presente: LocalDatabaseUnavailableException, arquivo e chave intactos, onKeyLost não chamado',
    () async {
      final db = make();
      await gravar(db, 'x');
      await db.close();

      final falho = make(
        openOverride: (p, k) async {
          opens++;
          throw _OpenFailed('open_failed $p');
        },
      );
      await expectLater(
        falho.open(),
        throwsA(isA<LocalDatabaseUnavailableException>()),
      );
      expect(opens, 2);
      expect(File(path).existsSync(), isTrue);
      expect(lostCalls, 0);
      expect(await ler(make()), ['x']);
    },
  );

  test('abertura falha uma vez e passa no retry: abre sem erro', () async {
    final db = make(
      openOverride: (p, k) async {
        opens++;
        if (opens == 1) throw _OpenFailed('open_failed $p');
        return databaseFactoryFfi.openDatabase(p);
      },
    );
    await db.open();
    expect(opens, 2);
    await db.close();
  });

  test(
    'uma falha não fica memoizada: a próxima chamada tenta de novo',
    () async {
      keys.forceNext([KeyUnavailable(), KeyUnavailable()]);
      final db = make();
      await expectLater(
        db.open(),
        throwsA(isA<LocalDatabaseUnavailableException>()),
      );
      await db.open();
      await db.close();
    },
  );

  test('KeyLocked: LocalDatabaseLockedException, nada apagado', () async {
    final db = make();
    await gravar(db, 'x');
    await db.close();

    keys.forceNext([KeyLocked()]);
    await expectLater(
      make().open(),
      throwsA(isA<LocalDatabaseLockedException>()),
    );
    expect(File(path).existsSync(), isTrue);
    expect(lostCalls, 0);
  });

  test(
    'deleteEverything: sem arquivo, sem chave; próxima abertura cria banco novo',
    () async {
      final db = make();
      await gravar(db, 'x');
      await db.deleteEverything();
      expect(File(path).existsSync(), isFalse);

      final db2 = make();
      expect(await ler(db2), isEmpty);
      expect(db2.recoveredFromLostKey, isFalse);
      await db2.close();
    },
  );

  test('onKeyLost lança: a abertura ainda conclui', () async {
    final db = make();
    await gravar(db, 'x');
    await db.close();
    await keys.destroy();

    final db2 = make(onKeyLost: () async => throw StateError('falha'));
    expect(await ler(db2), isEmpty);
    expect(db2.recoveredFromLostKey, isTrue);
  });

  test(
    'destroy falha na recuperação: indisponível e nenhuma chave nova',
    () async {
      final db = make();
      await gravar(db, 'x');
      await db.close();
      await keys.destroy();

      keys.failDestroy = true;
      await expectLater(
        make().open(),
        throwsA(isA<LocalDatabaseUnavailableException>()),
      );
      expect(keys.currentKey, isNull);
      expect(lostCalls, 0);
    },
  );

  test('deleteEverything com destroy falhando: indisponível', () async {
    final db = make();
    await gravar(db, 'x');
    keys.failDestroy = true;
    await expectLater(
      db.deleteEverything(),
      throwsA(isA<LocalDatabaseUnavailableException>()),
    );
  });

  test(
    'chave gravada e arquivo ausente: abre, cria o arquivo, sem onKeyLost',
    () async {
      keys = InMemoryDatabaseKeyProvider(initialKey: generateRawDatabaseKey());
      final db = make();
      await db.open();
      expect(File(path).existsSync(), isTrue);
      expect(lostCalls, 0);
      expect(db.recoveredFromLostKey, isFalse);
    },
  );

  test(
    'deleteEverything e open concorrentes: uma chave, arquivo abre com ela',
    () async {
      final db = make();
      await gravar(db, 'velho');
      final futures = [db.deleteEverything(), db.open()];
      await Future.wait(futures);
      final key = keys.currentKey;
      expect(key, isNotNull);
      expect(db.recoveredFromLostKey, isFalse);
      expect(lostCalls, 0);
      expect(await (await db.open()).query('reminders'), isEmpty);
      await db.close();
      final fresh = make();
      expect(await ler(fresh), isEmpty);
      expect(keys.currentKey, key);
    },
  );

  test(
    'legado migrado: onLegacyMigrated é chamado; falha no callback é engolida',
    () async {
      databaseFactory = databaseFactoryFfi;
      final c = await databaseFactoryFfi.openDatabase(
        '${dir.path}/sinalacs_patient_consent.db',
      );
      await c.execute(
        'CREATE TABLE consent_preferences '
        '(purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)',
      );
      await c.insert('consent_preferences', {'purpose': 'push', 'granted': 1});
      await c.close();

      var migrated = 0;
      final db = PatientLocalDatabase(
        keys: keys,
        databaseName: name,
        allowUnencryptedForTesting: true,
        retryDelay: Duration.zero,
        onLegacyMigrated: () async {
          migrated++;
          throw StateError('falha');
        },
      );
      made.add(db);
      final conn = await db.open();
      expect(migrated, 1);
      expect(await conn.query('consent_preferences'), hasLength(1));
    },
  );

  Future<void> semearConsentimentoAntigo() async {
    final c = await databaseFactoryFfi.openDatabase(
      '${dir.path}/sinalacs_patient_consent.db',
    );
    await c.execute(
      'CREATE TABLE consent_preferences '
      '(purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)',
    );
    await c.insert('consent_preferences', {'purpose': 'push', 'granted': 1});
    await c.close();
  }

  test('onLegacyMigrated pode chamar open() sem travar (R8)', () async {
    await semearConsentimentoAntigo();
    late PatientLocalDatabase db;
    var linhas = -1;
    db = PatientLocalDatabase(
      keys: keys,
      databaseName: name,
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
      onLegacyMigrated: () async {
        linhas = (await (await db.open()).query('reminders')).length;
      }.timeoutWrap,
    );
    made.add(db);
    await db.open().timeout(const Duration(seconds: 5));
    expect(linhas, 0);
  });

  test('onKeyLost pode chamar open() sem travar (R8)', () async {
    final first = make();
    await gravar(first, 'x');
    await first.close();
    await keys.destroy();

    late PatientLocalDatabase db;
    var chamado = 0;
    db = make(
      onKeyLost: () async {
        chamado++;
        await db.open();
      }.timeoutWrap,
    );
    await db.open().timeout(const Duration(seconds: 5));
    expect(chamado, 1);
  });

  test(
    'deleteEverything apaga os arquivos legados; a próxima abertura não importa',
    () async {
      await semearConsentimentoAntigo();
      final db = make();
      await db.deleteEverything();
      expect(
        File('${dir.path}/sinalacs_patient_consent.db').existsSync(),
        isFalse,
      );
      expect(await (await db.open()).query('consent_preferences'), isEmpty);
    },
  );
}

extension on Future<void> Function() {
  Future<void> Function() get timeoutWrap =>
      () => this().timeout(const Duration(seconds: 5));
}
