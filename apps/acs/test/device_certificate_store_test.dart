import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/security/secure_device_certificate_store.dart';

/// Loja do certificado MQTT do aparelho (#94). A chave privada do aparelho
/// repousa aqui: no Keystore, pelo MESMO modo das outras lojas do app
/// (`database_key_store.dart`), para a frase do `spec/stack.md` nunca ficar
/// falsa. Material sintético; nada aqui é chave de verdade.
void main() {
  StoredDeviceCertificate cert({String acsId = 'acs-1', String deviceId = 'aparelho-1', String serial = 's1'}) =>
      StoredDeviceCertificate(
        acsId: acsId,
        deviceId: deviceId,
        microAreaId: 'area-sintetica',
        serial: serial,
        certificatePem: 'CERT-SINTETICO',
        privateKeyPem: 'CHAVE-SINTETICA',
        notAfter: DateTime.utc(2026, 11, 26, 12),
        serverOffset: const Duration(minutes: -30),
      );

  test('a instância padrão usa EncryptedSharedPreferences (Keystore), como as outras lojas', () {
    final storage = SecureStorageDeviceCertificateStore().storage;
    expect(storage.aOptions.toMap()['encryptedSharedPreferences'], 'true');
    expect(
      storage.iOptions.toMap()['accessibility'],
      KeychainAccessibility.first_unlock_this_device.name,
    );
  });

  test('ida e volta: grava em acs_device_cert|<acsId>|<deviceId> e lê o mesmo registro', () async {
    final keystore = _KeystoreFalso();
    final store = SecureStorageDeviceCertificateStore(storage: keystore);

    await store.write(cert());

    expect(keystore.data.keys, contains('acs_device_cert|acs-1|aparelho-1'));
    final lido = await store.read(acsId: 'acs-1', deviceId: 'aparelho-1');
    expect(lido, isNotNull);
    expect(lido!.acsId, 'acs-1');
    expect(lido.deviceId, 'aparelho-1');
    expect(lido.microAreaId, 'area-sintetica');
    expect(lido.serial, 's1');
    expect(lido.certificatePem, 'CERT-SINTETICO');
    expect(lido.privateKeyPem, 'CHAVE-SINTETICA');
    expect(lido.notAfter, DateTime.utc(2026, 11, 26, 12));
    expect(lido.serverOffset, const Duration(minutes: -30));
    expect(await store.read(acsId: 'acs-2', deviceId: 'aparelho-1'), isNull);
  });

  test('valor corrompido vale como ausente', () async {
    final keystore = _KeystoreFalso({'acs_device_cert|acs-1|aparelho-1': '{lixo'});
    final store = SecureStorageDeviceCertificateStore(storage: keystore);

    expect(await store.read(acsId: 'acs-1', deviceId: 'aparelho-1'), isNull);
  });

  test('delete apaga os certificados de TODOS os ACS daquele aparelho, e só dele', () async {
    final keystore = _KeystoreFalso({'acs_refresh_token': 'outro-segredo'});
    final store = SecureStorageDeviceCertificateStore(storage: keystore);
    await store.write(cert(acsId: 'acs-1'));
    await store.write(cert(acsId: 'acs-2'));
    await store.write(cert(acsId: 'acs-1', deviceId: 'aparelho-2'));

    await store.delete(deviceId: 'aparelho-1');

    expect(await store.read(acsId: 'acs-1', deviceId: 'aparelho-1'), isNull);
    expect(await store.read(acsId: 'acs-2', deviceId: 'aparelho-1'), isNull);
    expect(await store.read(acsId: 'acs-1', deviceId: 'aparelho-2'), isNotNull);
    expect(keystore.data['acs_refresh_token'], 'outro-segredo');
    expect(keystore.data.keys.where((k) => k.contains('aparelho-1')), isEmpty);
    expect(keystore.readAllCalls, 0, reason: 'nunca carregar os outros segredos do Keystore');
  });

  test('InMemoryDeviceCertificateStore: ida e volta e delete por aparelho', () async {
    final store = InMemoryDeviceCertificateStore();
    await store.write(cert());
    expect((await store.read(acsId: 'acs-1', deviceId: 'aparelho-1'))?.serial, 's1');
    expect(store.writeCount, 1);

    await store.delete(deviceId: 'aparelho-1');

    expect(await store.read(acsId: 'acs-1', deviceId: 'aparelho-1'), isNull);
  });
}

/// Keystore em memória que RECUSA contar com `readAll`.
class _KeystoreFalso implements FlutterSecureStorage {
  _KeystoreFalso([Map<String, String>? inicial]) : data = {...?inicial};

  final Map<String, String> data;
  int readAllCalls = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCalls++;
    return Map.of(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
