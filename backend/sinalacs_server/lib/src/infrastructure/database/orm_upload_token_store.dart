import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/application/auth/upload_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/subject_lock.dart';

/// Implementação do `UploadTokenStore` sobre o ORM do Serverpod.
///
/// Mesmo arranjo de `OrmRefreshTokenStore`: o `Session` vem por chamada e só o
/// SHA-256 do token chega aqui — o token em claro nunca é visto por este store.
class OrmUploadTokenStore implements UploadTokenStore {
  OrmUploadTokenStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  /// Revoga o vigente do par e insere o novo numa transação serializada por
  /// (usuário, aparelho) com advisory lock: dois logins concorrentes do mesmo
  /// aparelho não deixam dois tokens vigentes (sob READ COMMITTED, o `UPDATE`
  /// de um não enxergaria a linha que o outro acabou de inserir).
  @override
  Future<void> replace(UploadTokenRecord record, String tokenHash) async {
    final session = _session();
    await session.db.transaction((transaction) async {
      await lockPerSubject(
        session,
        transaction,
        namespace: lockNamespaceUploadToken,
        key: '${record.userId}|${record.deviceId}',
      );
      await session.db.unsafeExecute(
        'UPDATE "acs_upload_tokens" SET "revokedAt" = @at '
        'WHERE "userId" = @userId::uuid AND "deviceId" = @deviceId::text '
        'AND "revokedAt" IS NULL;',
        parameters: QueryParameters.named({
          'at': record.issuedAt,
          'userId': record.userId,
          'deviceId': record.deviceId,
        }),
        transaction: transaction,
      );
      await AcsUploadToken.db.insertRow(
        session,
        AcsUploadToken(
          id: UuidValue.fromString(record.id),
          userId: UuidValue.fromString(record.userId),
          tokenHash: tokenHash,
          deviceId: record.deviceId,
          issuedAt: record.issuedAt,
          expiresAt: record.expiresAt,
        ),
        transaction: transaction,
      );
    });
  }

  @override
  Future<UploadTokenRecord?> findByHash(String tokenHash) async {
    final row = await AcsUploadToken.db.findFirstRow(
      _session(),
      where: (t) => t.tokenHash.equals(tokenHash),
    );
    if (row == null) return null;
    return UploadTokenRecord(
      id: row.id!.uuid,
      userId: row.userId.uuid,
      deviceId: row.deviceId,
      issuedAt: row.issuedAt,
      expiresAt: row.expiresAt,
      revokedAt: row.revokedAt,
    );
  }

  @override
  Future<void> revoke(String id, DateTime at) async {
    await _session().db.unsafeExecute(
      'UPDATE "acs_upload_tokens" SET "revokedAt" = @at '
      'WHERE "id" = @id::uuid AND "revokedAt" IS NULL;',
      parameters: QueryParameters.named({'at': at, 'id': id}),
    );
  }

  /// Só conta de ACS (mesma regra de `OrmRefreshTokenStore.findAccount`): um
  /// usuário sem linha em `acs` nunca resolve um token de envio.
  @override
  Future<RefreshAccount?> findAccount(String userId) async {
    final session = _session();
    final id = UuidValue.fromString(userId);
    final acs = await Acs.db.findFirstRow(session, where: (t) => t.id.equals(id));
    if (acs == null) return null;
    final user = await User.db.findFirstRow(session, where: (t) => t.id.equals(id));
    if (user == null) return null;
    return RefreshAccount(active: acs.active, microAreaId: user.microAreaId?.uuid);
  }

  @override
  Future<void> deleteExpiredFor(String userId, DateTime before) async {
    await AcsUploadToken.db.deleteWhere(
      _session(),
      where: (t) =>
          t.userId.equals(UuidValue.fromString(userId)) & (t.expiresAt < before),
    );
  }
}
