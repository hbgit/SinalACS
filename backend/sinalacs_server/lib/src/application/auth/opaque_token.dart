import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Peças comuns dos tokens opacos do ACS (refresh token e token de envio
/// diferido): 256 bits aleatórios em base64url sem `=`, e o SHA-256 em hex que
/// é a única forma persistida. Um hash simples basta porque o token não vem de
/// uma escolha humana — não há espaço de busca a enumerar.
abstract final class OpaqueToken {
  /// Token novo: 32 bytes de [random] (`Random.secure()` em produção).
  static String generate(Random random) => base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');

  /// O que vai para o banco: o SHA-256 em hex, nunca o token.
  static String hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  /// UUID v4 a partir de [random], para o `id` da linha.
  static String uuid(Random random) {
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
