import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'legacy_plain_migration.dart';
import 'local_data_control.dart';
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
class PatientLocalDatabase implements LocalDataControl {
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

  /// Chamado uma vez quando a migração dos arquivos em claro copiou algo
  /// (T5 reagenda as notificações). Falha nele é engolida.
  final Future<void> Function()? onLegacyMigrated;

  final Future<Database> Function(String path, String rawKey)? openOverride;

  Database? _database;
  Future<Database>? _inFlight;
  bool _recovered = false;
  bool _recoveredInFlight = false;

  /// Portão de operações: abrir, fechar e apagar rodam uma de cada vez, na
  /// ordem de chegada. Assim `open()` nunca lê a chave velha entre o fechar e
  /// o destruir de [deleteEverything], nem `close()` corre com uma abertura.
  Future<void> _gate = Future<void>.value();

  int _queued = 0;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    _queued++;
    final result = _gate.then((_) => operation());
    // O portão avança mesmo se a operação falhar; o erro vai a quem pediu.
    _gate = result
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(() => _queued--);
    return result;
  }

  /// `true` se esta execução recomeçou o banco por chave perdida.
  @override
  bool get recoveredFromLostKey => _recovered;

  bool _recoveryNoticePending = false;

  @override
  bool consumeRecoveryNotice() {
    final pending = _recoveryNoticePending;
    _recoveryNoticePending = false;
    return pending;
  }

  @override
  Future<void> retryOpen() => open();

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Abre (ou devolve) o banco. Aberturas concorrentes dividem um só voo; uma
  /// falha não é memoizada.
  Future<Database> open() {
    final existing = _database;
    // Atalho só com o portão ocioso: um apagar/fechar na fila vem antes.
    if (_queued == 0 && existing != null && existing.isOpen) {
      return Future.value(existing);
    }
    final joined = _inFlight;
    if (joined != null) return joined;

    final flight = _serialize(() async {
      final current = _database;
      if (current != null && current.isOpen) return (current, false);
      _recoveredInFlight = false;
      final db = await _openOnce();
      _database = db;
      // I2: um voo que recomeçou o banco não importa arquivo antigo nenhum.
      final migrated =
          _recoveredInFlight ? false : await migrateLegacyPlainDatabases(db);
      return (db, migrated);
    });
    final shared = flight
        .then((r) => r.$1)
        .whenComplete(() => _inFlight = null);
    shared.ignore();
    _inFlight = shared;
    return _finish(flight, shared);
  }

  /// R8: os callbacks rodam DEPOIS de a operação sair do portão e de
  /// `_inFlight` ser limpo; assim podem chamar `open()` sem travar. Cada um
  /// dispara no máximo uma vez por evento e seus erros são engolidos.
  Future<Database> _finish(
    Future<(Database, bool)> flight,
    Future<Database> shared,
  ) async {
    (Database, bool)? result;
    Object? failure;
    StackTrace? trace;
    try {
      result = await flight;
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
    try {
      await shared;
    } catch (_) {
      // O mesmo erro já está em [failure].
    }
    if (_lostPending) {
      _lostPending = false;
      await _fire(onKeyLost);
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    if (result!.$2) await _fire(onLegacyMigrated);
    return result.$1;
  }

  bool _lostPending = false;

  Future<void> _fire(Future<void> Function()? callback) async {
    if (callback == null) return;
    try {
      await callback();
    } catch (_) {
      // Reagendar/cancelar notificação nunca impede abrir.
    }
  }

  Future<void> close() => _serialize(_closeNow);

  Future<void> _closeNow() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// Fecha, apaga arquivo, laterais, chave e os arquivos legados em claro.
  /// Usado por "Apagar e recomeçar".
  ///
  /// Um apagar na fila atrás de uma abertura em voo fecha o handle que essa
  /// abertura devolveu (quem o segura vê `database_closed`); é aceito para
  /// "apagar".
  @override
  Future<void> deleteEverything() => _serialize(() async {
    await _closeNow();
    await _deleteFiles(await _path());
    try {
      await deleteLegacyPlainFiles();
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
    }
    try {
      await keys.destroy();
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
    }
    _recovered = false;
    _recoveryNoticePending = false;
  });

  Future<String> _path() async {
    if (_isMobile) {
      return '${await sqlcipher.getDatabasesPath()}/$databaseName';
    }
    sqfliteFfiInit();
    return '${await databaseFactoryFfi.getDatabasesPath()}/$databaseName';
  }

  /// Apaga pelo plugin e varre os laterais com dart:io. Qualquer erro
  /// (inclusive de arquivo) vira [LocalDatabaseUnavailableException], sem causa.
  Future<void> _deleteFiles(String path) async {
    try {
      if (_isMobile) {
        await sqlcipher.deleteDatabase(path);
      } else {
        await databaseFactoryFfi.deleteDatabase(path);
      }
      for (final suffix in _sidecars) {
        final file = File('$path$suffix');
        if (file.existsSync()) await file.delete();
      }
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
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
    if (!_isMobile && !allowUnencryptedForTesting) {
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
  ///
  /// O pendente de "chave perdida" sobe já no início (M1): mesmo que apagar
  /// falhe adiante, as notificações antigas são canceladas por [onKeyLost].
  /// Os arquivos legados em claro também caem (I2): o marcador da migração
  /// mora no banco que se perde, e sem apagá-los a próxima abertura os
  /// reimportaria, inclusive um consentimento antigo. Se não der para apagá-los,
  /// a recuperação para (falha fechada).
  Future<LocalKeyState> _recover(String path) async {
    _lostPending = true;
    await _deleteFiles(path);
    try {
      await deleteLegacyPlainFiles();
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
    }
    try {
      await keys.destroy();
    } catch (_) {
      // O arquivo já se foi (chave provadamente ausente); sem destruir o
      // envelope não se cria chave nova.
      throw const LocalDatabaseUnavailableException();
    }
    final state = await _obtain(false);
    _recovered = true;
    _recoveredInFlight = true;
    _recoveryNoticePending = true;
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
    await db.execute(
      'CREATE TABLE local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute('''
CREATE TABLE consent_preferences (
  purpose TEXT PRIMARY KEY,
  granted INTEGER NOT NULL
)''');
  }
}
