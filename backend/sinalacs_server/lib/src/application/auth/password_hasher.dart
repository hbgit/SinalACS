/// Um hash de senha e os parâmetros que o produziram.
///
/// Os parâmetros viajam com o hash de propósito. Argon2id é caro por desenho, e
/// o custo recomendado sobe a cada ano; se a verificação usasse os parâmetros
/// da configuração do processo em vez dos gravados na linha, subir o custo
/// invalidaria toda credencial existente de uma vez — todos os ACS trancados
/// fora num deploy.
class PasswordDigest {
  const PasswordDigest({
    required this.hashBase64,
    required this.saltBase64,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
  });

  final String hashBase64;
  final String saltBase64;

  /// Custo de memória em blocos de 1 kB (o `memory` do Argon2id).
  final int memoryKb;
  final int iterations;
  final int parallelism;
}

/// Derivação e verificação de senha.
///
/// Interface em `application/`, implementação em `infrastructure/` — mesmo
/// arranjo de `AlertStore`/`OrmAlertStore` (ver `backend/CLAUDE.md`). O serviço
/// de login decide *quando* verificar; a derivação em si é detalhe de
/// infraestrutura.
abstract interface class PasswordHasher {
  Future<PasswordDigest> derive(String password);

  /// `false` para senha errada. **Não lança** para credencial inválida: quem
  /// chama precisa distinguir "não confere" (conta com tentativa contada) de
  /// "a linha está corrompida" (erro de servidor), e uma exceção para o
  /// primeiro caso apagaria essa diferença.
  Future<bool> matches(String password, PasswordDigest digest);
}
