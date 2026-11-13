import 'package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart';
import 'package:sinalacs_patient/core/events/sqflite_local_event_log.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:sinalacs_patient/core/reminders/sqflite_reminder_store.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';
import 'package:sinalacs_patient/core/storage/patient_local_database.dart';

/// Um único banco cifrado (#136) alimentando as lojas (e, desde a #127, a
/// trilha local de eventos), com os dois
/// eventos do banco ligados às notificações:
///
/// - chave perdida: o banco recomeçou vazio e não se sabem mais os ids, então
///   [ReminderScheduler.cancelAll];
/// - migração dos arquivos antigos em claro: as notificações agendadas antes
///   carregam o rótulo no corpo; com o consentimento local `true`, reagenda os
///   ativos com o corpo genérico, e em qualquer outro caso (recusa, sem
///   registro, falha de leitura) cancela tudo (falha fechada).
///
/// Nada aqui é lido na partida do app: o banco só abre quando uma tela pede
/// os lembretes ou o consentimento, e o alerta de urgência nunca espera por ele.
class PatientLocalStores {
  factory PatientLocalStores({
    required LocalDatabaseKeyProvider keys,
    required ReminderScheduler scheduler,
    bool allowUnencryptedForTesting = false,
    Duration retryDelay = const Duration(milliseconds: 500),
  }) {
    late final PatientLocalStores stores;
    final database = PatientLocalDatabase(
      keys: keys,
      allowUnencryptedForTesting: allowUnencryptedForTesting,
      retryDelay: retryDelay,
      onKeyLost: scheduler.cancelAll,
      // R8: o callback roda fora do portão do banco, então pode ler as lojas.
      onLegacyMigrated: () => _rescheduleAfterMigration(stores, scheduler),
    );
    return stores = PatientLocalStores._(
      database,
      SqfliteReminderStore(database),
      SqfliteConsentPreferences(database),
      SqfliteLocalEventLog(database),
    );
  }

  PatientLocalStores._(this.database, this.reminders, this.consent, this.events);

  final PatientLocalDatabase database;
  final SqfliteReminderStore reminders;
  final SqfliteConsentPreferences consent;

  /// Trilha local de eventos (C-04, #127), no mesmo banco cifrado.
  final SqfliteLocalEventLog events;

  static Future<void> _rescheduleAfterMigration(
    PatientLocalStores stores,
    ReminderScheduler scheduler,
  ) async {
    try {
      if (await stores.consent.localRemindersGranted() == true) {
        final active = (await stores.reminders.list()).where((r) => r.active).toList();
        await scheduler.rescheduleAll(active);
        return;
      }
    } catch (_) {
      // Cai no cancelamento abaixo.
    }
    await scheduler.cancelAll();
  }
}
