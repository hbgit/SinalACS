import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:test/test.dart';

void main() {
  late HealthDataCipher cipher;

  setUp(() {
    // 32 bytes em hex = 64 caracteres, mesmo formato de `openssl rand -hex 32`
    // usado pelos outros segredos do projeto.
    cipher = HealthDataCipher(keyHex: 'a' * 64, keyVersion: 1);
  });

  test('decifra exatamente o que foi cifrado', () async {
    const texto = 'hipertensão, diabetes tipo 2';
    final cifrado = await cipher.encrypt(texto);
    final decifrado = await cipher.decrypt(cifrado);
    expect(decifrado, texto);
  });

  test('o valor cifrado nunca contém o texto claro', () async {
    const texto = 'hipertensão, diabetes tipo 2';
    final cifrado = await cipher.encrypt(texto);
    expect(cifrado.ciphertextBase64, isNot(contains('hipertensão')));
    expect(cifrado.ciphertextBase64, isNot(contains('diabetes')));
  });

  test('duas cifragens do mesmo texto produzem ciphertexts diferentes (nonce aleatório)', () async {
    const texto = 'mesmo texto';
    final a = await cipher.encrypt(texto);
    final b = await cipher.encrypt(texto);
    expect(a.ciphertextBase64, isNot(b.ciphertextBase64));
    // mas ambos decifram para o mesmo texto
    expect(await cipher.decrypt(a), texto);
    expect(await cipher.decrypt(b), texto);
  });

  test('marca a versão de chave usada', () async {
    final cifrado = await cipher.encrypt('texto');
    expect(cifrado.keyVersion, 1);
  });

  test('recusa decifrar com a chave errada', () async {
    final cifrado = await cipher.encrypt('texto secreto');
    final outraChave = HealthDataCipher(keyHex: 'b' * 64, keyVersion: 1);
    expect(() => outraChave.decrypt(cifrado), throwsA(anything));
  });

  test('string vazia cifra e decifra normalmente', () async {
    final cifrado = await cipher.encrypt('');
    expect(await cipher.decrypt(cifrado), '');
  });
}
