import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'upload_token_store.dart';

export 'upload_token_store.dart';

/// Mesmas opções de `SecureStorageSessionTokenStore`: respaldo no Keystore e
/// fora de backup em nuvem.
const FlutterSecureStorage _defaultSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

/// Tokens de envio diferido no Keystore, um por dono, sob
/// `acs_upload_token|<userId>` (D7). Separado de `upload_token_store.dart`
/// para que `backend_client.dart` (que roda também na VM) não puxe o Flutter.
class SecureStorageUploadTokenStore implements UploadTokenStore {
  SecureStorageUploadTokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? _defaultSecureStorage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String ownerId) async {
    final value = await _storage.read(key: uploadTokenKey(ownerId));
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String ownerId, String token) => _storage.write(key: uploadTokenKey(ownerId), value: token);

  @override
  Future<void> clear(String ownerId) => _storage.delete(key: uploadTokenKey(ownerId));

  @override
  Future<List<String>> owners() async {
    final all = await _storage.readAll();
    return [
      for (final entry in all.entries)
        if (entry.key.startsWith(uploadTokenKeyPrefix) &&
            entry.key.length > uploadTokenKeyPrefix.length &&
            entry.value.isNotEmpty)
          entry.key.substring(uploadTokenKeyPrefix.length),
    ];
  }
}
