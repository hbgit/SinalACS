import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/security/device_credential_store.dart';
import 'package:sinalacs_patient/core/security/pin_envelope.dart';

/// A custódia da credencial de dispositivo (C-05) sobre o
/// `flutter_secure_storage` **de verdade** (mock do canal da plataforma):
/// enroll/unlock/destroy e o bloqueio por tentativas persistido.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime agora = DateTime.utc(2026, 11, 9, 12);

  SecureStorageDeviceCredentialStore store() => SecureStorageDeviceCredentialStore(
        clock: () => agora,
      );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    agora = DateTime.utc(2026, 11, 9, 12);
  });

  test('enroll guarda o deviceId legível e o segredo só no envelope', () async {
    final custodia = store();
    expect(await custodia.hasCredential(), isFalse);

    await custodia.enroll(pin: '284637', deviceId: 'device-1', secret: 'segredo');

    expect(await custodia.hasCredential(), isTrue);
    expect(await custodia.deviceId(), 'device-1');
    final aberta = await custodia.unlock('284637');
    expect(aberta.deviceId, 'device-1');
    expect(aberta.secret, 'segredo');

    // O armazenamento cru não tem o segredo em claro (nem o PIN).
    const cru = FlutterSecureStorage();
    final registro = await cru.read(key: 'sinalacs.patient.device_credential');
    expect(registro, isNotNull);
    expect(registro!.contains('segredo'), isFalse);
    expect(registro.contains('284637'), isFalse);
  });

  test('PIN errado lança WrongPinException e conta tentativa', () async {
    final custodia = store();
    await custodia.enroll(pin: '284637', deviceId: 'device-1', secret: 'segredo');

    await expectLater(custodia.unlock('000000'), throwsA(isA<WrongPinException>()));
    expect(await custodia.remainingLockout(), isNull,
        reason: 'menos de ${DeviceCredentialStore.maxAttempts} falhas não bloqueia');

    // O PIN certo zera o contador e abre.
    final aberta = await custodia.unlock('284637');
    expect(aberta.secret, 'segredo');
  });

  test('tentativas demais bloqueiam por um prazo crescente, e o PIN certo não fura o bloqueio', () async {
    final custodia = store();
    await custodia.enroll(pin: '284637', deviceId: 'device-1', secret: 'segredo');

    for (var i = 0; i < DeviceCredentialStore.maxAttempts; i++) {
      await expectLater(custodia.unlock('000000'), throwsA(isA<WrongPinException>()));
    }

    final bloqueio = await custodia.remainingLockout();
    expect(bloqueio, isNotNull);
    expect(bloqueio, greaterThan(Duration.zero));
    // Mesmo o PIN certo é recusado enquanto o bloqueio estiver de pé.
    await expectLater(custodia.unlock('284637'), throwsA(isA<WrongPinException>()));

    // Relógio avança: libera e o PIN certo entra.
    agora = agora.add(const Duration(minutes: 1));
    expect(await custodia.remainingLockout(), isNull);
    expect((await custodia.unlock('284637')).secret, 'segredo');
  });

  test('5ª falha: 30 s, dobrando até 15 min', () {
    expect(DeviceCredentialStore.lockDuration(4), Duration.zero);
    expect(DeviceCredentialStore.lockDuration(5), const Duration(seconds: 30));
    expect(DeviceCredentialStore.lockDuration(6), const Duration(seconds: 60));
    expect(DeviceCredentialStore.lockDuration(9), const Duration(minutes: 8));
    expect(DeviceCredentialStore.lockDuration(10), const Duration(minutes: 15));
    expect(DeviceCredentialStore.lockDuration(50), const Duration(minutes: 15));
  });

  test('destroy apaga credencial e tentativas', () async {
    final custodia = store();
    await custodia.enroll(pin: '284637', deviceId: 'device-1', secret: 'segredo');
    await expectLater(custodia.unlock('000000'), throwsA(isA<WrongPinException>()));

    await custodia.destroy();

    expect(await custodia.hasCredential(), isFalse);
    expect(await custodia.deviceId(), isNull);
    expect(await custodia.remainingLockout(), isNull);
    await expectLater(custodia.unlock('284637'), throwsA(isA<WrongPinException>()));
  });

  test('enroll recusa PIN fora da política e sem credencial não há o que abrir', () async {
    final custodia = store();
    // PIN fraco que NÃO é citado na mensagem da política: o teste prova que o
    // valor não vai para a exceção, e não que a mensagem deixou de citar um
    // exemplo.
    await expectLater(
      custodia.enroll(pin: '654321', deviceId: 'device-1', secret: 'x'),
      throwsA(
        isA<ArgumentError>()
            .having((e) => e.toString(), 'toString', isNot(contains('654321'))),
      ),
    );
    expect(await custodia.hasCredential(), isFalse);
    await expectLater(custodia.unlock('654321'), throwsA(isA<WrongPinException>()));
  });
}
