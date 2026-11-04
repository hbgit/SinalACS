import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/sqflite_reminder_store.dart';
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
  late SqfliteReminderStore store;

  setUp(() async {
    // Banco único (#136) num diretório temporário por teste.
    dir = await Directory.systemTemp.createTemp('patient_reminders');
    databaseFactoryFfi.setDatabasesPath(dir.path);
    database = PatientLocalDatabase(
      keys: InMemoryDatabaseKeyProvider(),
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
    );
    store = SqfliteReminderStore(database);
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test('lista vazia quando não há lembretes', () async {
    expect(await store.list(), isEmpty);
  });

  test('salva e recupera um lembrete novo', () async {
    final saved = await store.save(const Reminder(
      id: 0, label: '08:00 - Losartana 50 mg', hour: 8, minute: 0, active: true,
    ));
    expect(saved.id, isNot(0));

    final all = await store.list();
    expect(all, hasLength(1));
    expect(all.first.label, '08:00 - Losartana 50 mg');
  });

  test('atualiza um lembrete existente sem duplicar', () async {
    final saved = await store.save(const Reminder(
      id: 0, label: 'Original', hour: 8, minute: 0, active: true,
    ));
    await store.save(saved.copyWith(active: false));

    final all = await store.list();
    expect(all, hasLength(1));
    expect(all.first.active, isFalse);
  });

  test('remove um lembrete', () async {
    final saved = await store.save(const Reminder(
      id: 0, label: 'Para remover', hour: 8, minute: 0, active: true,
    ));
    await store.delete(saved.id);
    expect(await store.list(), isEmpty);
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
      SqfliteReminderStore(failing).list(),
      throwsA(isA<LocalDatabaseUnavailableException>()),
    );
  });
}
