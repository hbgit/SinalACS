import '../storage/patient_local_database.dart';
import 'reminder.dart';
import 'reminder_store.dart';

/// Implementação de [ReminderStore] sobre o banco local do paciente.
///
/// Desde a #136, no banco cifrado: o rótulo é texto livre e pode citar
/// medicamento (dado de saúde, art. 11); a C-10 apaga tudo num ponto só.
///
/// Toda operação abre (ou reaproveita) o banco por [PatientLocalDatabase.open]
/// e propaga `LocalDatabaseUnavailableException` quando ele não abre: quem
/// chama decide o que mostrar.
class SqfliteReminderStore implements ReminderStore {
  SqfliteReminderStore(this._database);

  static const _table = 'reminders';
  final PatientLocalDatabase _database;

  @override
  Future<List<Reminder>> list() async {
    final db = await _database.open();
    final rows = await db.query(_table, orderBy: 'hour, minute');
    return [
      for (final row in rows)
        Reminder(
          id: row['id'] as int,
          label: row['label'] as String,
          hour: row['hour'] as int,
          minute: row['minute'] as int,
          active: (row['active'] as int) == 1,
        ),
    ];
  }

  @override
  Future<Reminder> save(Reminder reminder) async {
    final db = await _database.open();
    final values = {
      'label': reminder.label,
      'hour': reminder.hour,
      'minute': reminder.minute,
      'active': reminder.active ? 1 : 0,
    };

    if (reminder.id == 0) {
      final id = await db.insert(_table, values);
      return Reminder(
        id: id,
        label: reminder.label,
        hour: reminder.hour,
        minute: reminder.minute,
        active: reminder.active,
      );
    }

    await db.update(_table, values, where: 'id = ?', whereArgs: [reminder.id]);
    return reminder;
  }

  @override
  Future<void> delete(int id) async {
    final db = await _database.open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
