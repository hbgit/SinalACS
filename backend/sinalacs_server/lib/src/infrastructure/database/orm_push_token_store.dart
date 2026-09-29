import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/push_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/subject_lock.dart';

/// Implementação de [PushTokenStore] sobre o ORM do Serverpod.
class OrmPushTokenStore implements PushTokenStore {
  OrmPushTokenStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  /// Duas travas, sempre nesta ordem: por titular (fecha a janela entre ler o
  /// consentimento e gravar, contra a revogação) e depois por token (o índice
  /// único recusaria o segundo inserto de uma corrida, e aqui o segundo deve
  /// virar atualização). Só se espera pela trava do token com a do titular na
  /// mão, e quem a segura a solta no fim da própria transação: não há ciclo.
  @override
  Future<bool> registerIfConsented({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    final session = _session();
    final userUuid = UuidValue.fromString(userId);
    final areaUuid = microAreaId == null ? null : UuidValue.fromString(microAreaId);
    return session.db.transaction((transaction) async {
      await lockPerSubject(session, transaction, namespace: lockNamespacePushToken, key: userId);
      await lockPerSubject(session, transaction, namespace: lockNamespacePushTokenRow, key: token);
      final consent = await ConsentLog.db.findFirstRow(
        session,
        where: (t) =>
            t.userId.equals(userUuid) & t.purpose.equals(ConsentPurpose.segmentedPush.name),
        orderBy: (t) => t.timestamp,
        orderDescending: true,
        transaction: transaction,
      );
      final existing = await PushToken.db.findFirstRow(
        session,
        where: (t) => t.token.equals(token),
        transaction: transaction,
      );
      if (consent == null || consent.action != 'granted') {
        if (existing != null && existing.userId != userUuid) {
          await PushToken.db.deleteRow(session, existing, transaction: transaction);
        }
        return false;
      }
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
        return true;
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
      return true;
    });
  }

  @override
  Future<int> deleteAllFor(String userId) async {
    final session = _session();
    return session.db.transaction((transaction) async {
      await lockPerSubject(session, transaction, namespace: lockNamespacePushToken, key: userId);
      final removed = await PushToken.db.deleteWhere(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(userId)),
        transaction: transaction,
      );
      return removed.length;
    });
  }
}
