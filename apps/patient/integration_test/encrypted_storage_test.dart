/// Prova no aparelho de que o banco local do paciente está cifrado (#136).
///
/// Só funciona em dispositivo: no Linux o `flutter test` cai no FFI, sem
/// SQLCipher. Mesma lógica de `apps/acs/integration_test/encrypted_storage_test.dart`.
///
///   flutter test integration_test/encrypted_storage_test.dart -d emulator-5554
///
/// PRIVACIDADE: só rótulos e chaves sintéticos. `print` é aceitável aqui (a
/// regra de não registrar vale para `lib/core/storage`).
// ignore_for_file: avoid_print
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/sqflite_reminder_store.dart';
import 'package:sinalacs_patient/core/storage/keystore_key_provider.dart';
import 'package:sinalacs_patient/core/storage/legacy_plain_migration.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sinalacs_patient/core/storage/patient_local_database.dart';
import 'package:sqflite/sqflite.dart' as plain;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

const rotulo = 'losartana-teste-136';
const dbName = 'sinalacs_patient_crypto_probe.db';
const legacyReminders = 'sinalacs_patient_reminders_probe.db';
const legacyConsent = 'sinalacs_patient_consent_probe.db';
const realKeyName = 'sinalacs.patient.local_database_key';

Future<String> pathOf(String name) async =>
    '${await sqlcipher.getDatabasesPath()}/$name';

Future<void> removeFiles(String name) async {
  final path = await pathOf(name);
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) {
      try {
        await Process.run('chmod', ['600', f.path]);
      } catch (_) {}
      await f.delete();
    }
  }
}

String randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

String latin1Of(List<int> bytes) => String.fromCharCodes(bytes);

const reminder = Reminder(
  id: 0,
  label: rotulo,
  hour: 8,
  minute: 30,
  active: true,
);

