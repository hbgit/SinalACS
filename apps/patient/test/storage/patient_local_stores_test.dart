import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/patient_local_stores.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Registra as chamadas, sem canal de plataforma.
class _RecordingScheduler implements ReminderScheduler {
  final scheduled = <int>[];
  var cancelAllCalls = 0;
  final rescheduled = <List<int>>[];

  @override
  Future<void> schedule(Reminder reminder) async => scheduled.add(reminder.id);

  @override
  Future<void> cancel(int reminderId) async {}

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<void> rescheduleAll(List<Reminder> active) async {
    rescheduled.add([for (final r in active) r.id]);
  }
}

void main() {
  late Directory dir;
  late _RecordingScheduler scheduler;
  final made = <PatientLocalStores>[];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('patient_local_stores');
    databaseFactoryFfi.setDatabasesPath(dir.path);
    scheduler = _RecordingScheduler();
  });

  tearDown(() async {
    for (final stores in made) {
      await stores.database.close();
    }
    made.clear();
    await dir.delete(recursive: true);
  });

  PatientLocalStores make(LocalDatabaseKeyProvider keys) {
    final stores = PatientLocalStores(
      keys: keys,
      scheduler: scheduler,
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
    );
    made.add(stores);
    return stores;
  }

  Future<void> semearAntigos({required bool granted}) async {
    final r = await databaseFactoryFfi.openDatabase('${dir.path}/sinalacs_patient_reminders.db');
    await r.execute(
      'CREATE TABLE reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL, '
      'hour INTEGER NOT NULL, minute INTEGER NOT NULL, active INTEGER NOT NULL)',
    );
    await r.insert('reminders', {'id': 3, 'label': 'a', 'hour': 8, 'minute': 0, 'active': 1});
    await r.insert('reminders', {'id': 7, 'label': 'b', 'hour': 9, 'minute': 30, 'active': 0});
    await r.close();
    final c = await databaseFactoryFfi.openDatabase('${dir.path}/sinalacs_patient_consent.db');
    await c.execute('CREATE TABLE consent_preferences (purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)');
    await c.insert('consent_preferences', {'purpose': 'localReminders', 'granted': granted ? 1 : 0});
    await c.close();
  }

  test('chave perdida cancela todas as notificações agendadas', () async {
    final first = make(InMemoryDatabaseKeyProvider());
    await first.reminders.save(const Reminder(id: 0, label: 'x', hour: 8, minute: 0, active: true));
    await first.database.close();

    // Mesmo arquivo, custódia sem chave: a chave se perdeu.
    final second = make(InMemoryDatabaseKeyProvider());
    expect(await second.reminders.list(), isEmpty);

    expect(second.database.recoveredFromLostKey, isTrue);
    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.scheduled, isEmpty);
  });

  test('migração dos arquivos antigos com consentimento reagenda só os ativos', () async {
    await semearAntigos(granted: true);
    final stores = make(InMemoryDatabaseKeyProvider());

    expect(await stores.reminders.list(), hasLength(2));

    expect(scheduler.rescheduled, [
      [3],
    ]);
    expect(scheduler.cancelAllCalls, 0);
  });

  test('migração sem consentimento cancela tudo e não reagenda', () async {
    await semearAntigos(granted: false);
    final stores = make(InMemoryDatabaseKeyProvider());

    expect(await stores.reminders.list(), hasLength(2));

    expect(scheduler.rescheduled, isEmpty);
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelAllCalls, 1);
  });
}
