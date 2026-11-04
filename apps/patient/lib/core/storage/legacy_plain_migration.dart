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
  var copiedNow = false;
  try {
    // R9: com o marcador, os arquivos antigos já foram copiados uma vez e o
    // consentimento do banco cifrado manda; nunca copiar de novo, para não
    // ressuscitar um consentimento revogado (LGPD).
    final marked = await encrypted.rawQuery(
      'SELECT 1 FROM local_meta WHERE key = ?',
      [_marker],
    );
    if (marked.isEmpty) {
      copiedNow = await copyLegacyRows(
        encrypted,
        remindersName: remindersName,
        consentName: consentName,
      );
      if (!copiedNow) return false;
    }
  } catch (_) {
    return false;
  }
  try {
    // Só depois do commit: o que foi copiado já está no banco cifrado. Se
    // apagar falhar, o marcador impede nova cópia e a próxima abertura limpa.
    await deleteLegacyPlainFiles(
      remindersName: remindersName,
      consentName: consentName,
    );
  } catch (_) {
    // Sem log: a próxima abertura repete.
  }
  return copiedNow;
}

const _marker = 'legacy_migrated';

/// Apaga os dois arquivos antigos em claro e os laterais.
Future<void> deleteLegacyPlainFiles({
  String remindersName = 'sinalacs_patient_reminders.db',
  String consentName = 'sinalacs_patient_consent.db',
}) async {
  for (final name in [remindersName, consentName]) {
    await _deleteLegacy(await _legacyPath(name));
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
        final rows = await legacy.rawQuery(
          'SELECT purpose, granted FROM consent_preferences',
        );
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
    // R9: o marcador entra na mesma transação da cópia.
    await txn.rawInsert(
      'INSERT OR REPLACE INTO local_meta (key, value) VALUES (?, ?)',
      [_marker, '1'],
    );
  });
  return true;
}

Future<String> _legacyPath(String name) async =>
    '${await databaseFactory.getDatabasesPath()}/$name';

Future<Database> _openReadOnly(String path) => databaseFactory.openDatabase(
  path,
  options: OpenDatabaseOptions(readOnly: true),
);

Future<void> _deleteLegacy(String path) async {
  await databaseFactory.deleteDatabase(path);
  for (final suffix in ['', '-journal', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (file.existsSync()) await file.delete();
  }
}
