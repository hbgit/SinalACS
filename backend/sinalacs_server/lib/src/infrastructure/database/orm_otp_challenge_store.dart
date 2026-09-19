import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [OtpChallengeStore] sobre o ORM do Serverpod (RF01).
///
/// É a fronteira entre o login (`application/`) e as tabelas `users` /
/// `otp_challenges`, e é onde vivem as quatro semânticas que a interface não
/// declara — cada uma presa por uma asserção contra o Postgres em
/// `test/integration/passwordless_login_test.dart`, porque o store falso do
/// teste unitário concorda com quem o escreveu e não as alcança:
///
/// 1. [save] **ignora o `id` recebido** e deixa o banco atribuir o seu. O
///    serviço manda `id: ''` (o id é do banco — ver a doc de
///    [OtpChallengeStore.save]); honrar esse valor não compila um uuid válido,
///    e é o INSERT que falha, alto, em vez de gravar uma linha sem id.
/// 2. [latestOpen] filtra `consumedAt IS NULL AND expiresAt > at` e ordena por
///    `createdAt` desc — uso único, TTL e "o mais recente" em uma consulta só.
/// 3. [registerAttempt] grava a contagem **absoluta**, nunca `attempts + 1`: o
///    serviço manda o número já calculado.
/// 4. [consume] grava o instante do primeiro consumo e **não o reescreve** numa
///    chamada seguinte — consumo não se desfaz nem se re-data.
class OrmOtpChallengeStore implements OtpChallengeStore {
  OrmOtpChallengeStore({required Session Function() session})
      : _session = session;

  final Session Function() _session;

  /// `users.cpfHash` é índice único, e é por ele que o login acha o paciente —
  /// o CPF em claro nunca chega ao banco (LGPD).
  ///
  /// `microAreaId` sai daqui junto porque é o território que vai para o token
  /// do paciente (INV-01): ler a microárea em outro lugar seria uma segunda
  /// consulta com a chance de responder por outro usuário.
  @override
  Future<PatientCredentialRecord?> findByCpfHash(String cpfHash) async {
    final session = _session();
    final user = await User.db.findFirstRow(
      session,
      where: (table) => table.cpfHash.equals(cpfHash),
    );
    if (user == null) return null;

    return PatientCredentialRecord(
      userId: user.id!.uuid,
      birthDate: user.birthDate,
      microAreaId: user.microAreaId?.uuid,
    );
  }

  /// Insere **sem passar `id`**: a coluna é `uuid NOT NULL DEFAULT
  /// gen_random_uuid()`, e é o dono da coluna que gera a chave (semântica 1).
  ///
  /// `consumedAt` nasce `null` por construção: um desafio novo não pode nascer
  /// consumido, mesmo que quem chame mande um valor.
  @override
  Future<void> save(OtpChallengeRecord challenge) async {
    final session = _session();
    await OtpChallenge.db.insertRow(
      session,
      OtpChallenge(
        userId: UuidValue.fromString(challenge.userId),
        codeHash: challenge.codeHash,
        attempts: challenge.attempts,
        createdAt: challenge.createdAt,
        expiresAt: challenge.expiresAt,
        consumedAt: null,
      ),
    );
  }

  /// Semântica 2. `equals(null)` vira `IS NULL` no ORM (não `= NULL`, que
  /// nunca casaria): os dois filtros são o coração do uso único e do TTL.
  ///
  /// A ordenação por `createdAt` desc é o que faz "o código que vale" ser o
  /// último pedido — o serviço usa o id devolvido aqui para
  /// [registerAttempt] e [consume], então uma ordem errada gastaria tentativa
  /// e consumiria a linha errada.
  @override
  Future<OtpChallengeRecord?> latestOpen(String userId, DateTime at) async {
    final session = _session();
    final row = await OtpChallenge.db.findFirstRow(
      session,
      where: (table) =>
          table.userId.equals(UuidValue.fromString(userId)) &
          table.consumedAt.equals(null) &
          // O operador de comparação do Serverpod 3 é o próprio `>` (`>` vira
          // `expiresAt > at` no SQL). A borda fica aberta de propósito:
          // `expiresAt == at` JÁ está expirado, a mesma comparação que o
          // serviço repete em `verifyOtp`.
          (table.expiresAt > at),
      orderBy: (table) => table.createdAt,
      orderDescending: true,
    );
    return row == null ? null : _toRecord(row);
  }

  /// Semântica 3: escrita **absoluta** do valor recebido. Um `UPDATE attempts =
  /// attempts + 1` aqui somaria de novo o que o serviço já somou, e o teto de
  /// [PasswordlessAuthService.maxAttempts] dispararia na metade das
  /// tentativas.
  @override
  Future<void> registerAttempt(String challengeId, int attempts) async {
    final session = _session();
    final row = await OtpChallenge.db.findById(
      session,
      _challengeId(challengeId),
    );
    if (row == null) return;
    row.attempts = attempts;
    await OtpChallenge.db.updateRow(session, row);
  }

  /// Semântica 4: **o primeiro consumo é o que vale**.
  ///
  /// A linha já consumida é devolvida sem tocar em `consumedAt`. Duas
  /// consequências, as duas deliberadas: o instante gravado é o do consumo
  /// real (não o da última chamada, que reescreveria a trilha de quando o
  /// código morreu), e uma segunda chamada não tem como "desfazer" o consumo
  /// devolvendo o desafio à vida.
  ///
  /// Isto **não** é a defesa contra duas verificações simultâneas do mesmo
  /// código: o `Future<void>` da interface não tem como dizer a quem chama
  /// "outro chegou primeiro", e a guarda de concorrência de verdade seria um
  /// `UPDATE ... WHERE consumedAt IS NULL RETURNING` que devolvesse a linha
  /// afetada. O uso único é sustentado pelo filtro de [latestOpen] mais a
  /// repetição da checagem no serviço.
  @override
  Future<void> consume(String challengeId, DateTime at) async {
    final session = _session();
    final row = await OtpChallenge.db.findById(
      session,
      _challengeId(challengeId),
    );
    if (row == null || row.consumedAt != null) return;
    row.consumedAt = at;
    await OtpChallenge.db.updateRow(session, row);
  }

  /// O id que chega aqui veio de [latestOpen] — ou seja, do banco. Um id
  /// inválido é defeito de quem chamou, não entrada de usuário, e falhar alto
  /// é melhor do que um `return` silencioso que deixaria o desafio aberto.
  UuidValue _challengeId(String challengeId) =>
      UuidValue.fromString(challengeId);

  OtpChallengeRecord _toRecord(OtpChallenge row) => OtpChallengeRecord(
        id: row.id!.uuid,
        userId: row.userId.uuid,
        codeHash: row.codeHash,
        attempts: row.attempts,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        consumedAt: row.consumedAt,
      );
}
