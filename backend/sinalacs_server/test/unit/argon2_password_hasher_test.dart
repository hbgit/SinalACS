import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

void main() {
  // Parâmetros reduzidos para o teste não gastar ~19 MB e ~80 ms por
  // derivação: o que se prova aqui é o CONTRATO (salt por credencial,
  // verificação correta, parâmetros gravados junto do hash), não o custo, que
  // é uma constante declarada em Argon2PasswordHasher.recommended.
  final hasher = Argon2PasswordHasher(
    memoryKb: 512,
    iterations: 1,
    parallelism: 1,
  );

  test('aceita a senha correta', () async {
    final digest = await hasher.derive('senha-sintetica-de-teste');
    expect(await hasher.matches('senha-sintetica-de-teste', digest), isTrue);
  });

  test('recusa senha errada sem lançar', () async {
    final digest = await hasher.derive('senha-sintetica-de-teste');
    expect(await hasher.matches('outra-senha', digest), isFalse);
  });

  test('dois hashes da MESMA senha diferem (salt por credencial)', () async {
    final primeiro = await hasher.derive('senha-sintetica-de-teste');
    final segundo = await hasher.derive('senha-sintetica-de-teste');

    expect(primeiro.saltBase64, isNot(segundo.saltBase64));
    expect(primeiro.hashBase64, isNot(segundo.hashBase64));
  });

  test('grava os parâmetros que produziram o hash', () async {
    final digest = await hasher.derive('senha-sintetica-de-teste');

    // São eles que permitem subir o custo no futuro sem invalidar as
    // credenciais antigas: a verificação usa o que está gravado na linha, não
    // o que a configuração do processo diz hoje.
    expect(digest.memoryKb, 512);
    expect(digest.iterations, 1);
    expect(digest.parallelism, 1);
  });

  test('verifica com os parâmetros DA LINHA, não com os do processo', () async {
    final antigo = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);
    final digest = await antigo.derive('senha-sintetica-de-teste');

    // Um processo configurado com custo maior precisa continuar aceitando a
    // credencial gravada com o custo antigo — senão toda troca de parâmetro
    // tranca todos os ACS fora.
    final novo = Argon2PasswordHasher(memoryKb: 4096, iterations: 2, parallelism: 1);
    expect(await novo.matches('senha-sintetica-de-teste', digest), isTrue);
  });

  test('salt curto demais é recusado em vez de silenciosamente aceito', () async {
    const invalido = PasswordDigest(
      hashBase64: 'AAAA',
      saltBase64: '',
      memoryKb: 512,
      iterations: 1,
      parallelism: 1,
    );
    await expectLater(
      hasher.matches('qualquer', invalido),
      throwsA(isA<ArgumentError>()),
    );
  });
}
