import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação do `RefreshTokenStore` sobre o ORM do Serverpod.
///
/// Mesmo arranjo de `OrmAcsCredentialStore`: o `Session` vem por chamada e o
/// que o ORM não expressa de forma atômica (escrita condicional com contagem
/// de linhas) é uma única instrução SQL. Só o SHA-256 do token chega aqui; o
/// token em claro nunca é visto por este store.
/// Quando [transaction] é fornecida, todas as escritas participam dela — mesmo
/// arranjo de `OrmAlertStore`: é o que permite a desativação (#43) gravar a
/// flag do ACS e revogar os tokens na **mesma** transação, sem que este store
/// conheça o caso de uso.
class OrmRefreshTokenStore implements RefreshTokenStore {
  OrmRefreshTokenStore({
    required Session Function() session,
    Transaction? transaction,
  }) : _session = session,
       _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

  /// Uma instrução: trava as linhas da família (`FOR UPDATE`) e só insere se
  /// nenhuma delas está revogada. Se um `revokeFamily` concorrente já travou a
  /// linha, o `FOR UPDATE` espera, relê a linha já revogada e recusa — não há
  /// janela entre "checar" e "inserir" em que a revogação passe despercebida.
  @override
  Future<bool> insert(RefreshTokenRecord record, String tokenHash) async {
    final linhas = await _session().db.unsafeExecute(
      '''
      WITH familia AS (
        SELECT "revokedAt" FROM "acs_refresh_tokens"
         WHERE "familyId" = @familyId::uuid
           FOR UPDATE
      )
      INSERT INTO "acs_refresh_tokens"
        ("id", "userId", "familyId", "tokenHash", "deviceId", "issuedAt",
         "idleExpiresAt", "absoluteExpiresAt", "rotatedAt", "revokedAt")
      SELECT @id::uuid, @userId::uuid, @familyId::uuid, @tokenHash::text,
             @deviceId::text, @issuedAt::timestamp, @idleExpiresAt::timestamp,
             @absoluteExpiresAt::timestamp, NULL, NULL
       WHERE NOT EXISTS (SELECT 1 FROM familia WHERE "revokedAt" IS NOT NULL);
      ''',
      parameters: QueryParameters.named({
        'id': record.id,
        'userId': record.userId,
        'familyId': record.familyId,
        'tokenHash': tokenHash,
        'deviceId': record.deviceId,
        'issuedAt': record.issuedAt,
        'idleExpiresAt': record.idleExpiresAt,
        'absoluteExpiresAt': record.absoluteExpiresAt,
      }),
      transaction: _transaction,
    );
    return linhas == 1;
  }

  @override
  Future<RefreshTokenRecord?> findByHash(String tokenHash) async {
    final row = await AcsRefreshToken.db.findFirstRow(
      _session(),
      where: (t) => t.tokenHash.equals(tokenHash),
      transaction: _transaction,
    );
    if (row == null) return null;
    return RefreshTokenRecord(
      id: row.id!.uuid,
      userId: row.userId.uuid,
      familyId: row.familyId.uuid,
      deviceId: row.deviceId,
      issuedAt: row.issuedAt,
      idleExpiresAt: row.idleExpiresAt,
      absoluteExpiresAt: row.absoluteExpiresAt,
      rotatedAt: row.rotatedAt,
      revokedAt: row.revokedAt,
    );
  }

  @override
  Future<bool> markRotated(String id, DateTime at) async {
    final linhas = await _session().db.unsafeExecute(
      'UPDATE "acs_refresh_tokens" SET "rotatedAt" = @at '
      'WHERE "id" = @id::uuid AND "rotatedAt" IS NULL AND "revokedAt" IS NULL;',
      parameters: QueryParameters.named({'at': at, 'id': id}),
      transaction: _transaction,
    );
    return linhas == 1;
  }

  /// Duas passadas, de propósito. Sob READ COMMITTED a `UPDATE` enxerga só as
  /// linhas do seu instantâneo: um `insert` concorrente que travou a família
  /// primeiro e confirmou depois do início desta instrução cria um filho que
  /// a primeira passada não vê. A segunda passada, com instantâneo novo, o
  /// alcança — sem ela, o filho ficaria vigente depois da revogação. (O
  /// inverso, `insert` depois da revogação, é barrado pelo próprio `insert`.)
  @override
  Future<void> revokeFamily(String familyId, DateTime at) async {
    for (var passada = 0; passada < 2; passada++) {
      await _session().db.unsafeExecute(
        'UPDATE "acs_refresh_tokens" SET "revokedAt" = @at '
        'WHERE "familyId" = @familyId::uuid AND "revokedAt" IS NULL;',
        parameters: QueryParameters.named({'at': at, 'familyId': familyId}),
        transaction: _transaction,
      );
    }
  }

  /// Todas as famílias do usuário — a desativação da conta (#43); o `logout`
  /// continua revogando só a própria família.
  ///
  /// Uma instrução só, e não as duas passadas de [revokeFamily]: aqui a
  /// revogação não depende de alcançar um filho inserido depois dela, porque
  /// quem impede um filho novo é o próprio `insert` (recusa a família revogada)
  /// e a emissão de família nova exige um login, que a conta inativa já barra.
  @override
  Future<void> revokeAllForUser(String userId, DateTime at) async {
    await _session().db.unsafeExecute(
      'UPDATE "acs_refresh_tokens" SET "revokedAt" = @at '
      'WHERE "userId" = @userId::uuid AND "revokedAt" IS NULL;',
      parameters: QueryParameters.named({'at': at, 'userId': userId}),
      transaction: _transaction,
    );
  }

  /// Só devolve conta de um ACS: o serviço fixa o papel ACS na renovação, então
  /// um usuário sem linha em `acs` (paciente, por exemplo) não pode renovar.
  @override
  Future<RefreshAccount?> findAccount(String userId) async {
    final session = _session();
    final id = UuidValue.fromString(userId);
    final acs = await Acs.db.findFirstRow(
      session,
      where: (t) => t.id.equals(id),
      transaction: _transaction,
    );
    if (acs == null) return null;
    final user = await User.db.findFirstRow(
      session,
      where: (t) => t.id.equals(id),
      transaction: _transaction,
    );
    if (user == null) return null;
    return RefreshAccount(active: acs.active, microAreaId: user.microAreaId?.uuid);
  }

  @override
  Future<void> deleteExpiredFor(String userId, DateTime before) async {
    await AcsRefreshToken.db.deleteWhere(
      _session(),
      where: (t) =>
          t.userId.equals(UuidValue.fromString(userId)) &
          (t.absoluteExpiresAt < before),
      transaction: _transaction,
    );
  }
}