PatientLocalDatabase newDb(LocalDatabaseKeyProvider keys) =>
    PatientLocalDatabase(
      keys: keys,
      databaseName: dbName,
      retryDelay: const Duration(milliseconds: 50),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => removeFiles(dbName));
  tearDown(() => removeFiles(dbName));

  test('chave raw chega crua ao SQLCipher (salt explícito)', () async {
    final key = randomHex(32);
    final salt = randomHex(16);
    final path = await pathOf(dbName);
    final db = await sqlcipher.openDatabase(
      path,
      password: "x'$key$salt'",
      version: 1,
      onCreate: (d, v) => d.execute('CREATE TABLE t (v TEXT)'),
    );
    await db.insert('t', {'v': 'linha'});
    await db.close();

    final head = (await File(path).openRead(0, 16).first).toList();
    final observed = head.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    print('SALT esperado=$salt observado=$observed');
    expect(observed, salt,
        reason: 'os 16 primeiros bytes devem ser o salt dado: a chave raw '
            'chegou crua ao SQLCipher');
  });

  test('arquivo não começa com "SQLite format 3" e não contém o rótulo do lembrete',
      () async {
    final db = newDb(InMemoryDatabaseKeyProvider());
    await SqfliteReminderStore(db).save(reminder);
    await db.close();

    final bytes = await File(await pathOf(dbName)).readAsBytes();
    expect(latin1Of(bytes.take(15).toList()), isNot('SQLite format 3'));
    expect(latin1Of(bytes).contains(rotulo), isFalse);
  });

  test(
      'chave errada pelo PatientLocalDatabase: LocalDatabaseUnavailableException, '
      'arquivo intacto (mesmos bytes), chave intacta', () async {
    final keys = InMemoryDatabaseKeyProvider();
    final first = newDb(keys);
    await SqfliteReminderStore(first).save(reminder);
    await first.close();

    final file = File(await pathOf(dbName));
    final before = await file.readAsBytes();

    final wrong = generateRawDatabaseKey();
    final other = InMemoryDatabaseKeyProvider(initialKey: wrong);
    final second = newDb(other);
    await expectLater(
      second.open(),
      throwsA(isA<LocalDatabaseUnavailableException>()),
    );

    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), before, reason: 'arquivo alterado');
    expect(other.currentKey, wrong, reason: 'a chave guardada foi trocada');

    // A chave certa ainda abre: nada foi apagado.
    final third = newDb(keys);
    expect(
      (await SqfliteReminderStore(third).list()).single.label,
      rotulo,
    );
    await third.close();
  });

  test('open_failed é ambíguo: chave errada e arquivo sem permissão dão o mesmo erro',
      () async {
    final key = generateRawDatabaseKey();
    final path = await pathOf(dbName);
    final db = await sqlcipher.openDatabase(
      path,
      password: key,
      version: 1,
      onCreate: (d, v) => d.execute('CREATE TABLE t (v TEXT)'),
    );
    await db.close();

    Future<String> failure(String k) async {
      try {
        final d = await sqlcipher.openDatabase(path, password: k);
        await d.query('sqlite_master');
        await d.close();
      } on Exception catch (e) {
        return e.toString();
      }
      return 'abriu';
    }

    final wrongKey = await failure(generateRawDatabaseKey());
    print('chave errada -> ${wrongKey.split('\n').first}');
    expect(wrongKey, contains('open_failed'));

    ProcessResult r;
    try {
      r = await Process.run('chmod', ['000', path]);
    } catch (e) {
      print('PULADO: chmod indisponível ($e)');
      return;
    }
    if (r.exitCode != 0) {
      print('PULADO: chmod 000 recusado (exit ${r.exitCode})');
      return;
    }
    try {
      final denied = await failure(key);
      print('sem permissão -> ${denied.split('\n').first}');
      expect(denied, contains('open_failed'));
      expect(wrongKey.contains('open_failed'), denied.contains('open_failed'));
    } finally {
      await Process.run('chmod', ['600', path]);
    }
  });

  test('fechar e reabrir com KeystoreDatabaseKeyProvider real mantém o lembrete',
      () async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final saved = await storage.read(key: realKeyName);
    try {
      await storage.delete(key: realKeyName);
      final keys = KeystoreDatabaseKeyProvider();
      final first = newDb(keys);
      await SqfliteReminderStore(first).save(reminder);
      await first.close();

      final second = newDb(KeystoreDatabaseKeyProvider());
      final list = await SqfliteReminderStore(second).list();
      expect(list.single.label, rotulo);
      await second.close();
    } finally {
      if (saved != null) {
        await storage.write(key: realKeyName, value: saved);
      } else {
        await storage.delete(key: realKeyName);
      }
    }
  });

  test('arquivo antigo em claro migra no aparelho e some', () async {
    await removeFiles(legacyReminders);
    await removeFiles(legacyConsent);
    final rPath = await pathOf(legacyReminders);
    final legacy = await plain.openDatabase(
      rPath,
      version: 1,
      onCreate: (d, v) => d.execute(
        'CREATE TABLE reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'label TEXT NOT NULL, hour INTEGER NOT NULL, minute INTEGER NOT NULL, '
        'active INTEGER NOT NULL)',
      ),
    );
    await legacy.insert('reminders', {
      'label': rotulo,
      'hour': 7,
      'minute': 0,
      'active': 1,
    });
    await legacy.close();
    // Confere que o arquivo antigo está mesmo em claro.
    expect(latin1Of(await File(rPath).readAsBytes()).contains(rotulo), isTrue);

    // Nomes próprios do teste: os arquivos reais do app ficam intactos.
    final db = newDb(InMemoryDatabaseKeyProvider());
    final handle = await db.open();
    final migrated = await migrateLegacyPlainDatabases(
      handle,
      remindersName: legacyReminders,
      consentName: legacyConsent,
    );
    expect(migrated, isTrue);
    final list = await SqfliteReminderStore(db).list();
    expect(list.single.label, rotulo);
    expect(File(rPath).existsSync(), isFalse, reason: 'arquivo antigo sobrou');
    await db.close();
  });

  test('tempo de open() (média de 10) registrado no log do teste', () async {
    final keys = InMemoryDatabaseKeyProvider();
    final seed = newDb(keys);
    await SqfliteReminderStore(seed).save(reminder);
    await seed.close();

    final sw = Stopwatch();
    var total = 0;
    for (var i = 0; i < 10; i++) {
      final db = newDb(keys);
      sw
        ..reset()
        ..start();
      await db.open();
      sw.stop();
      total += sw.elapsedMicroseconds;
      await db.close();
    }
    print('TEMPO open() média de 10 = ${(total / 10 / 1000).toStringAsFixed(1)} ms');
  });
}
