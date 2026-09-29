import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/sqflite_reminder_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqfliteReminderStore store;

  setUp(() {
    // Banco em memória por teste — nome único evita colisão entre casos.
    store = SqfliteReminderStore(databaseName: inMemoryDatabasePath);
  });

  tearDown(() => store.close());

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
}
