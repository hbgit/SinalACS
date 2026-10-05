import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_token_store.dart';

export 'session_token_store.dart';

/// Mesmas opções de [SecureStorageDatabaseKeyStore]: respaldo no Keystore e
/// fora de backup em nuvem.
const FlutterSecureStorage _defaultSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

class SecureStorageSessionTokenStore implements SessionTokenStore {
  SecureStorageSessionTokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? _defaultSecureStorage;

  static const _key = 'acs_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);

  @override
  Future<bool> contains() async => await read() != null;

  @override
  Future<SessionUnlock> unlock({required String reason}) async => SessionUnlock.notRequired;
}

class SecureStorageDeviceIdStore implements DeviceIdStore {
  SecureStorageDeviceIdStore({FlutterSecureStorage? storage}) : _storage = storage ?? _defaultSecureStorage;

  static const _key = 'acs_device_id';

  final FlutterSecureStorage _storage;

  @override
  Future<String> readOrCreate() {
    // Memoiza o Future: chamadas concorrentes na 1ª vez devolvem o mesmo id.
    // Uma falha não fica memorizada (a próxima chamada tenta de novo).
    final pending = _pending ??= _load();
    return pending.catchError((Object e) {
      _pending = null;
      throw e;
    });
  }

  Future<String>? _pending;

  Future<String> _load() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = generateDeviceId();
    await _storage.write(key: _key, value: created);
    return created;
  }
}
