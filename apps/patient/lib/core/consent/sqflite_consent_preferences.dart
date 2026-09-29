import 'package:sinalacs_client/sinalacs_client.dart' show ConsentPurpose;
import 'package:sqflite/sqflite.dart' hide databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory;

import 'consent_preferences.dart';

/// Implementação de [ConsentPreferences] sobre SQLite comum (`sqflite`),
/// mesmo padrão de `SqfliteReminderStore`: não é dado de saúde, não precisa
/// de SQLCipher.
class SqfliteConsentPreferences implements ConsentPreferences {
  SqfliteConsentPreferences({this.databaseName = 'sinalacs_patient_consent.db'});

  static const _table = 'consent_preferences';
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
  purpose TEXT PRIMARY KEY,
  granted INTEGER NOT NULL
)'''),
      ),
    );
  }

  @override
  Future<bool?> localRemindersGranted() async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'purpose = ?',
      whereArgs: [ConsentPurpose.localReminders.name],
    );
    if (rows.isEmpty) return null;
    return (rows.first['granted'] as int) == 1;
  }

  @override
  Future<void> saveLocalRemindersConsent(bool granted) async {
    final db = await _open();
    await db.insert(
      _table,
      {
        'purpose': ConsentPurpose.localReminders.name,
        'granted': granted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
