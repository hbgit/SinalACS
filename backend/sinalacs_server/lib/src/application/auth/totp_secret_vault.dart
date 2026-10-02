import 'dart:typed_data';

/// Segredo TOTP já cifrado, com a versão da chave que o cifrou.
class SealedSecret {
  const SealedSecret({required this.ciphertextBase64, required this.keyVersion});

  final String ciphertextBase64;
  final int keyVersion;
}

/// Cifra e decifra o segredo TOTP. A camada de aplicação não conhece a cifra:
/// quem decide o algoritmo é `infrastructure/` (`HealthCipherTotpVault`).
abstract interface class TotpSecretVault {
  Future<SealedSecret> seal(Uint8List secret);
  Future<Uint8List> open(SealedSecret sealed);
}
