import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Código de ativação de uso único da MFA do staff (issue #48).
///
/// 130 bits de entropia: SHA-256 puro basta como hash (não há senha fraca a
/// proteger com KDF lento), e o código só existe em claro na saída da CLI.
class StaffActivationCode {
  const StaffActivationCode._();

  static const defaultValidity = Duration(hours: 24);
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const _length = 26;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final raw = List.generate(_length, (_) => _alphabet[r.nextInt(_alphabet.length)]);
    final grupos = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      grupos.add(raw.sublist(i, i + 4 > raw.length ? raw.length : i + 4).join());
    }
    return grupos.join('-');
  }

  static String normalize(String input) => input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static String hash(String code) => sha256.convert(utf8.encode(normalize(code))).toString();

  /// Comparação em tempo constante do hash de [input] com [storedHash].
  static bool matches(String input, String storedHash) {
    if (normalize(input).isEmpty) return false;
    final a = utf8.encode(hash(input));
    final b = utf8.encode(storedHash);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
