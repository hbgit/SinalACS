import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/security/device_credential_store.dart';
import 'package:sinalacs_patient/core/security/pin_envelope.dart';

/// Duplo de teste da custódia da credencial de dispositivo (C-05).
///
/// Mantém os testes de widget herméticos longe do Keystore/Keychain — o
/// comportamento (envelope + bloqueio por tentativas) é o do real, mas em
/// memória e com relógio injetável para a contagem do bloqueio não esperar
/// tempo real.
class FakeDeviceCredentialStore implements DeviceCredentialStore {
  String? enrolledDeviceId;
  String? enrolledSecret;
  String? enrolledPin;

  int unlockCalls = 0;
  int destroyCalls = 0;
  int failures = 0;
  bool failEnroll = false;
  bool failUnlock = false;
  DateTime now = DateTime.utc(2026, 11, 9, 12);

  void enrollForTest({
    required String deviceId,
    required String secret,
    required String pin,
  }) {
    enrolledDeviceId = deviceId;
    enrolledSecret = secret;
    enrolledPin = pin;
  }

  @override
  Future<bool> hasCredential() async => enrolledDeviceId != null;

  @override
  Future<String?> deviceId() async => enrolledDeviceId;

  @override
  Future<void> enroll({
    required String pin,
    required String deviceId,
    required String secret,
  }) async {
    if (failEnroll) throw StateError('enroll falhou (injetado)');
    enrolledDeviceId = deviceId;
    enrolledSecret = secret;
    enrolledPin = pin;
    failures = 0;
  }

  @override
  Future<DeviceCredential> unlock(String pin) async {
    unlockCalls++;
    if (failUnlock) throw StateError('unlock falhou (injetado)');
    if (await remainingLockout() != null) throw const WrongPinException();
    if (enrolledDeviceId == null || pin != enrolledPin) {
      await recordFailure();
      throw const WrongPinException();
    }
    failures = 0;
    return DeviceCredential(
      deviceId: enrolledDeviceId!,
      secret: enrolledSecret!,
    );
  }

  @override
  Future<void> destroy() async {
    destroyCalls++;
    enrolledDeviceId = null;
    enrolledSecret = null;
    enrolledPin = null;
    failures = 0;
  }

  @override
  Future<Duration?> remainingLockout() async {
    if (failures < DeviceCredentialStore.maxAttempts) return null;
    final lockedUntil = DateTime.utc(2026, 11, 9, 12).add(
          DeviceCredentialStore.lockDuration(failures),
        );
    final remaining = lockedUntil.difference(now);
    return remaining.isNegative ? null : remaining;
  }

  @override
  Future<void> recordFailure() async {
    failures++;
  }

  @override
  Future<void> resetFailures() async {
    failures = 0;
  }
}

/// PIN sintético dos testes de widget que entram já com credencial.
const testPin = '284637';

/// Store com uma credencial sintética já gravada: a tela inicial abre no PIN.
FakeDeviceCredentialStore enrolledCredentialStore() => FakeDeviceCredentialStore()
  ..enrollForTest(
    deviceId: '00000000-0000-4000-8000-0000000000e2',
    secret: 'segredo-sintetico-de-teste',
    pin: testPin,
  );

/// Entra pelo PIN (RF24) na tela inicial de um app montado com
/// [enrolledCredentialStore].
Future<void> loginWithPin(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('pin_field')), testPin);
  await tester.tap(find.byKey(const Key('pin_unlock_button')));
  await tester.pumpAndSettle();
}
