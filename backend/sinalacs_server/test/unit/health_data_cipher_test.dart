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

  group('keyVersion é gravado, não consultado', () {
    // Fixa o comportamento REAL, para que a documentação não volte a prometer
    // uma rotação que não existe: `decrypt` ignora `value.keyVersion` e usa
    // sempre a única chave configurada no processo.
    test('a versão declarada pelo valor não escolhe chave nenhuma', () async {
      final cifrado = await cipher.encrypt('texto secreto');

      // Mesma chave, versão declarada diferente: decifra do mesmo jeito.
      final versaoOutra = EncryptedValue(
        ciphertextBase64: cifrado.ciphertextBase64,
        keyVersion: 99,
      );
      expect(await cipher.decrypt(versaoOutra), 'texto secreto');

      // Chave trocada, versão declarada preservada: NÃO decifra. É o custo de
      // trocar HEALTH_DATA_ENCRYPTION_KEY sem rotina de reescrita.
      final chaveNova = HealthDataCipher(keyHex: 'b' * 64, keyVersion: 2);
      expect(() => chaveNova.decrypt(cifrado), throwsA(anything));
    });
  });

  group('formato da chave', () {
    // Antes, `hex.length ~/ 2` truncava em silêncio e a chave malformada só
    // aparecia na primeira gravação. A validação primária é
    // `AppConfig._resolveHealthDataEncryptionKey`; esta é a rede de baixo.
    test('recusa comprimento ímpar em vez de truncar', () {
      expect(
        () => HealthDataCipher(keyHex: 'a' * 63, keyVersion: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('recusa comprimento par porém errado', () {
      expect(
        () => HealthDataCipher(keyHex: 'a' * 32, keyVersion: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('recusa caractere não-hexadecimal', () {
      expect(
        () => HealthDataCipher(keyHex: '${'a' * 63}z', keyVersion: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('aceita 64 hexadecimais em maiúsculas', () async {
      final maiusculas =
          HealthDataCipher(keyHex: '0123456789ABCDEF' * 4, keyVersion: 1);
      final minusculas =
          HealthDataCipher(keyHex: '0123456789abcdef' * 4, keyVersion: 1);
      // Mesma chave: o hex é case-insensitive, então uma decifra a outra.
      expect(
        await minusculas.decrypt(await maiusculas.encrypt('texto')),
        'texto',
      );
    });
  });
}
