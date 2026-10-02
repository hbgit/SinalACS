import 'dart:convert';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Cofre do segredo TOTP sobre a mesma AES-256-GCM dos dados clínicos
/// (`HEALTH_DATA_ENCRYPTION_KEY`). Uma chave a menos para gerir; o custo é que
/// quem a perde, perde também as MFAs — e a redefinição é manual (decisão D6).
class HealthCipherTotpVault implements TotpSecretVault {
  HealthCipherTotpVault(this._cipher);

  final HealthDataCipher _cipher;

  @override
  Future<SealedSecret> seal(Uint8List secret) async {
    final v = await _cipher.encrypt(base64Encode(secret));
    return SealedSecret(ciphertextBase64: v.ciphertextBase64, keyVersion: v.keyVersion);
  }

  @override
  Future<Uint8List> open(SealedSecret sealed) async {
    final claro = await _cipher.decrypt(
      EncryptedValue(ciphertextBase64: sealed.ciphertextBase64, keyVersion: sealed.keyVersion),
    );
    return base64Decode(claro);
  }
}
