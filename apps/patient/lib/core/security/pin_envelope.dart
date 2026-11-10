import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sinalacs_patient/core/security/pin_policy.dart';

/// PIN digitado para um envelope que não é dele (ou envelope corrompido).
class WrongPinException implements Exception {
  const WrongPinException();

  @override
  String toString() => 'WrongPinException';
}

/// Envelope do PIN local (C-05, RF24): o segredo protegido fica cifrado com
/// AES-256-GCM sob uma chave derivada do PIN por Argon2id — os parâmetros são
/// a decisão D3 do plano da #136
/// (`docs/superpowers/plans/2026-11-03-issue-136-cifra-local-paciente.md`),
/// e a Fase 2 daquela issue reutiliza este mesmo envelope para embrulhar a
/// chave do banco local:
///
/// - salt aleatório de 16 bytes;
/// - Argon2id com m = 19 MiB, t = 2, p = 1, saída de 32 bytes;
/// - registro `{v, salt, nonce, ct}` em base64, guardado no
///   `flutter_secure_storage` (preso ao Keystore do aparelho).
///
/// O PIN nunca sai do aparelho e nunca é gravado: só a derivação dele é usada
/// para abrir o envelope. Erro de derivação e segredo corrompido produzem a
/// MESMA [WrongPinException], para o tempo da falha não servir de oráculo.
class PinEnvelope {
  PinEnvelope({Random? random}) : _random = random ?? Random.secure();

  static const version = 1;

  /// Argon2id, m = 19 MiB (19456 KiB), t = 2, p = 1, saída 32 bytes (D3).
  static final _kdf = Argon2id(
    memory: 19456,
    iterations: 2,
    parallelism: 1,
    hashLength: 32,
  );

  final Random _random;

  /// Cifra [plaintext] sob o [pin] e devolve o envelope como uma string JSON
  /// pronta para o `flutter_secure_storage`. Recusa PIN fora da política —
  /// defesa em profundidade da validação feita na tela.
  Future<String> encrypt({
    required String pin,
    required String plaintext,
  }) async {
    final weakness = pinWeakness(pin);
    if (weakness != null) {
      // Sem o valor na exceção: o `toString` de `ArgumentError.value` sairia
      // com o PIN, e o logcat do Android grava exceções não tratadas. A D3
      // veda o PIN em log/`toString` de exceção.
      throw ArgumentError(weakness, 'pin');
    }

    final salt = _randomBytes(16);
    final secretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    final nonce = _randomBytes(12);
    final aesGcm = AesGcm.with256bits();
    final sealed = await aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );
    final envelope = {
      'v': version,
      'salt': base64UrlEncode(salt),
      'nonce': base64UrlEncode(nonce),
      'ct': base64UrlEncode(sealed.cipherText),
      'mac': base64UrlEncode(sealed.mac.bytes),
    };
    return jsonEncode(envelope);
  }

  /// Abre o envelope com o [pin] e devolve o texto em claro. PIN errado ou
  /// envelope corrompido: [WrongPinException].
  Future<String> decrypt({
    required String pin,
    required String envelopeJson,
  }) async {
    final Map<String, Object?> envelope;
    try {
      final decoded = jsonDecode(envelopeJson);
      if (decoded is! Map<String, Object?>) {
        throw const WrongPinException();
      }
      envelope = decoded;
    } on FormatException {
      throw const WrongPinException();
    }

    final int? version = envelope['v'] as int?;
    final salt = _decodePart(envelope, 'salt');
    final nonce = _decodePart(envelope, 'nonce');
    final cipherText = _decodePart(envelope, 'ct');
    final mac = _decodePart(envelope, 'mac');
    if (version != PinEnvelope.version ||
        salt == null ||
        nonce == null ||
        cipherText == null ||
        mac == null) {
      throw const WrongPinException();
    }

    try {
      final secretKey = await _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      return utf8.decode(clear);
    } catch (_) {
      throw const WrongPinException();
    }
  }

  List<int>? _decodePart(Map<String, Object?> envelope, String name) {
    final value = envelope[name];
    if (value is! String) return null;
    try {
      return base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      return null;
    }
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
