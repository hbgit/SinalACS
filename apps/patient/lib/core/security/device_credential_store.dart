import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sinalacs_patient/core/security/pin_envelope.dart';
import 'package:sinalacs_patient/core/security/pin_policy.dart';

/// A credencial de dispositivo do participante (C-05, RF24): o par sorteado na
/// conclusão do convite e reapresentado em `auth.loginDevice`.
class DeviceCredential {
  const DeviceCredential({required this.deviceId, required this.secret});

  final String deviceId;
  final String secret;

  @override
  String toString() => 'DeviceCredential($deviceId)'; // sem o segredo
}

/// Custódia local da credencial de dispositivo e do bloqueio por tentativas
/// de PIN. Interface aqui, implementação real sobre o `flutter_secure_storage`
/// ([SecureStorageDeviceCredentialStore]) e duplo de teste em `test/support/`.
///
/// Contrato de segurança:
/// - o **segredo** só existe cifrado no envelope do PIN (Argon2id + AES-GCM);
/// - o **PIN** nunca é gravado nem sai do aparelho;
/// - o bloqueio por tentativas é persistido e consultado ANTES de verificar o
///   PIN, para o tempo da recusa não servir de oráculo.
abstract interface class DeviceCredentialStore {
  /// Há uma credencial guardada neste aparelho? (lê só metadados, sem PIN.)
  Future<bool> hasCredential();

  /// O `deviceId` guardado, ou `null` sem credencial. Não é segredo — vai no
  /// JWT — e é o que a tela usa para saber que aparelho está entrando.
  Future<String?> deviceId();

  /// Grava a credencial protegida pelo [pin]. Recusa PIN fora da política
  /// ([pinWeakness]).
  Future<void> enroll({
    required String pin,
    required String deviceId,
    required String secret,
  });

  /// Abre a credencial com o [pin]. PIN errado conta uma tentativa; tentativas
  /// demais bloqueiam por um tempo crescente ([remainingLockout]).
  /// [WrongPinException] para PIN errado ou envelope corrompido.
  Future<DeviceCredential> unlock(String pin);

  /// Apaga credencial e o estado de tentativas (o caminho de "esqueci o PIN"
  /// e da C-10).
  Future<void> destroy();

  /// Tempo restante de bloqueio por tentativas, ou `null` se desbloqueado.
  Future<Duration?> remainingLockout();

  /// Registra uma falha de PIN. Acima de [maxAttempts] passa a bloquear com
  /// prazos crescentes.
  Future<void> recordFailure();

  /// Zera o contador de falhas (login bem-sucedido).
  Future<void> resetFailures();

  /// Falhas consecutivas até o bloqueio começar.
  static const maxAttempts = 5;

  /// Prazo do bloqueio a partir da [failures]-ésima falha: 30 s dobrando por
  /// falha além do teto, até 15 min. Não é segurança contra força bruta
  /// offline (que o bloqueio não alcança) — só contra a digitação insistida
  /// com o aparelho em mãos sem root.
  static Duration lockDuration(int failures) {
    final extra = failures - maxAttempts;
    if (extra < 0) return Duration.zero;
    final seconds = 30 * (1 << extra.clamp(0, 5));
    return Duration(seconds: seconds);
  }
}

/// Implementação real: envelope do PIN no `flutter_secure_storage`, preso ao
/// Keystore/Keychain do aparelho — mesmo arranjo da chave do banco local
/// (#136, `KeystoreDatabaseKeyProvider`).
class SecureStorageDeviceCredentialStore implements DeviceCredentialStore {
  SecureStorageDeviceCredentialStore({
    FlutterSecureStorage? storage,
    PinEnvelope? envelope,
    DateTime Function()? clock,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ),
        _envelope = envelope ?? PinEnvelope(),
        _clock = clock ?? DateTime.now;

  static const _credentialKey = 'sinalacs.patient.device_credential';
  static const _attemptsKey = 'sinalacs.patient.pin_attempts';

  final FlutterSecureStorage _storage;
  final PinEnvelope _envelope;
  final DateTime Function() _clock;

  @override
  Future<bool> hasCredential() async => await deviceId() != null;

  @override
  Future<String?> deviceId() async {
    final record = await _readCredentialRecord();
    return record?['deviceId'] as String?;
  }

  @override
  Future<void> enroll({
    required String pin,
    required String deviceId,
    required String secret,
  }) async {
    final weakness = pinWeakness(pin);
    if (weakness != null) {
      throw ArgumentError.value(pin, 'pin', weakness);
    }
    final sealed = await _envelope.encrypt(pin: pin, plaintext: secret);
    await _storage.write(
      key: _credentialKey,
      value: jsonEncode({
        'v': 1,
        'deviceId': deviceId,
        'envelope': sealed,
        'createdAt': _clock().toUtc().toIso8601String(),
      }),
    );
    await resetFailures();
  }

  @override
  Future<DeviceCredential> unlock(String pin) async {
    final lock = await remainingLockout();
    if (lock != null) {
      throw const WrongPinException();
    }

    final record = await _readCredentialRecord();
    final deviceId = record?['deviceId'] as String?;
    final sealed = record?['envelope'] as String?;
    if (deviceId == null || sealed == null) {
      throw const WrongPinException();
    }

    try {
      final secret = await _envelope.decrypt(pin: pin, envelopeJson: sealed);
      await resetFailures();
      return DeviceCredential(deviceId: deviceId, secret: secret);
    } on WrongPinException {
      await recordFailure();
      rethrow;
    }
  }

  @override
  Future<void> destroy() async {
    await _storage.delete(key: _credentialKey);
    await _storage.delete(key: _attemptsKey);
  }

  @override
  Future<Duration?> remainingLockout() async {
    final state = await _readAttempts();
    final lockedUntilMs = state?['lockedUntilMs'] as int?;
    if (lockedUntilMs == null) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(lockedUntilMs)
        .difference(_clock().toUtc());
    return remaining.isNegative ? null : remaining;
  }

  @override
  Future<void> recordFailure() async {
    final state = await _readAttempts() ?? <String, Object?>{};
    final failures = ((state['failures'] as int?) ?? 0) + 1;
    final lockedUntilMs = failures >= DeviceCredentialStore.maxAttempts
        ? _clock()
            .toUtc()
            .add(DeviceCredentialStore.lockDuration(failures))
            .millisecondsSinceEpoch
        : null;
    await _storage.write(
      key: _attemptsKey,
      value: jsonEncode({
        'failures': failures,
        if (lockedUntilMs != null) 'lockedUntilMs': lockedUntilMs,
      }),
    );
  }

  @override
  Future<void> resetFailures() async {
    await _storage.delete(key: _attemptsKey);
  }

  Future<Map<String, Object?>?> _readCredentialRecord() async {
    // Exceção engolida sem causa, como no KeystoreDatabaseKeyProvider (#136):
    // um Keystore inacessível falha fechado — sem credencial legível, a tela
    // oferece o convite, nunca entra com um segredo de lugar nenhum.
    final String? raw;
    try {
      raw = await _storage.read(key: _credentialKey);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, Object?>?> _readAttempts() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _attemptsKey);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
