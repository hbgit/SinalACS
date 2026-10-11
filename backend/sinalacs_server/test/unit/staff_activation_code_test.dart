import 'dart:math';

import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:test/test.dart';

void main() {
  test('generate devolve grupos de 4 base32 e sempre muda', () {
    final a = StaffActivationCode.generate(Random(1));
    final b = StaffActivationCode.generate(Random(2));
    expect(a, matches(RegExp(r'^([A-Z2-7]{4}-){6}[A-Z2-7]{2}$')));
    expect(a, isNot(b));
  });

  test('normalize ignora caixa, espaços e hífens', () {
    expect(StaffActivationCode.normalize(' ab cd-ef '), 'ABCDEF');
  });

  test('matches aceita o mesmo código em outra formatação e recusa o errado', () {
    final c = StaffActivationCode.generate(Random(3));
    final h = StaffActivationCode.hash(c);
    expect(StaffActivationCode.matches(c.toLowerCase().replaceAll('-', ' '), h), isTrue);
    expect(StaffActivationCode.matches('${c}X', h), isFalse);
    expect(StaffActivationCode.matches('', h), isFalse);
  });

  test('o hash não contém o código', () {
    final c = StaffActivationCode.generate(Random(4));
    expect(StaffActivationCode.hash(c), isNot(contains(StaffActivationCode.normalize(c))));
    expect(StaffActivationCode.hash(c), hasLength(64));
  });
}
