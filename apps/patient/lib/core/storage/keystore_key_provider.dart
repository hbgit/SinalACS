import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_database_key.dart';

/// Guarda a chave raw do banco local no Android Keystore / iOS Keychain.
///
/// **Nunca registre a chave em log**, nem em mensagem de erro. Exceções da
/// custódia são descartadas, não embrulhadas: a causa pode carregar material
/// sensível.
class KeystoreDatabaseKeyProvider implements LocalDatabaseKeyProvider {
  KeystoreDatabaseKeyProvider({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Mesmas opções do app do ACS; minSdk 24 atende.
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            // `first_unlock_this_device` mantém a chave fora de backup em
            // nuvem e ilegível antes do primeiro desbloqueio.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _key = 'sinalacs.patient.local_database_key';

  final FlutterSecureStorage _storage;

  @override
  Future<LocalKeyState> obtain({required bool databaseExists}) async {
    String? existing;
    try {
      existing = await _storage.read(key: _key);
    } catch (_) {
      return KeyUnavailable();
    }
    if (existing != null && existing.isNotEmpty) return KeyAvailable(existing);
    if (databaseExists) return KeyLost();

    final created = generateRawDatabaseKey();
    try {
      await _storage.write(key: _key, value: created);
    } catch (_) {
      throw const LocalDatabaseUnavailableException();
    }
    return KeyAvailable(created);
  }

  @override
  Future<void> destroy() => _storage.delete(key: _key);
}
