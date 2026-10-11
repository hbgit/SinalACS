import 'dart:convert';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:test/test.dart';

void main() {
  // Segredo da RFC 6238 (Apêndice B): ASCII "12345678901234567890".
  final segredo = Uint8List.fromList(ascii.encode('12345678901234567890'));
  DateTime em(int segundos) => DateTime.fromMillisecondsSinceEpoch(segundos * 1000, isUtc: true);

  group('RFC 6238 — vetores do SHA-1 (6 últimos dígitos)', () {
    final vetores = {
      59: '287082',
      1111111109: '081804',
      1111111111: '050471',
      1234567890: '005924',
      2000000000: '279037',
      20000000000: '353130',
    };
    vetores.forEach((t, esperado) {
      test('T=$t → $esperado', () => expect(Totp.code(segredo, em(t)), esperado));
    });
  });

  test('base32 do segredo da RFC é o valor conhecido', () {
    expect(Totp.base32(segredo), 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  });

  test('o passo muda a cada 30 s', () {
    expect(Totp.stepOf(em(29)), 0);
    expect(Totp.stepOf(em(30)), 1);
  });

  group('verify', () {
    test('aceita o código do passo atual e devolve o passo', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, Totp.code(segredo, agora), agora), Totp.stepOf(agora));
    });

    test('aceita um passo antes e um depois (relógio fora por até 30 s)', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, Totp.code(segredo, agora.subtract(const Duration(seconds: 30))), agora),
          Totp.stepOf(agora) - 1);
      expect(Totp.verify(segredo, Totp.code(segredo, agora.add(const Duration(seconds: 30))), agora),
          Totp.stepOf(agora) + 1);
    });

    test('recusa dois passos de distância', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, Totp.code(segredo, agora.add(const Duration(seconds: 60))), agora), isNull);
    });

    test('recusa passo já usado (replay): só aceita passo MAIOR que lastStep', () {
      final agora = em(1111111111);
      final passo = Totp.stepOf(agora);
      expect(Totp.verify(segredo, Totp.code(segredo, agora), agora, lastStep: passo), isNull);
      expect(Totp.verify(segredo, Totp.code(segredo, agora), agora, lastStep: passo - 1), passo);
    });

    test('recusa código com tamanho errado ou não numérico, sem lançar', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, '12345', agora), isNull);
      expect(Totp.verify(segredo, '1234567', agora), isNull);
      expect(Totp.verify(segredo, 'abcdef', agora), isNull);
      expect(Totp.verify(segredo, '', agora), isNull);
    });

    test('ignora espaços em volta do código (apps agrupam "123 456")', () {
      final agora = em(1111111111);
      final c = Totp.code(segredo, agora);
      expect(Totp.verify(segredo, '${c.substring(0, 3)} ${c.substring(3)}', agora), Totp.stepOf(agora));
    });
  });

  test('otpauthUri tem o formato que os autenticadores leem', () {
    final uri = Totp.otpauthUri(secretBase32: 'ABC234', account: 'ACS-001');
    expect(uri, 'otpauth://totp/SinalACS:ACS-001?secret=ABC234&issuer=SinalACS&algorithm=SHA1&digits=6&period=30');
  });
}
