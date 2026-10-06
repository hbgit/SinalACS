import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
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
class OrmAcsCredentialStore implements AcsCredentialStore, TotpStore {
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
      lockStreak: credential.lockStreak,
      totp: _totpOf(credential),
    );
  }

  /// Estado da MFA como está na linha. Segredo sem versão de chave é linha
  /// corrompida: vira erro de servidor, não "sem MFA" — tratar como ausente
  /// deixaria entrar só com a senha quem tem MFA ativa.
  static TotpEnrollment? _totpOf(UserCredential credential) {
    final cifrado = credential.totpSecretEncrypted;
    if (cifrado == null) return null;
    final versao = credential.totpKeyVersion;
    if (versao == null) {
      throw StateError('Segredo TOTP sem versão de chave em user_credentials.');
    }
    return TotpEnrollment(
      sealed: SealedSecret(ciphertextBase64: cifrado, keyVersion: versao),
      enabled: credential.totpEnabledAt != null,
      lastStep: credential.totpLastStep,
    );
  }

  /// Grava um segredo **pendente**: zera `totpEnabledAt` e `totpLastStep`, de
  /// modo que a MFA só passa a valer com `enable`. O `WHERE totpEnabledAt IS
  /// NULL` recusa sobrescrever uma MFA já ativa mesmo quando o serviço leu a
  /// linha antes de uma confirmação concorrente gravar: sem ele, quem só tem a
  /// senha poderia trocar o segredo de uma MFA recém-ativada.
  @override
  Future<bool> saveSecret(String acsId, SealedSecret secret, DateTime at) async {
    final linhas = await UserCredential.db.updateWhere(
      _session(),
      columnValues: (t) => [
        t.totpSecretEncrypted(secret.ciphertextBase64),
        t.totpKeyVersion(secret.keyVersion),
        t.totpEnabledAt(null),
        t.totpLastStep(null),
        t.updatedAt(at),
      ],
      where: (t) => t.userId.equals(UuidValue.fromString(acsId)) & t.totpEnabledAt.equals(null),
    );
    return linhas.isNotEmpty;
  }

  /// Ativa só se a linha ainda está pendente **com o mesmo segredo** que o
  /// código conferiu: duas confirmações concorrentes ativam uma vez só, e um
  /// novo início no meio (segredo trocado) não é ativado por um código do
  /// segredo antigo.
  @override
  Future<bool> enable(String acsId, SealedSecret pending, int step, DateTime at) async {
    final linhas = await UserCredential.db.updateWhere(
      _session(),
      columnValues: (t) => [t.totpEnabledAt(at), t.totpLastStep(step), t.updatedAt(at)],
      where: (t) =>
          t.userId.equals(UuidValue.fromString(acsId)) &
          t.totpEnabledAt.equals(null) &
          t.totpSecretEncrypted.equals(pending.ciphertextBase64),
    );
    return linhas.isNotEmpty;
  }

  /// Grava o passo aceito e diz se gravou. O `WHERE` só deixa o passo
  /// **avançar**; sob READ COMMITTED, a segunda de duas requisições com o
  /// mesmo código espera o lock da linha, reavalia o `WHERE` contra o passo
  /// que a primeira gravou e não altera nada — devolve `false`, e o serviço
  /// recusa a sessão (replay).
  @override
  Future<bool> registerStep(String acsId, int step) async {
    final linhas = await UserCredential.db.updateWhere(
      _session(),
      columnValues: (t) => [t.totpLastStep(step)],
      where: (t) =>
          t.userId.equals(UuidValue.fromString(acsId)) &
          (t.totpLastStep.equals(null) | (t.totpLastStep < step)),
    );
    return linhas.isNotEmpty;
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
    // O `WHERE` recusa a escrita enquanto a linha está bloqueada AGORA: assim
    // "bloqueio ativo não conta nem estende tentativa" — a regra do serviço —
    // continua valendo mesmo quando duas requisições se cruzam e uma delas leu
    // a linha antes de a outra trancá-la. O reinício do contador não precisa de
    // cláusula própria aqui: bloqueio vencido já satisfaz `"lockedUntil" <= @at`,
    // então a escrita acontece; e se, entre a leitura do serviço e esta UPDATE,
    // outra requisição re-trancar a conta, a escrita é recusada — um leitor
    // atrasado não derruba um bloqueio recém-aplicado.
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
             -- A escalada sobe só quando o bloqueio é APLICADO nesta escrita; o
             -- reinício do contador (bloqueio vencido) a preserva. Como o `WHERE`
             -- recusa a linha já bloqueada, uma rajada concorrente sobe uma vez.
             "lockStreak" = CASE
                 WHEN @restart THEN "lockStreak"
                 WHEN "failedAttempts" + 1 >= @maxFailedAttempts THEN "lockStreak" + 1
                 ELSE "lockStreak"
               END,
             "updatedAt" = @at
       WHERE "userId" = @userId::uuid
         AND ("lockedUntil" IS NULL OR "lockedUntil" <= @at);
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
      'SET "failedAttempts" = 0, "lockedUntil" = NULL, "lockStreak" = 0, "updatedAt" = @at '
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
