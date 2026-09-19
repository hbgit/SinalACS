import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação sobre o ORM do Serverpod.
///
/// O `Session` é recebido por chamada (não guardado no construtor), o mesmo
/// arranjo de `OrmAlertStore`: o Serverpod amarra a conexão de banco à sessão
/// da requisição.
///
/// ## O contrato de escrita deste store
///
/// **A contagem de tentativas é aplicada pelo banco, numa única instrução; a
/// política continua no serviço.** `registerFailedAttempt` não recebe o valor
/// final do contador — recebe as decisões de `InstitutionalAuthService`
/// (`restartCounter`, o limite, o instante em que o bloqueio vence) e faz a
/// aritmética dentro da própria `UPDATE`.
///
/// O motivo é o modo de falha da leitura-e-escrita: contar em Dart, a partir
/// de um valor lido numa consulta anterior, faz N requisições concorrentes
/// lerem a mesma base e todas gravarem `base + 1` — o contador avança muito
/// menos que o número de tentativas e o bloqueio pode nunca ser aplicado, ou
/// seja, o controle do achado F6 vale só para tentativas serializadas (o custo
/// do Argon2id é um freio incidental, não uma garantia). Com a soma dentro da
/// `UPDATE`, o Postgres segura o lock da linha até o fim da instrução e cada
/// tentativa enxerga o resultado da anterior: nenhuma atualização se perde.
///
/// Nenhum número de política mora aqui: `5` e `15 minutos` são de
/// `InstitutionalAuthService` e chegam como parâmetro (`maxFailedAttempts`,
/// `lockUntil`). Mesmo arranjo de `OrmOnboardingStore.consumeIfValid`, que
/// também resolve no `SET`/`WHERE` do Postgres o que o ORM não expressa — o
/// ORM não tem `UPDATE ... SET col = col + 1`.
class OrmAcsCredentialStore implements AcsCredentialStore {
  OrmAcsCredentialStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async {
    final session = _session();

    // Três consultas em vez de um JOIN escrito à mão: o ORM do Serverpod não
    // expressa junção, e a alternativa — SQL cru — passaria por fora dos
    // tipos gerados. A matrícula é única (índice `acs_enrollment_id_key`),
    // então a primeira consulta devolve no máximo uma linha.
    //
    // O caminho é `acs.enrollmentId → acs.id → users.microAreaId` e
    // `acs.id → user_credentials.userId`: é esta travessia que o teste de
    // integração prova contra Postgres, e que um store falso não alcança.
    final acs = await Acs.db.findFirstRow(
      session,
      where: (table) => table.enrollmentId.equals(enrollmentId),
    );
    if (acs == null) return null;

    // `acs.id` já é `UuidValue` (o id de `acs` É o UUID do usuário) — não há
    // string para converter aqui.
    final acsUuid = acs.id!;

    final credential = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(acsUuid),
    );
    if (credential == null) return null;

    final user = await User.db.findFirstRow(
      session,
      where: (table) => table.id.equals(acsUuid),
    );
    if (user == null) return null;

