import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'local_database_key.dart';

export 'local_database_key.dart' show LocalDatabaseUnavailableException;

/// O banco local está protegido por uma chave que exige o PIN (Fase 2).
class LocalDatabaseLockedException implements Exception {
  const LocalDatabaseLockedException();

  @override
  String toString() => 'LocalDatabaseLockedException';
}

/// Banco local único do app do paciente, cifrado com SQLCipher (INV-04).
///
/// Falha fechada (D2d): nenhum erro de abertura apaga arquivo ou chave. O único
/// caminho que apaga é a chave PROVADAMENTE perdida ([KeyLost]), e ele
/// recomeça o banco vazio. Nada aqui registra em log nem interpola uma exceção
/// capturada: a causa pode carregar material da custódia.
class PatientLocalDatabase {
  PatientLocalDatabase({
    required this.keys,
    this.databaseName = 'sinalacs_patient_local.db',
    this.allowUnencryptedForTesting = false,
    this.retryDelay = const Duration(milliseconds: 500),
    this.onKeyLost,
    this.onLegacyMigrated,
    @visibleForTesting this.openOverride,
  });

  /// C-04 sobe para 2 com `local_events`.
  static const schemaVersion = 1;

  static const _sidecars = ['-wal', '-shm', '-journal'];

  final LocalDatabaseKeyProvider keys;
  final String databaseName;

  /// Só para testes na VM, onde o SQLCipher não existe. Produção não passa.
  final bool allowUnencryptedForTesting;
  final Duration retryDelay;

  /// Chamado quando a chave se perdeu e o banco recomeçou (T5 cancela as
  /// notificações). Falha nele é engolida: nunca impede abrir.
  final Future<void> Function()? onKeyLost;

  // Guardado para a Task 4, que o chamará depois da migração legada.
  final Future<void> Function()? onLegacyMigrated;

  final Future<Database> Function(String path, String rawKey)? openOverride;

  Database? _database;
  Future<Database>? _inFlight;
  bool _recovered = false;

  /// `true` se esta execução recomeçou o banco por chave perdida.
  bool get recoveredFromLostKey => _recovered;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Abre (ou devolve) o banco. Aberturas concorrentes dividem um só voo; uma
  /// falha não é memoizada.
  Future<Database> open() {
    final existing = _database;
    if (existing != null && existing.isOpen) return Future.value(existing);
    return _inFlight ??= _openOnce().then((db) {
      _database = db;
      return db;
    }).whenComplete(() => _inFlight = null);
  }

  Future<void> close() async {
    final pending = _inFlight;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A falha da abertura em voo já chegou a quem a pediu.
      }
    }
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// Fecha, apaga arquivo, laterais e chave. Usado por "Apagar e recomeçar".
  Future<void> deleteEverything() async {
    await close();
    await _deleteFiles(await _path());
    try {
      await keys.destroy();
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
    }
    _recovered = false;
  }

  Future<String> _path() async {
    if (_isMobile) {
      return '${await sqlcipher.getDatabasesPath()}/$databaseName';
    }
    sqfliteFfiInit();
    return '${await databaseFactoryFfi.getDatabasesPath()}/$databaseName';
  }

  Future<void> _deleteFiles(String path) async {
    for (final suffix in ['', ..._sidecars]) {
      final file = File('$path$suffix');
      if (file.existsSync()) await file.delete();
    }
  }

  Future<LocalKeyState> _obtain(bool databaseExists) async {
    try {
      return await keys.obtain(databaseExists: databaseExists);
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
    }
  }

  Future<Database> _openOnce() async {
    if (!_isMobile && !allowUnencryptedForTesting && openOverride == null) {
      throw UnsupportedError(
        'O SQLCipher só está disponível em Android/iOS. Abrir o banco aqui '
        'gravaria dados de saúde em texto plano, o que viola o INV-04 do PRD. '
        'Em teste, passe allowUnencryptedForTesting: true explicitamente.',
      );
    }

    final path = await _path();
    var state = await _obtain(File(path).existsSync());
    if (state is KeyUnavailable) {
      await Future<void>.delayed(retryDelay);
      state = await _obtain(File(path).existsSync());
    }

    if (state is KeyLost) {
      state = await _recover(path);
    }

    switch (state) {
      case KeyAvailable(:final rawKey):
        return _openWithRetry(path, rawKey);
      case KeyLocked():
        throw const LocalDatabaseLockedException();
      case KeyLost():
      case KeyUnavailable():
        throw const LocalDatabaseUnavailableException();
    }
  }

  /// Recomeça o banco: só a partir de [KeyLost].
  Future<LocalKeyState> _recover(String path) async {
    await _deleteFiles(path);
    try {
      await keys.destroy();
    } catch (_) {
      // O arquivo já se foi (chave provadamente ausente); sem destruir o
      // envelope não se cria chave nova.
      throw const LocalDatabaseUnavailableException();
    }
    final callback = onKeyLost;
    if (callback != null) {
      try {
        await callback();
      } catch (_) {
        // Cancelar notificação nunca impede abrir.
      }
    }
    final state = await _obtain(false);
    _recovered = true;
    return state;
  }

  Future<Database> _openWithRetry(String path, String rawKey) async {
    try {
      return await _openRaw(path, rawKey);
    } catch (_) {
      await Future<void>.delayed(retryDelay);
    }
    try {
      return await _openRaw(path, rawKey);
    } catch (_) {
      // D2d: qualquer erro de abertura é falha fechada; nada é apagado e a
      // causa é descartada.
      throw const LocalDatabaseUnavailableException();
    }
  }

  Future<Database> _openRaw(String path, String rawKey) {
    final override = openOverride;
    if (override != null) return override(path, rawKey);

    if (_isMobile) {
      return sqlcipher.openDatabase(
        path,
        password: rawKey,
        version: schemaVersion,
        onCreate: (db, version) => _create(db),
        onDowngrade: onDatabaseDowngradeDelete,
      );
    }
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _create(db),
        onDowngrade: onDatabaseDowngradeDelete,
      ),
    );
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
CREATE TABLE reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  hour INTEGER NOT NULL,
  minute INTEGER NOT NULL,
  active INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE consent_preferences (
  purpose TEXT PRIMARY KEY,
  granted INTEGER NOT NULL
)''');
  }
}
