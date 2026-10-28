import 'package:basic_utils/basic_utils.dart';

/// Par de chaves EC P-256 do aparelho, em PEM (#94).
///
/// Dart puro, sem `dart:ui`: a árvore de `backend_client.dart` é importada
/// por uma ferramenta de VM. A chave privada só deve repousar no
/// `flutter_secure_storage`.
class DeviceKeyPair {
  const DeviceKeyPair({
    required this.privateKeyPem,
    required this.publicKeyPem,
  });

  final String privateKeyPem;
  final String publicKeyPem;
}

/// Gera um par EC P-256 novo para este aparelho.
DeviceKeyPair generateDeviceKeyPair() {
  final par = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  final priv = par.privateKey as ECPrivateKey;
  final pub = par.publicKey as ECPublicKey;
  return DeviceKeyPair(
    privateKeyPem: CryptoUtils.encodeEcPrivateKeyToPem(priv),
    publicKeyPem: CryptoUtils.encodeEcPublicKeyToPem(pub),
  );
}

/// CSR PKCS#10 com `CN = microAreaId`. Sem SAN: quem os define é o servidor.
String buildDeviceCsrPem({
  required DeviceKeyPair keyPair,
  required String microAreaId,
}) {
  return X509Utils.generateEccCsrPem(
    {'CN': microAreaId},
    CryptoUtils.ecPrivateKeyFromPem(keyPair.privateKeyPem),
    CryptoUtils.ecPublicKeyFromPem(keyPair.publicKeyPem),
  );
}
