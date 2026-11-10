import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/security/pin_policy.dart';

/// A política do PIN (C-05, decisão D3 do plano da #136): tamanho mínimo de 6
/// dígitos e a lista de PINs proibidos — defesa em profundidade documentada no
/// comentário da issue #128 e em `spec/lgpd_design.md` §0.
void main() {
  group('tamanho', () {
    test('menos de 6 dígitos é recusado', () {
      expect(pinWeakness('12345'), contains('6'));
      expect(isValidPin('12345'), isFalse);
      expect(pinWeakness(''), isNotNull);
    });

    test('6 ou mais dígitos passa', () {
      expect(isValidPin('284637'), isTrue);
      expect(isValidPin('2846371'), isTrue);
    });

    test('não-dígitos são recusados antes de qualquer outra regra', () {
      expect(pinWeakness('12a456'), contains('números'));
      expect(pinWeakness('284 637'), isNull, reason: 'espaços são ignorados');
    });
  });

  group('lista proibida', () {
    test('um só dígito repetido', () {
      expect(pinWeakness('000000'), isNotNull);
      expect(pinWeakness('111111'), isNotNull);
      expect(pinWeakness('99999999'), isNotNull);
    });

    test('sequências crescentes consecutivas cobrindo o PIN inteiro', () {
      expect(pinWeakness('123456'), isNotNull);
      expect(pinWeakness('456789'), isNotNull);
      expect(pinWeakness('23456789'), isNotNull);
    });

    test('sequências decrescentes consecutivas cobrindo o PIN inteiro', () {
      expect(pinWeakness('987654'), isNotNull);
      expect(pinWeakness('654321'), isNotNull);
    });

    test('alternância de dois dígitos', () {
      expect(pinWeakness('121212'), isNotNull);
      expect(pinWeakness('989898'), isNotNull);
      expect(pinWeakness('070707'), isNotNull);
    });

    test('a lista só pega o padrão inteiro, não trechos', () {
      // "112233" não é sequência nem alternância: é um PIN legítimo.
      expect(isValidPin('112233'), isTrue);
      // "1234567" é sequência inteira; "123450" não (o 0 quebra).
      expect(isValidPin('123450'), isTrue);
      // "121213" quebra a alternância no último dígito.
      expect(isValidPin('121213'), isTrue);
    });
  });
}
