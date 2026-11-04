import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/patient_local_stores.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_patient_backend.dart';

class _Scheduler implements ReminderScheduler {
  final rescheduled = <List<int>>[];
  var cancelAllCalls = 0;

  @override
  Future<void> schedule(Reminder reminder) async {}

  @override
  Future<void> cancel(int reminderId) async {}

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<void> rescheduleAll(List<Reminder> active) async {
    rescheduled.add([for (final r in active) r.id]);
  }
}

/// I1 / R14: o banco cifrado é aquecido depois do primeiro quadro, sem
/// navegar para Lembretes, Meus dados ou o cadastro.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late _Scheduler scheduler;
  late PatientLocalStores stores;

  // O setUp roda em tempo real (o isolate do sqlite não anda na zona falsa).
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('patient_warmup');
    scheduler = _Scheduler();
    databaseFactoryFfi.setDatabasesPath(dir.path);
    final r = await databaseFactoryFfi.openDatabase('${dir.path}/sinalacs_patient_reminders.db');
    await r.execute(
      'CREATE TABLE reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL, '
      'hour INTEGER NOT NULL, minute INTEGER NOT NULL, active INTEGER NOT NULL)',
    );
    await r.insert('reminders', {'id': 3, 'label': 'a', 'hour': 8, 'minute': 0, 'active': 1});
    await r.insert('reminders', {'id': 7, 'label': 'b', 'hour': 9, 'minute': 0, 'active': 0});
    await r.close();
    final c = await databaseFactoryFfi.openDatabase('${dir.path}/sinalacs_patient_consent.db');
    await c.execute('CREATE TABLE consent_preferences (purpose TEXT PRIMARY KEY, granted INTEGER NOT NULL)');
    await c.insert('consent_preferences', {'purpose': 'localReminders', 'granted': 1});
    await c.close();
    stores = PatientLocalStores(
      keys: InMemoryDatabaseKeyProvider(),
      scheduler: scheduler,
      allowUnencryptedForTesting: true,
      retryDelay: Duration.zero,
    );
  });

  testWidgets('partida sem navegar: arquivos antigos somem e os ativos são reagendados', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      reminderScheduler: scheduler,
      localStores: stores,
    ));
    // A abertura nasce na zona falsa do teste: alterna tempo real (isolate do
    // sqlite) e bombeamento (microtarefas).
    for (var i = 0; i < 100 && scheduler.rescheduled.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(scheduler.rescheduled, [
      [3],
    ]);
    expect(File('${dir.path}/sinalacs_patient_reminders.db').existsSync(), isFalse);
    expect(File('${dir.path}/sinalacs_patient_consent.db').existsSync(), isFalse);
    // O aviso de recuperação não é consumido pelo aquecimento.
    expect(stores.database.consumeRecoveryNotice(), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await stores.database.close();
      await dir.delete(recursive: true);
    });
  });
}
