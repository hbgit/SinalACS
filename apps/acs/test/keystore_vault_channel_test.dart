import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/security/keystore_vault.dart';

/// Fixa o contrato do canal que o `KeystoreVault.kt` cumpre: códigos de erro
/// `cancelled`/`lockedOut`/`invalidated`/qualquer outro (= `unavailable`), e
/// plugin ausente sempre como falha fechada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('br.com.prismrr.sinalacs.acs/keystore_vault');
  final vault = MethodChannelKeystoreVault();

  void mock(Future<Object?> Function(MethodCall) h) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(channel, h);

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final entry in {
    'cancelled': VaultFailure.cancelled,
    'lockedOut': VaultFailure.lockedOut,
    'invalidated': VaultFailure.invalidated,
    'qualquer-outro': VaultFailure.unavailable,
  }.entries) {
    test('unseal traduz o código ${entry.key}', () async {
      mock((_) async => throw PlatformException(code: entry.key));
      await expectLater(
        () => vault.unseal('a', reason: 'x'),
        throwsA(
          isA<VaultException>().having((e) => e.failure, 'failure', entry.value),
        ),
      );
    });
  }

  test('plugin ausente vira unavailable e isSupported false', () async {
    await expectLater(
      () => vault.unseal('a', reason: 'x'),
      throwsA(
        isA<VaultException>().having(
          (e) => e.failure,
          'failure',
          VaultFailure.unavailable,
        ),
      ),
    );
    expect(await vault.isSupported, isFalse);
  });

  test('plugin ausente em seal também vira VaultException(unavailable)', () async {
    await expectLater(
      () => vault.seal('a', 't'),
      throwsA(
        isA<VaultException>().having(
          (e) => e.failure,
          'failure',
          VaultFailure.unavailable,
        ),
      ),
    );
  });

  test('seal que falha vira VaultException(unavailable)', () async {
    mock((_) async => throw PlatformException(code: 'seal_failed'));
    await expectLater(
      () => vault.seal('a', 't'),
      throwsA(
        isA<VaultException>().having(
          (e) => e.failure,
          'failure',
          VaultFailure.unavailable,
        ),
      ),
    );
  });

  test('unseal devolve o texto e null quando não há blob', () async {
    mock((call) async {
      expect(call.method, 'unseal');
      expect(call.arguments, {'alias': 'a', 'reason': 'x'});
      return 'tok';
    });
    expect(await vault.unseal('a', reason: 'x'), 'tok');
    mock((_) async => null);
    expect(await vault.unseal('a', reason: 'x'), isNull);
  });
}
