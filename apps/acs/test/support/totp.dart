import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Gerador TOTP (RFC 6238, SHA-1, 6 dígitos, 30 s) SÓ para testes: a prova de
/// MFA no emulador precisa produzir o código que o autenticador produziria.
String totpCode(Uint8List secret, DateTime at) {
  final passo = at.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final mensagem = ByteData(8)..setUint64(0, passo);
  final h = Hmac(sha1, secret).convert(mensagem.buffer.asUint8List()).bytes;
  final o = h[h.length - 1] & 0x0f;
  final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (bin % 1000000).toString().padLeft(6, '0');
}

/// Decodifica base32 (RFC 4648, sem preenchimento) — o que o servidor entrega em `secretBase32`.
Uint8List base32Decode(String texto) {
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0;
  var valor = 0;
  final saida = <int>[];
  for (final c in texto.toUpperCase().split('')) {
    final i = alfabeto.indexOf(c);
    if (i < 0) continue;
    valor = (valor << 5) | i;
    bits += 5;
    if (bits >= 8) {
      saida.add((valor >> (bits - 8)) & 0xff);
      bits -= 8;
      valor &= (1 << bits) - 1;
    }
  }
  return Uint8List.fromList(saida);
}
