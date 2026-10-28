import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_certificate_store.dart';

export 'device_certificate_store.dart';

/// Mesmas opções de `SecureStorageDatabaseKeyStore` e das outras lojas do app:
/// respaldo no Keystore (EncryptedSharedPreferences) e fora de backup em
/// nuvem. `test/device_certificate_store_test.dart` fixa este modo.
const FlutterSecureStorage _defaultSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

/// Certificado MQTT do aparelho (#94) no Keystore, sob
/// `acs_device_cert|<acsId>|<deviceId>` (valor JSON, com a chave privada).
///
/// [delete] por aparelho lê um ÍNDICE próprio
/// (`acs_device_cert_owners|<deviceId>`, lista JSON de `acsId`) em vez de
/// `readAll()`: apagar não pode carregar para a memória do Dart os outros
/// segredos do Keystore. Separado de `device_certificate_store.dart` para que
/// o enroller (que roda também na VM) não puxe o Flutter.
class SecureStorageDeviceCertificateStore implements DeviceCertificateStore {
  SecureStorageDeviceCertificateStore({FlutterSecureStorage? storage}) : _storage = storage ?? _defaultSecureStorage;

  final FlutterSecureStorage _storage;

  /// O armazenamento por baixo, para o teste conferir o modo.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

  static String keyFor({required String acsId, required String deviceId}) => 'acs_device_cert|$acsId|$deviceId';

  static String _indexKey(String deviceId) => 'acs_device_cert_owners|$deviceId';

  /// Cauda das mutações: gravação e exclusão do índice não se intercalam.
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<StoredDeviceCertificate?> read({required String acsId, required String deviceId}) async {
    final c = StoredDeviceCertificate.tryParse(await _storage.read(key: keyFor(acsId: acsId, deviceId: deviceId)));
    // Um registro sob a chave errada não serve a ninguém.
    if (c == null || c.acsId != acsId || c.deviceId != deviceId) return null;
    return c;
  }

  @override
  Future<void> write(StoredDeviceCertificate c) => _serial(() async {
        final owners = await _owners(c.deviceId);
        if (!owners.contains(c.acsId)) {
          await _storage.write(key: _indexKey(c.deviceId), value: jsonEncode([...owners, c.acsId]));
        }
        await _storage.write(key: keyFor(acsId: c.acsId, deviceId: c.deviceId), value: jsonEncode(c.toJson()));
      });

  @override
  Future<void> delete({required String deviceId}) => _serial(() async {
        for (final acsId in await _owners(deviceId)) {
          await _storage.delete(key: keyFor(acsId: acsId, deviceId: deviceId));
        }
        await _storage.delete(key: _indexKey(deviceId));
      });

  /// Índice ausente ou corrompido vale como vazio.
  Future<List<String>> _owners(String deviceId) async {
    final raw = await _storage.read(key: _indexKey(deviceId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>().toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }
}