    return AcsCredentialRecord(
      acsId: acsUuid.uuid,
      microAreaId: user.microAreaId?.uuid,
      active: acs.active,
      digest: PasswordDigest(
        hashBase64: credential.passwordHash,
        saltBase64: credential.passwordSalt,
        memoryKb: credential.memoryKb,
        iterations: credential.iterations,
        parallelism: credential.parallelism,
      ),
      failedAttempts: credential.failedAttempts,
      lockedUntil: credential.lockedUntil,
    );
  }

  @override
  Future<void> registerFailedAttempt(
    String acsId, {
    required bool restartCounter,
    required int maxFailedAttempts,
    required DateTime lockUntil,
    required DateTime at,
  }) async {
    // Uma instrução, três decisões do serviço:
    //
    // - `@restart` (bloqueio anterior já vencido) recomeça a contagem em `1`;
    //   sem isso, `6 >= 5` trancaria a conta de novo a cada tentativa e uma
    //   tentativa por janela bastaria para manter um ACS fora para sempre;
    // - `"failedAttempts" + 1 >= @maxFailedAttempts` decide o bloqueio pelo
    //   contador **da linha**, e não pelo contador que o serviço leu antes — é
    //   essa diferença que faz a rajada concorrente ser contada inteira e
    //   travar no limite;
    // - `@lockUntil` é o vencimento já calculado pelo serviço
    //   (`at.add(lockDuration)`), para o store não conhecer a duração.
    //
    // O `WHERE` recusa a escrita quando a linha está bloqueada AGORA e o
    // serviço não mandou reiniciar: assim "bloqueio ativo não conta nem estende
    // tentativa" — a regra do serviço — continua valendo mesmo quando duas
    // requisições se cruzam e uma delas leu a linha antes de a outra trancá-la.
    //
    // Sem `RETURNING`: o serviço não consome o contador resultante (a falha é
    // uma recusa de qualquer forma) e quem observa o estado é o teste, lendo a
    // linha. Linha inexistente é no-op, como antes.
    //
    // `@lockUntil::timestamp` não é enfeite: dentro do `CASE` o Postgres não
    // tem contexto para inferir o tipo do parâmetro (numa atribuição ou numa
    // comparação ele infere da coluna) e o trata como `text`, que não tem
    // conversão implícita para `timestamp without time zone` — sem o cast a
    // instrução falha com "column lockedUntil is of type timestamp without time
    // zone but expression is of type text".
    await _session().db.unsafeExecute(
      '''
      UPDATE "user_credentials"
         SET "failedAttempts" = CASE WHEN @restart THEN 1
                                     ELSE "failedAttempts" + 1 END,
             "lockedUntil" = CASE
                 WHEN @restart THEN NULL
                 WHEN "failedAttempts" + 1 >= @maxFailedAttempts
                   THEN @lockUntil::timestamp
                 ELSE NULL
               END,
             "updatedAt" = @at
       WHERE "userId" = @userId::uuid
         AND ("lockedUntil" IS NULL OR "lockedUntil" <= @at OR @restart);
      ''',
      parameters: QueryParameters.named({
        'restart': restartCounter,
        'maxFailedAttempts': maxFailedAttempts,
        'lockUntil': lockUntil,
        'at': at,
        'userId': acsId,
      }),
    );
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    // Os DOIS campos: um login válido zera o contador **e** derruba o
    // bloqueio. Limpar só o contador manteria a conta trancada até
    // `lockedUntil` vencer, sem nada mais a contar; limpar só o bloqueio
    // deixaria o contador a uma falha de trancar de novo.
    //
    // Mesma forma de `registerFailedAttempt`: uma instrução, sem
    // leitura-antes-de-escrita. Aqui não há contagem a preservar (o alvo é
    // constante — zero) e por isso nem `CASE` nem `RETURNING`.
    await _session().db.unsafeExecute(
      'UPDATE "user_credentials" '
      'SET "failedAttempts" = 0, "lockedUntil" = NULL, "updatedAt" = @at '
      'WHERE "userId" = @userId::uuid;',
      parameters: QueryParameters.named({'at': at, 'userId': acsId}),
    );
  }

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {
    final session = _session();
    final userId = UuidValue.fromString(acsId);

    final existing = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(userId),
    );

    if (existing == null) {
      await UserCredential.db.insertRow(
        session,
        UserCredential(
          userId: userId,
          passwordHash: digest.hashBase64,
          passwordSalt: digest.saltBase64,
          memoryKb: digest.memoryKb,
          iterations: digest.iterations,
          parallelism: digest.parallelism,
          failedAttempts: 0,
          lockedUntil: null,
          createdAt: at,
          updatedAt: at,
        ),
      );
      return;
    }

    // Substituir a credencial também zera o estado de bloqueio: a senha nova
    // não tem relação com as tentativas da antiga, e herdar o contador faria
    // uma troca de senha nascer a uma falha do bloqueio.
    existing
      ..passwordHash = digest.hashBase64
      ..passwordSalt = digest.saltBase64
      ..memoryKb = digest.memoryKb
      ..iterations = digest.iterations
      ..parallelism = digest.parallelism
      ..failedAttempts = 0
      ..lockedUntil = null
      ..updatedAt = at;
    await UserCredential.db.updateRow(session, existing);
  }
}
