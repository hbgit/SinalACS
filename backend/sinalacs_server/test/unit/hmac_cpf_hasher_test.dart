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

  // O LITERAL do domínio, e não só a separação entre os dois: `sinalacs:cpf:v1:`
  // e `sinalacs:otp:v1:` são as constantes privadas `_cpfDomain`/`_otpDomain`.
  //
  // Trocar `v1` por `v2` — a manutenção que o `:v1:` existe para permitir —
  // invalida TODO `users.cpfHash` já gravado, do mesmo jeito e com a mesma
  // consequência que `CPF_HASH_PEPPER` tem: nenhum CPF cadastrado é encontrado
  // no login, e o banco não acusa nada. O `.env.example` documenta essa
  // armadilha para o pepper e não a documentava aqui; sem um valor preso, a
  // troca atravessava a suíte inteira verde, porque o teste acima compara os
  // dois hashes ENTRE SI e acompanha qualquer prefixo.
  //
  // Os dois hex abaixo são o HMAC-SHA-256 de `'pepper-de-teste'` sobre
  // `sinalacs:cpf:v1:12345678909` e `sinalacs:otp:v1:123456`. Eles prendem o
  // texto inteiro da mensagem — prefixo, separador e valor —, então mudam se o
  // prefixo mudar. Falha aqui significa que o valor dos hashes gravados mudou
  // de significado: é migração de dados, não edição de teste.
  test('o prefixo do domínio é literal, e mexer nele invalida o que está gravado',
      () {
    final hasher = HmacCpfHasher(pepper: 'pepper-de-teste');

    expect(
      hasher.hash(cpf),
      'e82e61fb1c576bdd9e9833751f429c3dd75007057631e4789135fb80beacd976',
    );
    expect(
      hasher.hashOtpCode('123456'),
      '8da2e4761720a0643a2eccf518e56802b7fb57de7c48be7cdbb5ef75e6015ed8',
    );
  });

  test('recusa pepper vazio', () {
    expect(() => HmacCpfHasher(pepper: ''), throwsA(isA<ArgumentError>()));
    expect(() => HmacCpfHasher(pepper: '   '), throwsA(isA<ArgumentError>()));
  });
}
