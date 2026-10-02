import 'dart:convert';

import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm, Database;

class CachedMicroArea {
  const CachedMicroArea({required this.patients, required this.fetchedAt});

  final List<MicroAreaPatient> patients;
  final DateTime fetchedAt;
}

/// Última lista da microárea no aparelho (RF08), na base SQLCipher das visitas.
///
/// Política em `spec/lgpd_design.md` §5.7: a lista pertence a um dono
/// (`userId|microAreaId`); [read] de **outro** dono apaga o cache em vez de
/// só escondê-lo — dado de outro território não fica no disco esperando uma
/// confusão.
class MicroAreaCacheStore {
  MicroAreaCacheStore({
    required DatabaseKeyStore keyStore,
    this.databaseName = 'sinalacs_acs.db',
    this.allowUnencryptedForTesting = false,
  }) : _keyStore = keyStore;

  static const _tabela = 'micro_area_cache';
  static const _meta = 'micro_area_cache_meta';
  static const _chaveDono = 'owner';
  static const _chaveData = 'fetched_at';

  final DatabaseKeyStore _keyStore;
  final String databaseName;
  final bool allowUnencryptedForTesting;
  Database? _database;

  Future<Database> _open() async {
    final existente = _database;
    if (existente != null && existente.isOpen) return existente;
    final passphrase = await _keyStore.readOrCreate();
    return _database = await EncryptedLocalDatabase.open(
      databaseName: databaseName,
      passphrase: passphrase,
      allowUnencryptedForTesting: allowUnencryptedForTesting,
    );
  }

  Future<CachedMicroArea?> read({required String owner}) async {
    final db = await _open();
    final meta = {
      for (final linha in await db.query(_meta)) linha['key'] as String: linha['value'] as String,
    };
    final donoGravado = meta[_chaveDono];
    final data = meta[_chaveData];
    if (donoGravado == null || data == null) return null;
    if (donoGravado != owner) {
      await clear();
      return null;
    }

    final linhas = await db.query(_tabela, orderBy: 'rowid');
    return CachedMicroArea(
      fetchedAt: DateTime.parse(data),
      patients: [
        for (final linha in linhas)
          MicroAreaPatient(
            patientId: linha['patient_id'] as String,
            name: linha['name'] as String,
            isChronic: (linha['is_chronic'] as int) == 1,
            chronicConditions: (jsonDecode(linha['chronic_conditions'] as String) as List).cast<String>(),
          ),
      ],
    );
  }

  Future<void> write({
    required String owner,
    required List<MicroAreaPatient> patients,
    required DateTime at,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_tabela);
      for (final p in patients) {
        await txn.insert(_tabela, {
          'patient_id': p.patientId,
          'name': p.name,
          'is_chronic': p.isChronic ? 1 : 0,
          'chronic_conditions': jsonEncode(p.chronicConditions),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert(_meta, {'key': _chaveDono, 'value': owner}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(_meta, {'key': _chaveData, 'value': at.toUtc().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> clear() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_tabela);
      await txn.delete(_meta);
    });
  }
}
