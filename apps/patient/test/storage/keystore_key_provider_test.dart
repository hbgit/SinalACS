import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/storage/keystore_key_provider.dart';
import 'package:sinalacs_patient/core/storage/local_database_key.dart';

/// Simula um Keystore que lança na leitura e/ou na escrita.
class _FalhaStorage extends FlutterSecureStorage {
  _FalhaStorage({this.falhaLeitura = false, this.falhaEscrita = false});

  final bool falhaLeitura;
  final bool falhaEscrita;
  int escritas = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (falhaLeitura) throw StateError('chave-secreta-no-erro');
    return null;
  }

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
    escritas++;
    if (falhaEscrita) throw StateError('chave-secreta-no-erro');
  }
}

void main() {
  final raw = RegExp(r"^x'[0-9a-f]{64}'$");

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sem banco e sem chave: cria no formato raw e grava', () async {
    final provider = KeystoreDatabaseKeyProvider();
    final first = await provider.obtain(databaseExists: false);
    expect(first, isA<KeyAvailable>());
    expect((first as KeyAvailable).rawKey, matches(raw));

    final second = await provider.obtain(databaseExists: true);
    expect((second as KeyAvailable).rawKey, first.rawKey);
  });

  test('banco existe e chave não: KeyLost, sem criar', () async {
    final provider = KeystoreDatabaseKeyProvider();
    expect(await provider.obtain(databaseExists: true), isA<KeyLost>());
    // Continua sem chave: nada foi criado.
    expect(await provider.obtain(databaseExists: true), isA<KeyLost>());
  });

  test('leitura que lança vira KeyUnavailable e não escreve nada', () async {
    final storage = _FalhaStorage(falhaLeitura: true);
    final provider = KeystoreDatabaseKeyProvider(storage: storage);
    expect(await provider.obtain(databaseExists: false),
        isA<KeyUnavailable>());
    expect(await provider.obtain(databaseExists: true),
        isA<KeyUnavailable>());
    expect(storage.escritas, 0);
  });

  test('escrita que lança vira LocalDatabaseUnavailableException sem origem',
      () async {
    final provider =
        KeystoreDatabaseKeyProvider(storage: _FalhaStorage(falhaEscrita: true));
    try {
      await provider.obtain(databaseExists: false);
      fail('deveria lançar');
    } on LocalDatabaseUnavailableException catch (e) {
      expect(e.toString(), isNot(contains('chave-secreta-no-erro')));
    }
  });

  test('toString não expõe a chave', () async {
    final state = await KeystoreDatabaseKeyProvider()
        .obtain(databaseExists: false) as KeyAvailable;
    expect(state.toString(), isNot(contains(state.rawKey)));
    expect(state.toString(), isNot(contains(state.rawKey.substring(2, 10))));
  });

  test('destroy apaga', () async {
    final provider = KeystoreDatabaseKeyProvider();
    await provider.obtain(databaseExists: false);
    await provider.destroy();
    expect(await provider.obtain(databaseExists: true), isA<KeyLost>());
  });

  group('InMemoryDatabaseKeyProvider', () {
    test('conta chamadas e segue a mesma regra de criação', () async {
      final p = InMemoryDatabaseKeyProvider();
      expect(await p.obtain(databaseExists: true), isA<KeyLost>());
      final s = await p.obtain(databaseExists: false) as KeyAvailable;
      expect(s.rawKey, matches(raw));
      expect(p.obtainCalls, 2);
      await p.destroy();
      expect(await p.obtain(databaseExists: true), isA<KeyLost>());
    });

    test('estados forçados são consumidos um por chamada', () async {
      final p = InMemoryDatabaseKeyProvider()..forceNext([KeyUnavailable()]);
      expect(await p.obtain(databaseExists: false), isA<KeyUnavailable>());
      expect(await p.obtain(databaseExists: false), isA<KeyAvailable>());
      expect(p.obtainCalls, 2);
    });
  });
}
