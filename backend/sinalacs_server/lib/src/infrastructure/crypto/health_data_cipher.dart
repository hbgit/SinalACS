import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Um valor cifrado, pronto para persistir. `ciphertextBase64` empacota
/// nonce + texto cifrado + tag de autenticação — tudo que `decrypt`
/// precisa, num único campo de coluna.
class EncryptedValue {
  const EncryptedValue({required this.ciphertextBase64, required this.keyVersion});

  final String ciphertextBase64;
  final int keyVersion;
}

/// Criptografia AES-256-GCM de dados de saúde, na borda do repositório ORM
/// (RNF03, INV-04). Decisão §6 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md:
/// aplicação, não `pgcrypto` em SQL — o texto claro nunca deve passar pela
/// camada de log de query do Serverpod.
///
/// `keyVersion` acompanha cada valor cifrado para permitir rotação futura
/// sem reescrever todas as linhas de uma vez.
class HealthDataCipher {
  HealthDataCipher({required String keyHex, required this.keyVersion})
      : _algorithm = AesGcm.with256bits(),
        _secretKey = SecretKey(_hexToBytes(keyHex));

  final AesGcm _algorithm;
  final SecretKey _secretKey;
  final int keyVersion;

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  Future<EncryptedValue> encrypt(String plaintext) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: _secretKey,
    );
    // nonce + ciphertext + mac concatenados, para caber num único campo.
    final packed = <int>[
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return EncryptedValue(
      ciphertextBase64: base64.encode(packed),
      keyVersion: keyVersion,
    );
  }

  Future<String> decrypt(EncryptedValue value) async {
    final packed = base64.decode(value.ciphertextBase64);
    final nonceLength = _algorithm.nonceLength;
    const macLength = 16; // GCM: tag de 128 bits.

    final nonce = packed.sublist(0, nonceLength);
    final mac = Mac(packed.sublist(packed.length - macLength));
    final cipherText = packed.sublist(nonceLength, packed.length - macLength);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final clearBytes = await _algorithm.decrypt(secretBox, secretKey: _secretKey);
    return utf8.decode(clearBytes);
  }
}
