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
