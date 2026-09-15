import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

/// Banco local criptografado com SQLCipher (AES-256).
///
/// **INV-04 do PRD**: dados de saúde sensíveis nunca podem ser persistidos em
/// texto plano. É por isso que o caminho sem criptografia deste arquivo exige
/// uma flag de nome constrangedor, e não é alcançável por descuido — antes ele
/// era o comportamento padrão fora de Android/iOS, e o único teste que existia
/// passava justamente por ele.
class EncryptedLocalDatabase {
  EncryptedLocalDatabase._();

  /// Versão do schema. Suba junto com [_upgrade] ao alterar as tabelas.
  ///
  /// v1 existiu em duas formas em campo: `local_queue(id)` — o que um aparelho
  /// com a versão anterior instalada tem — e uma `offline_visits` com
  /// `patient_name`. v2 grava `patient_id`. v4 acrescenta `rejection_reason`,
  /// para a visita recusada em definitivo pelo servidor (`SyncStatus.rejected`)
  /// ficar visível no aparelho em vez de retentar para sempre.
  static const schemaVersion = 4;

  /// Visitas registradas offline, aguardando sincronização.
  ///
  /// Só o que ainda precisa sair do dispositivo é gravado: a visita confirmada
  /// pelo servidor é removida no `save` seguinte, o que atende o princípio da
  /// minimização (LGPD-RF07 / seção 5.6 de spec/lgpd_design.md). Desde a v4,
  /// isso inclui a visita recusada em definitivo — ela fica no disco, com o
  /// motivo, até o ACS descartá-la explicitamente (ver `OfflineVisitQueue`).
  static const createOfflineVisits = '''
CREATE TABLE IF NOT EXISTS offline_visits (
  local_id TEXT PRIMARY KEY,
  patient_id TEXT NOT NULL,
  risk TEXT NOT NULL,
  status TEXT NOT NULL,
  outcome TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  version INTEGER NOT NULL,
  rejection_reason TEXT
)''';

  /// Migração v1 → v2, v2 → v3 e v3 → v4.
  ///
  /// Nenhuma das duas formas de v1 guarda o UUID do paciente: `patient_name`
  /// era `'Paciente ' + 8 dos 32 dígitos hex`, irreversível. Sem UUID,
  /// `visits.sync` responde `identificadores devem ser UUID` a cada tentativa —
  /// preservar essas linhas só encheria a fila de pendências que nunca sobem e,
  /// por isso mesmo, nunca saem do disco.
  ///
  /// Recriar (v1 → v2) perde as visitas pendentes gravadas antes desta versão.
  /// Era aceitável **apenas** porque o app ainda não tinha tido release. A
  /// partir da v3 → v4, a migração passa a ser só `ALTER TABLE ... ADD COLUMN`
  /// — aditiva, preserva as linhas existentes, que é o que uma migração depois
  /// do primeiro release precisa fazer.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('DROP TABLE IF EXISTS local_queue');
      await db.execute('DROP TABLE IF EXISTS offline_visits');
      await db.execute(createOfflineVisits);
      return;
    }

    if (from < 3) {
      final columns = await db.rawQuery(
        "PRAGMA table_info('offline_visits')",
      );
      final hasNotes = columns.any((column) => column['name'] == 'notes');
      if (!hasNotes) {
        await db.execute(
          "ALTER TABLE offline_visits ADD COLUMN notes TEXT NOT NULL DEFAULT '';",
        );
      }
    }

    if (from < 4) {
      final columns = await db.rawQuery(
        "PRAGMA table_info('offline_visits')",
      );
      final hasRejectionReason =
          columns.any((column) => column['name'] == 'rejection_reason');
      if (!hasRejectionReason) {
        await db.execute(
          'ALTER TABLE offline_visits ADD COLUMN rejection_reason TEXT;',
        );
      }
    }
  }

  /// Caminho do arquivo do banco neste dispositivo.
  ///
  /// Público para que o teste de migração consiga criar um banco v1 exatamente
  /// onde o app o abriria.
  static Future<String> pathFor(String databaseName) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) return '${await sqlcipher.getDatabasesPath()}/$databaseName';

    sqfliteFfiInit();
    return '${await databaseFactoryFfi.getDatabasesPath()}/$databaseName';
  }

  /// Abre o banco do dispositivo.
  ///
  /// [passphrase] vem do `DatabaseKeyStore` — nunca de literal no código.
  ///
  /// [allowUnencryptedForTesting] abre mão da criptografia e só existe para os
  /// testes que rodam na VM, onde o SQLCipher não está disponível. O nome é
  /// deliberadamente constrangedor: um `grep` por ele mostra todo ponto que
  /// abriu mão da garantia. Código de produção **não deve** passá-la — fora de
  /// Android/iOS, abrir sem ela lança.
  static Future<Database> open({
    required String databaseName,
    required String passphrase,
    bool allowUnencryptedForTesting = false,
  }) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (!isMobile && !allowUnencryptedForTesting) {
      throw UnsupportedError(
        'O SQLCipher só está disponível em Android/iOS. Abrir o banco aqui '
        'gravaria dados de saúde em texto plano, o que viola o INV-04 do PRD. '
        'Em teste, passe allowUnencryptedForTesting: true explicitamente.',
      );
    }

    if (passphrase.isEmpty) {
      throw ArgumentError('A passphrase do banco local é obrigatória.');
    }

    final path = await pathFor(databaseName);

    if (isMobile) {
      return sqlcipher.openDatabase(
        path,
        password: passphrase,
        version: schemaVersion,
        onCreate: (db, version) => db.execute(createOfflineVisits),
        onUpgrade: _upgrade,
        // Um rollback de APK abriria um arquivo v2 pedindo v1 e lançaria,
        // deixando o app travado a cada abertura.
        onDowngrade: onDatabaseDowngradeDelete,
      );
    }

    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => db.execute(createOfflineVisits),
        onUpgrade: _upgrade,
        onDowngrade: onDatabaseDowngradeDelete,
      ),
    );
  }

  /// Apaga o arquivo do banco.
  ///
  /// Usado quando a chave se perde (reinstalação, restauração de backup): sem a
  /// chave o arquivo é ilegível para sempre, então recomeçar é a única saída
  /// que não deixa o app travado.
  static Future<void> deleteDatabaseFile(String databaseName) async {
    final path = await pathFor(databaseName);

    if (Platform.isAndroid || Platform.isIOS) {
      return sqlcipher.deleteDatabase(path);
    }
    return databaseFactoryFfi.deleteDatabase(path);
  }
}
