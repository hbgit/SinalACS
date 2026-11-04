import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sinalacs_patient/core/storage/patient_local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late PatientLocalDatabase database;
  late SqfliteConsentPreferences store;

  setUp(() async {
    // Banco único (#136), mesmo padrão de sqflite_reminder_store_test.dart.
    dir = await Directory.systemTemp.createTemp('patient_consent');
    databaseFactoryFfi.setDatabasesPath(dir.path);
    database = PatientLocalDatabase(
      keys: InMemoryDatabaseKeyProvider(),
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
    );
    store = SqfliteConsentPreferences(database);
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test('sem registro local, retorna null (nem aceite nem recusa)', () async {
    expect(await store.localRemindersGranted(), isNull);
  });

  test('grava aceite e recupera', () async {
    await store.saveLocalRemindersConsent(true);
    expect(await store.localRemindersGranted(), isTrue);
  });

  test('grava recusa e recupera', () async {
    await store.saveLocalRemindersConsent(true);
    await store.saveLocalRemindersConsent(false);
    expect(await store.localRemindersGranted(), isFalse);
  });

  test('gravar de novo substitui o valor anterior sem duplicar linha', () async {
    await store.saveLocalRemindersConsent(false);
    await store.saveLocalRemindersConsent(true);
    await store.saveLocalRemindersConsent(true);
    expect(await store.localRemindersGranted(), isTrue);
  });

  test('falha de abertura propaga LocalDatabaseUnavailableException', () async {
    final failing = PatientLocalDatabase(
      keys: InMemoryDatabaseKeyProvider(),
      databaseName: 'falha.db',
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
      openOverride: (_, _) async => throw StateError('disco'),
    );
    await expectLater(
      SqfliteConsentPreferences(failing).localRemindersGranted(),
      throwsA(isA<LocalDatabaseUnavailableException>()),
    );
  });
}
