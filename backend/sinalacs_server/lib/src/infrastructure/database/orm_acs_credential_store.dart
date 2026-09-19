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
/// **O store grava exatamente o que recebe; a política é do serviço.** Nenhum
/// método aqui decide quantas tentativas valem, nem por quanto tempo bloquear:
/// `registerFailedAttempt` persiste os dois valores que vieram, inclusive
/// quando o número é MENOR que o da linha.
///
/// Isso é deliberado, e o caso que o torna visível é a linha com
/// `lockedUntil` **no passado** e `failedAttempts` **abaixo do limite**: ela não
/// é produzida pelo serviço (o bloqueio só é gravado junto de
/// `attempts >= maxFailedAttempts`), mas é alcançável por um seed ou por uma
/// escrita manual no ORM. Quando o serviço encontra essa linha, ele conta a
/// falha como `1` — o bloqueio venceu, então o contador recomeça (ver
/// `lockedUntil` vencido em `InstitutionalAuthService.login`) — e gravar esse
/// `1` seria **baixar** o contador da linha.
///
/// A decisão é deixar a gravação acontecer: um store que "corrigisse" o valor
/// para não baixar o contador estaria decidindo política por conta própria e
/// escondendo do serviço o que ele pediu para gravar — a camada errada para
/// essa regra, e o oposto do arranjo de `application/` ✕ `infrastructure/` do
/// repositório. Quem tem de nunca passar um contador rebaixado para uma linha
/// ainda bloqueada é o serviço, que é quem conhece o limite e a duração.
class OrmAcsCredentialStore implements AcsCredentialStore {
  OrmAcsCredentialStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async {
    final session = _session();

    // Duas consultas em vez de um JOIN escrito à mão: o ORM do Serverpod não
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
    required int failedAttempts,
    required DateTime? lockedUntil,
  }) async {
    final session = _session();
    final credential = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(UuidValue.fromString(acsId)),
    );
    if (credential == null) return;

    credential.failedAttempts = failedAttempts;
    credential.lockedUntil = lockedUntil;
    credential.updatedAt = DateTime.now().toUtc();
    await UserCredential.db.updateRow(session, credential);
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    final session = _session();
    final credential = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(UuidValue.fromString(acsId)),
    );
    if (credential == null) return;

    // Os DOIS campos: um login válido zera o contador **e** derruba o
    // bloqueio. Limpar só o contador manteria a conta trancada até
    // `lockedUntil` vencer, sem nada mais a contar; limpar só o bloqueio
    // deixaria o contador a uma falha de trancar de novo.
    credential.failedAttempts = 0;
    credential.lockedUntil = null;
    credential.updatedAt = at;
    await UserCredential.db.updateRow(session, credential);
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
