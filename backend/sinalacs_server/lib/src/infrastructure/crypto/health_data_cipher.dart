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
/// `keyVersion` é GRAVADO junto de cada valor cifrado para que uma rotina de
/// rotação futura saiba, linha a linha, com que chave cada valor foi cifrado.
/// Ele **não é consultado na decifragem**: [decrypt] ignora
/// `value.keyVersion` e usa sempre a única chave que este processo conhece
/// ([keyHex] do construtor). Enquanto a rotina de reescrita não existir, trocar
/// `HEALTH_DATA_ENCRYPTION_KEY` torna ILEGÍVEL (falha de autenticação GCM) tudo
/// que já estava gravado — ver o aviso no `.env.example`. Rotação de verdade é
/// melhoria de produção futura, não requisito deste MVP.
class HealthDataCipher {
  HealthDataCipher({required String keyHex, required this.keyVersion})
      : _algorithm = AesGcm.with256bits(),
        _secretKey = SecretKey(_hexToBytes(keyHex));

  final AesGcm _algorithm;
  final SecretKey _secretKey;
  final int keyVersion;

  static final _hex32Bytes = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Recusa qualquer coisa que não seja hex de 64 caracteres.
  ///
  /// O `~/ 2` abaixo truncava em silêncio uma string de comprimento ímpar (63
  /// caracteres viravam uma chave de 31 bytes), e um comprimento par porém
  /// errado (32 caracteres) produzia uma chave de tamanho inválido para
  /// AES-256 — as duas coisas só apareciam muito depois do boot. A validação
  /// primária é `AppConfig._resolveHealthDataEncryptionKey`; esta aqui é a
  /// rede de baixo, para quem construir a cifra sem passar pela config.
  static Uint8List _hexToBytes(String hex) {
    if (!_hex32Bytes.hasMatch(hex)) {
      throw ArgumentError.value(
        hex.length,
        'keyHex.length',
        'a chave de dados de saúde precisa ser hexadecimal de exatamente 64 '
            'caracteres (32 bytes, AES-256)',
      );
    }
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
