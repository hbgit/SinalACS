import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:test/test.dart';

void main() {
  group('Cpf.tryParse', () {
    test('aceita CPF sintético com dígitos verificadores corretos', () {
      // Exemplos da documentação do próprio algoritmo de DV — nunca um CPF real.
      expect(Cpf.tryParse('12345678909')?.digits, '12345678909');
      expect(Cpf.tryParse('98765432100')?.digits, '98765432100');
    });

    test('normaliza a máscara que a pessoa digita', () {
      expect(Cpf.tryParse('123.456.789-09')?.digits, '12345678909');
      expect(Cpf.tryParse('  12345678909  ')?.digits, '12345678909');
    });

    test('recusa dígito verificador errado', () {
      expect(Cpf.tryParse('12345678900'), isNull);
      expect(Cpf.tryParse('98765432101'), isNull);
    });

    // Passa na aritmética do DV e é inválido por definição: a Receita nunca
    // emite CPF com todos os dígitos iguais.
    test('recusa repetição de dígito', () {
      for (final digito in ['0', '1', '9']) {
        expect(Cpf.tryParse(List.filled(11, digito).join()), isNull);
      }
    });

    test('recusa comprimento errado e lixo', () {
      expect(Cpf.tryParse('1234567890'), isNull);
      expect(Cpf.tryParse('123456789012'), isNull);
      expect(Cpf.tryParse(''), isNull);
      expect(Cpf.tryParse('abcdefghijk'), isNull);
    });

    test('formata para exibição', () {
      expect(Cpf.tryParse('12345678909')?.formatted, '123.456.789-09');
    });
  });
}
