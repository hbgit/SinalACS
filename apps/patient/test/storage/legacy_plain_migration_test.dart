import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/storage/legacy_plain_migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late Database encrypted;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('patient_legacy');
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(dir.path);
    encrypted = await databaseFactoryFfi.openDatabase(
      '${dir.path}/novo.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE reminders (id INTEGER PRIMARY KEY '
            'AUTOINCREMENT, label TEXT NOT NULL, hour INTEGER NOT NULL, '
            'minute INTEGER NOT NULL, active INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE consent_preferences '
            '(purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
  });

  tearDown(() async {
    await encrypted.close();
    await dir.delete(recursive: true);
  });

  Future<void> semearAntigos({bool divergente = false}) async {
    final r = await databaseFactoryFfi.openDatabase(
      '${dir.path}/sinalacs_patient_reminders.db',
    );
    if (divergente) {
      await r.execute(
        'CREATE TABLE reminders (id INTEGER PRIMARY KEY, '
        'label TEXT NOT NULL, minute INTEGER NOT NULL, '
        'active INTEGER NOT NULL)',
      );
      await r.insert('reminders', {
        'id': 3,
        'label': 'a',
        'minute': 0,
        'active': 1,
      });
    } else {
      await r.execute(
        'CREATE TABLE reminders (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, label TEXT NOT NULL, hour INTEGER NOT NULL, '
        'minute INTEGER NOT NULL, active INTEGER NOT NULL)',
      );
      await r.insert('reminders', {
        'id': 3,
        'label': 'a',
        'hour': 8,
        'minute': 0,
        'active': 1,
      });
      await r.insert('reminders', {
        'id': 7,
        'label': 'b',
        'hour': 9,
        'minute': 30,
        'active': 0,
      });
    }
    await r.close();
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

  bool antigosExistem() =>
      File('${dir.path}/sinalacs_patient_reminders.db').existsSync() ||
      File('${dir.path}/sinalacs_patient_consent.db').existsSync();

  test(
    'copia lembretes com os mesmos ids e consentimento; apaga os antigos',
    () async {
      await semearAntigos();
      expect(await migrateLegacyPlainDatabases(encrypted), isTrue);
      final rows = await encrypted.query('reminders', orderBy: 'id');
      expect([for (final r in rows) r['id']], [3, 7]);
      expect(rows[1]['hour'], 9);
      final consent = await encrypted.query('consent_preferences');
      expect(consent.single, {'purpose': 'push', 'granted': 1});
      expect(antigosExistem(), isFalse);
    },
  );

  test('rodar duas vezes (antigo ainda presente) não duplica', () async {
    await semearAntigos();
    expect(await copyLegacyRows(encrypted), isTrue);
    expect(await copyLegacyRows(encrypted), isTrue);
    final rows = await encrypted.query('reminders', orderBy: 'id');
    expect([for (final r in rows) r['id']], [3, 7]);
    expect(rows[1]['label'], 'b');
    expect(await encrypted.query('consent_preferences'), hasLength(1));
  });

  test('sem arquivos antigos: devolve false e não faz nada', () async {
    expect(await migrateLegacyPlainDatabases(encrypted), isFalse);
    expect(await encrypted.query('reminders'), isEmpty);
  });

  test('erro no meio da cópia: rollback, antigos intactos', () async {
    await semearAntigos(divergente: true);
    expect(await migrateLegacyPlainDatabases(encrypted), isFalse);
    expect(await encrypted.query('consent_preferences'), isEmpty);
    expect(await encrypted.query('reminders'), isEmpty);
    expect(
      File('${dir.path}/sinalacs_patient_reminders.db').existsSync(),
      isTrue,
    );
    expect(
      File('${dir.path}/sinalacs_patient_consent.db').existsSync(),
      isTrue,
    );
  });

  test(
    'marcador gravado na mesma transação da cópia; rollback não o deixa',
    () async {
      await semearAntigos();
      await copyLegacyRows(encrypted);
      expect(await encrypted.query('local_meta'), hasLength(1));
    },
  );

  test('rollback não deixa marcador', () async {
    await semearAntigos(divergente: true);
    await migrateLegacyPlainDatabases(encrypted);
    expect(await encrypted.query('local_meta'), isEmpty);
  });

  test(
    'cópia feita, apagar falhou, consentimento mudou: não ressuscita',
    () async {
      await semearAntigos();
      // Cópia commitada e arquivos antigos ainda presentes (apagar falhou).
      await copyLegacyRows(encrypted);
      await encrypted.update('consent_preferences', {'granted': 0});

      expect(await migrateLegacyPlainDatabases(encrypted), isFalse);
      final consent = await encrypted.query('consent_preferences');
      expect(consent.single['granted'], 0);
      expect(antigosExistem(), isFalse);
    },
  );
}
