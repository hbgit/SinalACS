import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Custódia do refresh token rotativo do ACS (LGPD-RT06).
///
/// Fica no Android Keystore / iOS Keychain, como a chave do banco local. É o
/// que permite renovar o JWT de 15 minutos sem reter a senha em memória.
///
/// **Nunca registre o valor em log**, nem em mensagem de erro.
abstract interface class SessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

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
}

/// Duplo de teste: só em memória.
class MemorySessionTokenStore implements SessionTokenStore {
  MemorySessionTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// Identificador estável desta instalação. O servidor amarra a família do
/// refresh token a ele e recusa a troca por outro aparelho.
abstract interface class DeviceIdStore {
  Future<String> readOrCreate();
}

/// UUID v4 aleatório (sem dependência extra).
String generateDeviceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
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

class MemoryDeviceIdStore implements DeviceIdStore {
  MemoryDeviceIdStore([this._id]);

  String? _id;

  @override
  Future<String> readOrCreate() async => _id ??= generateDeviceId();
}
