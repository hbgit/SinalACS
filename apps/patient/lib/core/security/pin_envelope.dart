import 'dart:convert';
import 'dart:isolate';
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
///
/// A derivação roda inteira dentro de `Isolate.run` (#170), para a criação do
/// PIN e o login nunca travarem a animação do indicador de progresso. Medido
/// em build release num Galaxy A54 (Android 16): ~0,25 s por derivação e 119
/// quadros/s durante ela; sem nenhum isolate, 39 quadros/s. O
/// `package:cryptography` 2.9.0 já preenche a memória num isolate dele com
/// estes parâmetros, mas por uma heurística interna que zera com outra
/// memória ou outra versão do pacote; o `Isolate.run` torna a garantia nossa.
/// Só o PIN e o salt vão para o isolate; o armazenamento seguro fica na
/// thread principal.
class PinEnvelope {
  PinEnvelope({Random? random}) : _random = random ?? Random.secure();

  static const version = 1;

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
    final secretKey = SecretKey(await _deriveInBackground(pin, salt));
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
      final secretKey = SecretKey(await _deriveInBackground(pin, salt));
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

  /// Deriva a chave do envelope fora da thread da UI. Só tipos enviáveis
  /// atravessam o isolate (os bytes do PIN e do salt, de ida; os 32 bytes da
  /// chave, de volta): nada de `BuildContext`, plugin ou armazenamento.
  static Future<List<int>> _deriveInBackground(String pin, List<int> salt) {
    final pinBytes = utf8.encode(pin);
    final saltBytes = List<int>.of(salt);
    return Isolate.run(
      () => _deriveKeyBytes(pinBytes, saltBytes),
      debugName: 'pin-envelope-argon2id',
    );
  }
}

/// Argon2id, m = 19 MiB (19456 KiB), t = 2, p = 1, saída 32 bytes (D3). Os
/// parâmetros não mudam com a #170: o envelope gravado pela C-05 continua
/// abrindo (`test/pin_envelope_test.dart`, envelope de referência).
const pinEnvelopeArgon2Memory = 19456;
const pinEnvelopeArgon2Iterations = 2;
const pinEnvelopeArgon2Parallelism = 1;
const pinEnvelopeArgon2HashLength = 32;

/// Roda dentro do isolate de [PinEnvelope._deriveInBackground]. Função de
/// topo, sem capturar nada do envelope.
Future<List<int>> _deriveKeyBytes(List<int> pin, List<int> salt) async {
  final kdf = Argon2id(
    memory: pinEnvelopeArgon2Memory,
    iterations: pinEnvelopeArgon2Iterations,
    parallelism: pinEnvelopeArgon2Parallelism,
    hashLength: pinEnvelopeArgon2HashLength,
  );
  final key = await kdf.deriveKey(secretKey: SecretKey(pin), nonce: salt);
  return key.extractBytes();
}
