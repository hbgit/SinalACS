import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/events/local_event_log.dart';
import 'package:sinalacs_patient/core/events/sqflite_local_event_log.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sinalacs_patient/core/storage/patient_local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Trilha local de eventos (C-04, #127) sobre o banco do paciente.
///
/// Na VM o banco abre sem SQLCipher (`allowUnencryptedForTesting`): estes
/// testes provam o esquema, a migração e o que é gravado. A cifra do arquivo é
/// a mesma da #136, provada no aparelho por
/// `integration_test/encrypted_storage_test.dart`.
void main() {
  late Directory dir;
  late InMemoryDatabaseKeyProvider keys;
  const name = 'eventos.db';
  final made = <PatientLocalDatabase>[];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('patient_local_events');
    databaseFactoryFfi.setDatabasesPath(dir.path);
    // Chave já existente: o arquivo da v1 criado abaixo não é "chave perdida".
    keys = InMemoryDatabaseKeyProvider(initialKey: generateRawDatabaseKey());
  });

  tearDown(() async {
    for (final db in made) {
      await db.close();
    }
    made.clear();
    await dir.delete(recursive: true);
  });

  PatientLocalDatabase make() {
    final db = PatientLocalDatabase(
      keys: keys,
      databaseName: name,
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
    );
    made.add(db);
    return db;
  }

  final shownAt = DateTime.utc(2026, 11, 10, 14, 30);
  final event = LocalEvent(
    kind: LocalEventKind.call192OrientationShown,
    occurredAt: shownAt,
    engineVersion: 'arvore-v1',
  );

  test('grava e lê o evento da orientação "Ligar 192"', () async {
    final log = SqfliteLocalEventLog(make());

    await log.record(event);

    expect(await log.list(), [event]);
  });

  test('a linha tem só tipo, instante em UTC e versão do motor — nenhuma resposta', () async {
    final db = make();
    await SqfliteLocalEventLog(db).record(event);

    final conn = await db.open();
    final columns = [
      for (final c in await conn.rawQuery('PRAGMA table_info(local_events)')) c['name'],
    ];
    expect(columns, ['id', 'kind', 'occurred_at', 'engine_version']);
    final row = (await conn.query('local_events')).single;
    expect(row['kind'], 'orientacao_192_exibida');
    expect(row['occurred_at'], '2026-11-10T14:30:00.000Z');
    expect(row['engine_version'], 'arvore-v1');
  });

  test('o evento sobrevive a fechar e reabrir o banco', () async {
    final db = make();
    await SqfliteLocalEventLog(db).record(event);
    await db.close();

    expect(await SqfliteLocalEventLog(make()).list(), [event]);
  });

  test('banco da v1 sobe para a v2 sem perder lembretes e ganha local_events', () async {
    // O arquivo exatamente como a #136 o criava.
    final path = '${dir.path}/$name';
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'label TEXT NOT NULL, hour INTEGER NOT NULL, minute INTEGER NOT NULL, '
            'active INTEGER NOT NULL)',
          );
          await db.execute('CREATE TABLE local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute(
            'CREATE TABLE consent_preferences (purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)',
          );
        },
      ),
    );
    await v1.insert('reminders', {'label': 'remédio', 'hour': 8, 'minute': 0, 'active': 1});
    await v1.close();

    final db = make();
    final conn = await db.open();
    expect(await conn.getVersion(), PatientLocalDatabase.schemaVersion);
    expect([for (final r in await conn.query('reminders')) r['label']], ['remédio']);

    final log = SqfliteLocalEventLog(db);
    await log.record(event);
    expect(await log.list(), [event]);
  });

  test('"Apagar e recomeçar" (deleteEverything) leva a trilha junto', () async {
    final db = make();
    await SqfliteLocalEventLog(db).record(event);

    await db.deleteEverything();

    expect(await SqfliteLocalEventLog(make()).list(), isEmpty);
  });

  test('um tipo desconhecido gravado por outra versão do app é ignorado na leitura', () async {
    final db = make();
    final log = SqfliteLocalEventLog(db);
    await log.record(event);
    final conn = await db.open();
    await conn.insert('local_events', {
      'kind': 'tipo_de_uma_versao_futura',
      'occurred_at': shownAt.toIso8601String(),
      'engine_version': 'arvore-v9',
    });

    expect(await log.list(), [event]);
  });
}
