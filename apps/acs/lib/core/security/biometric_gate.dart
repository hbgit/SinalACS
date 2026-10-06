import 'package:local_auth/local_auth.dart';

/// Resultado de uma tentativa de desbloqueio local.
enum UnlockResult { unlocked, cancelled, unavailable, lockedOut }

/// Porta do desbloqueio local (digital/rosto OU bloqueio de tela do aparelho).
abstract interface class BiometricGate {
  /// `true` se o aparelho tem biometria cadastrada OU bloqueio de tela seguro.
  Future<bool> get isAvailable;
  Future<UnlockResult> authenticate({required String reason});
}

/// Implementação sobre `local_auth` 3.x. Nunca registra a causa do erro.
class LocalAuthBiometricGate implements BiometricGate {
  LocalAuthBiometricGate([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> get isAvailable async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<UnlockResult> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
      return ok ? UnlockResult.unlocked : UnlockResult.cancelled;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          UnlockResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable =>
          UnlockResult.unavailable,
        _ => UnlockResult.cancelled,
      };
    } catch (_) {
      return UnlockResult.unavailable;
    }
  }
}
