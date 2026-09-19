import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:test/test.dart';

void main() {
  final cpf = Cpf.tryParse('12345678909')!;

  test('é determinístico: o mesmo CPF e o mesmo pepper dão o mesmo hash', () {
    final a = HmacCpfHasher(pepper: 'pepper-de-teste');
    final b = HmacCpfHasher(pepper: 'pepper-de-teste');

    expect(a.hash(cpf), b.hash(cpf));
  });

  test('pepper diferente produz hash diferente', () {
    final a = HmacCpfHasher(pepper: 'pepper-de-teste');
    final b = HmacCpfHasher(pepper: 'outro-pepper');

    expect(a.hash(cpf), isNot(b.hash(cpf)));
  });

  test('o hash não contém o CPF', () {
    final hash = HmacCpfHasher(pepper: 'pepper-de-teste').hash(cpf);

    expect(hash.contains(cpf.digits), isFalse);
    expect(hash.length, 64, reason: 'hex de 32 bytes');
  });

  // Campo de domínio: sem ele, `hashOtpCode('12345678909')` seria idêntico a
  // `hash(cpf)` do mesmo valor, e um hash de uma finalidade valeria na outra.
  test('o domínio separa CPF de código OTP', () {
    final hasher = HmacCpfHasher(pepper: 'pepper-de-teste');

    expect(hasher.hashOtpCode(cpf.digits), isNot(hasher.hash(cpf)));
  });

  test('recusa pepper vazio', () {
    expect(() => HmacCpfHasher(pepper: ''), throwsA(isA<ArgumentError>()));
    expect(() => HmacCpfHasher(pepper: '   '), throwsA(isA<ArgumentError>()));
  });
}
