import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TOTP (RFC 6238) com SHA-1, 6 dígitos e passo de 30 s — o padrão que todo
/// aplicativo autenticador entende. Função pura: sem relógio, sem I/O.
class Totp {
  Totp._();

  static const period = 30;
  static const digits = 6;
  static const _alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static int stepOf(DateTime at) => at.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;

  static String code(Uint8List secret, DateTime at) => _hotp(secret, stepOf(at));

  /// Passo (`stepOf`) em que [code] confere, dentro de ±[window] passos de [at],
  /// ou `null`. Com [lastStep], só aceita passo **maior** que ele: é o que
  /// impede reaproveitar um código já usado dentro da janela (replay).
  static int? verify(
    Uint8List secret,
    String code,
    DateTime at, {
    int window = 1,
    int? lastStep,
  }) {
    final limpo = code.replaceAll(RegExp(r'\s'), '');
    if (limpo.length != digits || !RegExp(r'^\d+$').hasMatch(limpo)) return null;
    final atual = stepOf(at);
    // Todos os passos da janela são calculados e comparados, sem sair no
    // primeiro que confere, e cada comparação percorre os seis dígitos: o tempo
    // de resposta não diz em que passo, nem em que dígito, o código divergiu.
    int? aceito;
    for (var passo = atual - window; passo <= atual + window; passo++) {
      final confere = _iguaisEmTempoConstante(_hotp(secret, passo), limpo);
      if (confere && aceito == null && (lastStep == null || passo > lastStep)) {
        aceito = passo;
      }
    }
    return aceito;
  }

  /// Compara sem saída antecipada no primeiro caractere diferente.
  static bool _iguaisEmTempoConstante(String a, String b) {
    if (a.length != b.length) return false;
    var diferenca = 0;
    for (var i = 0; i < a.length; i++) {
      diferenca |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diferenca == 0;
  }

  static String _hotp(Uint8List secret, int counter) {
    final mensagem = ByteData(8)..setUint64(0, counter);
    final h = Hmac(sha1, secret).convert(mensagem.buffer.asUint8List()).bytes;
    final o = h[h.length - 1] & 0x0f;
    final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
    return (bin % 1000000).toString().padLeft(digits, '0');
  }

  /// Base32 (RFC 4648, sem preenchimento): o formato do segredo que o aplicativo
  /// autenticador pede quando a pessoa não lê o QR.
  static String base32(Uint8List bytes) {
    var bits = 0;
    var valor = 0;
    final saida = StringBuffer();
    for (final b in bytes) {
      valor = (valor << 8) | b;
      bits += 8;
      while (bits >= 5) {
        saida.write(_alfabeto[(valor >> (bits - 5)) & 31]);
        bits -= 5;
      }
      valor &= (1 << bits) - 1;
    }
    if (bits > 0) saida.write(_alfabeto[(valor << (5 - bits)) & 31]);
    return saida.toString();
  }

  static String otpauthUri({
    required String secretBase32,
    required String account,
    String issuer = 'SinalACS',
  }) =>
      'otpauth://totp/${Uri.encodeComponent(issuer)}:${Uri.encodeComponent(account)}'
      '?secret=$secretBase32&issuer=${Uri.encodeComponent(issuer)}'
      '&algorithm=SHA1&digits=$digits&period=$period';
}
