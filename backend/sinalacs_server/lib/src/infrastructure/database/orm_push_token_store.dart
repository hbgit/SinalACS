import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/push_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/subject_lock.dart';

/// Implementação de [PushTokenStore] sobre o ORM do Serverpod.
class OrmPushTokenStore implements PushTokenStore {
  OrmPushTokenStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<bool> hasGrantedConsent(String userId) async {
    final row = await ConsentLog.db.findFirstRow(
      _session(),
      where: (t) =>
          t.userId.equals(UuidValue.fromString(userId)) &
          t.purpose.equals(ConsentPurpose.segmentedPush.name),
      orderBy: (t) => t.timestamp,
      orderDescending: true,
    );
    return row != null && row.action == 'granted';
  }

  /// Serializa por token com advisory lock: o índice único de `token` recusaria
  /// o segundo inserto de uma corrida, e aqui o segundo deve virar atualização.
  @override
  Future<void> upsert({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    final session = _session();
    final userUuid = UuidValue.fromString(userId);
    final areaUuid = microAreaId == null ? null : UuidValue.fromString(microAreaId);
    await session.db.transaction((transaction) async {
      await lockPerSubject(session, transaction, namespace: lockNamespacePushToken, key: token);
      final existing = await PushToken.db.findFirstRow(
        session,
        where: (t) => t.token.equals(token),
        transaction: transaction,
      );
      if (existing != null) {
        await PushToken.db.updateRow(
          session,
          existing.copyWith(
            userId: userUuid,
            microAreaId: areaUuid,
            platform: platform,
            updatedAt: now,
          ),
          transaction: transaction,
        );
        return;
      }
      await PushToken.db.insertRow(
        session,
        PushToken(
          userId: userUuid,
          microAreaId: areaUuid,
          token: token,
          platform: platform,
          createdAt: now,
          updatedAt: now,
        ),
        transaction: transaction,
      );
    });
  }

  @override
  Future<int> deleteAllFor(String userId) async {
    final removed = await PushToken.db.deleteWhere(
      _session(),
      where: (t) => t.userId.equals(UuidValue.fromString(userId)),
    );
    return removed.length;
  }
}
