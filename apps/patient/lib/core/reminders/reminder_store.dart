import 'reminder.dart';

/// Persistência local dos lembretes. Interface testável sem SQLite real,
/// mesmo padrão de `application/`+`infrastructure/` do backend.
abstract interface class ReminderStore {
  Future<List<Reminder>> list();

  /// Insere (id == null/0 tratado pela implementação) ou atualiza por id.
  Future<Reminder> save(Reminder reminder);

  Future<void> delete(int id);
}
