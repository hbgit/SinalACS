import 'package:sinalacs_client/sinalacs_client.dart' show ConsentPurpose;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../storage/patient_local_database.dart';
import 'consent_preferences.dart';

/// Implementação de [ConsentPreferences] sobre o banco local do paciente,
/// mesmo padrão de `SqfliteReminderStore`.
///
/// Desde a #136, o consentimento local fica no mesmo banco cifrado dos
/// lembretes; a C-10 apaga tudo num ponto só.
///
/// Propaga `LocalDatabaseUnavailableException` quando o banco não abre.
class SqfliteConsentPreferences implements ConsentPreferences {
  SqfliteConsentPreferences(this._database);

  static const _table = 'consent_preferences';
  final PatientLocalDatabase _database;

  @override
  Future<bool?> localRemindersGranted() async {
    final db = await _database.open();
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
    final db = await _database.open();
    await db.insert(
      _table,
      {
        'purpose': ConsentPurpose.localReminders.name,
        'granted': granted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
