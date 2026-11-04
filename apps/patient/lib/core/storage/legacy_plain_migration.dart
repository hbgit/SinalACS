import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show Database, OpenDatabaseOptions, databaseFactory;

/// Migra os dois arquivos SQLite em claro do app (lembretes e consentimento)
/// para o banco cifrado (#136, INV-04).
///
/// Os arquivos antigos são abertos pela `databaseFactory` comum (a mesma dos
/// stores legados), pelo nome, no caminho padrão de bancos. Em teste, aponte
/// `databaseFactory = databaseFactoryFfi` e `setDatabasesPath(<tmp>)`.
///
/// Devolve `true` se migrou algo. Qualquer falha é engolida (sem log e sem
/// conteúdo: R4): os arquivos antigos ficam intactos, o banco cifrado segue
/// utilizável e a próxima abertura tenta de novo.
Future<bool> migrateLegacyPlainDatabases(
  Database encrypted, {
  String remindersName = 'sinalacs_patient_reminders.db',
  String consentName = 'sinalacs_patient_consent.db',
}) async {
  try {
    final copied = await copyLegacyRows(
      encrypted,
      remindersName: remindersName,
      consentName: consentName,
    );
    if (!copied) return false;
    // Só depois do commit: o que foi copiado já está no banco cifrado.
    for (final name in [remindersName, consentName]) {
      await _deleteLegacy(await _legacyPath(name));
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Só a cópia, numa única transação do banco cifrado. Idempotente
/// (`INSERT OR REPLACE`, preservando `id`). Lança se a leitura ou a escrita
/// falhar; a transação desfaz tudo. Devolve `false` sem arquivos antigos.
@visibleForTesting
Future<bool> copyLegacyRows(
  Database encrypted, {
  String remindersName = 'sinalacs_patient_reminders.db',
  String consentName = 'sinalacs_patient_consent.db',
}) async {
  final remindersPath = await _legacyPath(remindersName);
  final consentPath = await _legacyPath(consentName);
  final hasReminders = File(remindersPath).existsSync();
  final hasConsent = File(consentPath).existsSync();
  if (!hasReminders && !hasConsent) return false;

  await encrypted.transaction((txn) async {
    if (hasConsent) {
      final legacy = await _openReadOnly(consentPath);
      try {
        final rows = await legacy
            .rawQuery('SELECT purpose, granted FROM consent_preferences');
        for (final row in rows) {
          await txn.rawInsert(
            'INSERT OR REPLACE INTO consent_preferences (purpose, granted) '
            'VALUES (?, ?)',
            [row['purpose'], row['granted']],
          );
        }
      } finally {
        await legacy.close();
      }
    }
    if (hasReminders) {
      final legacy = await _openReadOnly(remindersPath);
      try {
        final rows = await legacy.rawQuery(
          'SELECT id, label, hour, minute, active FROM reminders',
        );
        for (final row in rows) {
          await txn.rawInsert(
            'INSERT OR REPLACE INTO reminders '
            '(id, label, hour, minute, active) VALUES (?, ?, ?, ?, ?)',
            [
              row['id'],
              row['label'],
              row['hour'],
              row['minute'],
              row['active'],
            ],
          );
        }
      } finally {
        await legacy.close();
      }
    }
  });
  return true;
}

Future<String> _legacyPath(String name) async =>
    '${await databaseFactory.getDatabasesPath()}/$name';

Future<Database> _openReadOnly(String path) =>
    databaseFactory.openDatabase(path, options: OpenDatabaseOptions());

Future<void> _deleteLegacy(String path) async {
  await databaseFactory.deleteDatabase(path);
  for (final suffix in ['', '-journal', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (file.existsSync()) await file.delete();
  }
}
