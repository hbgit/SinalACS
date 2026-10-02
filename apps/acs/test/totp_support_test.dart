import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/totp.dart';

void main() {
  test('vetor RFC 6238: SHA-1, t=59 s dá 287082', () {
    final segredo = ascii.encode('12345678901234567890');
    expect(totpCode(segredo, DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)), '287082');
  });

  test('base32Decode devolve os 20 bytes ASCII do segredo de teste', () {
    expect(base32Decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'), ascii.encode('12345678901234567890'));
  });

  test('vetor RFC 6238: SHA-1, t=1111111109 s dá 081804', () {
    final segredo = ascii.encode('12345678901234567890');
    expect(totpCode(segredo, DateTime.fromMillisecondsSinceEpoch(1111111109000, isUtc: true)), '081804');
  });

  test('as duas cópias do gerador (test/ e integration_test/) são idênticas byte a byte', () {
    expect(File('integration_test/support/totp.dart').readAsBytesSync(),
        File('test/support/totp.dart').readAsBytesSync());
  });
}
