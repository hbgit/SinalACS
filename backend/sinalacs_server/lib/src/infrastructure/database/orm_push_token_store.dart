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
  Future<PushRegistrationResult> registerIfConsented({
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
        // Desempate por id: dois consentimentos no mesmo instante não podem deixar
        // a leitura não determinística.
        orderByList: (t) => [
          Order(column: t.timestamp, orderDescending: true),
          Order(column: t.id, orderDescending: true),
        ],
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
        return const PushRegistrationResult(PushRegistration.refused);
      }
      final ownerChanged = existing != null && existing.userId != userUuid;
      final previousOwnerId = ownerChanged ? existing.userId.uuid : null;
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
      } else {
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
      }
      // Teto por titular. Poupa sempre o token que acabou de entrar (um relógio que
      // voltou o faria parecer o mais antigo) e apaga por id E titular: se outro
      // registro roubou um desses tokens entre a leitura e o apagamento, a linha
      // já é de outro e não pode ser levada por esta poda.
      final mine = await PushToken.db.find(
        session,
        where: (t) => t.userId.equals(userUuid) & t.token.notEquals(token),
        orderByList: (t) => [
          Order(column: t.updatedAt, orderDescending: true),
          Order(column: t.createdAt, orderDescending: true),
        ],
        transaction: transaction,
      );
      final doomed = mine.skip(maxPushTokensPerUser - 1).map((t) => t.id!).toSet();
      if (doomed.isNotEmpty) {
        await PushToken.db.deleteWhere(
          session,
          where: (t) => t.id.inSet(doomed) & t.userId.equals(userUuid),
          transaction: transaction,
        );
      }
      return ownerChanged
          ? PushRegistrationResult(PushRegistration.ownerChanged, previousOwnerId: previousOwnerId)
          : const PushRegistrationResult(PushRegistration.registered);
    });
  }
}
