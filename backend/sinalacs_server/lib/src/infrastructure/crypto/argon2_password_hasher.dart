import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';

/// Argon2id sobre `package:cryptography` — a mesma dependência que
/// `HealthDataCipher` já usa para AES-256-GCM, então verificação de senha não
/// acrescenta pacote nenhum ao backend.
///
/// Argon2id (e não PBKDF2) porque é resistente a ataque com GPU/ASIC: o custo
/// de memória é o que encarece a força bruta, e é justamente o que falta no
/// PBKDF2. `scrypt` também serviria; o pacote já instalado só oferece Argon2id
/// e PBKDF2, e entre os dois a escolha é Argon2id.
class Argon2PasswordHasher implements PasswordHasher {
  const Argon2PasswordHasher({
    this.memoryKb = recommendedMemoryKb,
    this.iterations = recommendedIterations,
    this.parallelism = recommendedParallelism,
  });

  /// 19 MiB × 2 iterações × 1 via — o piso recomendado pela OWASP para
  /// Argon2id. Não é um número medido nesta máquina: é o ponto de partida
  /// documentado, e subir é uma mudança de constante (as credenciais antigas
  /// continuam verificando, porque os parâmetros vivem na linha).
  static const recommendedMemoryKb = 19456;
  static const recommendedIterations = 2;
  static const recommendedParallelism = 1;

  /// Comprimento do hash derivado, em bytes. **Não** viaja em [PasswordDigest],
  /// ao contrário dos parâmetros de custo: `matches` decodifica o que estiver
  /// gravado e compara com o que `_derive` produz aqui, então mudar este número
  /// faz toda credencial existente verificar como senha errada — e "senha
  /// errada" conta tentativa e bloqueia a conta. Subir o custo é troca de
  /// constante; mexer aqui é migração de credencial.
  static const _hashLength = 32;
  static const _saltLength = 16;

  /// Salt curto demais não protege contra rainbow table nem contra
  /// pré-computação entre credenciais. Recusar em vez de aceitar é o mesmo
  /// raciocínio de `HealthDataCipher._hexToBytes`.
  static const _minSaltLength = 8;

  final int memoryKb;
  final int iterations;
  final int parallelism;

  @override
  Future<PasswordDigest> derive(String password) async {
    final salt = _randomBytes(_saltLength);
    final hash = await _derive(password, salt, memoryKb: memoryKb, iterations: iterations, parallelism: parallelism);

    return PasswordDigest(
      hashBase64: base64.encode(hash),
      saltBase64: base64.encode(salt),
      memoryKb: memoryKb,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  @override
  Future<bool> matches(String password, PasswordDigest digest) async {
    final salt = base64.decode(digest.saltBase64);
    if (salt.length < _minSaltLength) {
      throw ArgumentError.value(
        salt.length,
        'digest.saltBase64',
        'salt precisa ter ao menos $_minSaltLength bytes',
      );
    }

    // Os parâmetros vêm DO DIGEST, nunca dos campos desta instância: é o que
    // permite aumentar o custo sem invalidar credencial antiga.
    final expected = base64.decode(digest.hashBase64);
    final actual = await _derive(
      password,
      salt,
      memoryKb: digest.memoryKb,
      iterations: digest.iterations,
      parallelism: digest.parallelism,
    );

    return _constantTimeEquals(expected, actual);
  }

  Future<Uint8List> _derive(
    String password,
    List<int> salt, {
    required int memoryKb,
    required int iterations,
    required int parallelism,
  }) async {
    final algorithm = Argon2id(
      parallelism: parallelism,
      memory: memoryKb,
      iterations: iterations,
      hashLength: _hashLength,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Comparação sem early-return: o tempo não pode depender de quantos bytes
  /// iniciais batem. Mesmo formato de `DevelopmentAuthService._matchesSignature`.
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a[index] ^ b[index];
    }
    return difference == 0;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var index = 0; index < length; index++) {
      bytes[index] = random.nextInt(256);
    }
    return bytes;
  }
}
