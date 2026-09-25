import 'package:sqflite/sqflite.dart' hide databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory;

import 'reminder.dart';
import 'reminder_store.dart';

/// Implementação de [ReminderStore] sobre SQLite comum (`sqflite`), **sem**
/// SQLCipher: lembretes (horário, texto livre curto) não são dado de saúde
/// sensível no mesmo grau de `chronicConditions`/`answers`/`notes` (Track E
/// deste plano), e introduzir gestão de chave só para isto seria
/// desproporcional ao risco. Reavaliar se o campo de texto livre passar a
/// aceitar diagnóstico.
class SqfliteReminderStore implements ReminderStore {
  SqfliteReminderStore({this.databaseName = 'sinalacs_patient_reminders.db'});

  static const _table = 'reminders';
  final String databaseName;
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;

    return _database = await databaseFactory.openDatabase(
      databaseName,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
CREATE TABLE $_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  hour INTEGER NOT NULL,
  minute INTEGER NOT NULL,
  active INTEGER NOT NULL
)'''),
      ),
    );
  }

  @override
  Future<List<Reminder>> list() async {
    final db = await _open();
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
    final db = await _open();
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
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
