import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/notices/notice_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';

/// Implementação de [NoticeRecipientStore] sobre o Postgres.
class OrmNoticeRecipientStore implements NoticeRecipientStore {
  OrmNoticeRecipientStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  /// A segmentação acontece aqui, no banco (decisão §3.2). O consentimento
  /// decisivo é a linha **mais recente** de `segmentedPush` de cada titular:
  /// quem revogou depois de registrar o token fica de fora mesmo que o token
  /// ainda esteja na tabela. Parâmetros sempre nomeados, nunca interpolados.
  @override
  Future<List<PushTarget>> consentedTargets({
    required String microAreaId,
    required bool chronicOnly,
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT pt."token" AS token, pt."platform" AS platform
      FROM push_tokens pt
      JOIN users u ON u."id" = pt."userId"
      JOIN patients p ON p."id" = u."id"
      WHERE u."microAreaId" = @micro::uuid
        AND u."role" = 'patient'
        AND (NOT @chronic OR p."isChronic")
        AND COALESCE((
              SELECT c."action" FROM consent_logs c
              WHERE c."userId" = pt."userId" AND c."purpose" = 'segmentedPush'
              ORDER BY c."timestamp" DESC LIMIT 1
            ), 'denied') = 'granted'
      ORDER BY pt."token"
      ''',
      parameters: QueryParameters.named({
        'micro': microAreaId,
        'chronic': chronicOnly,
      }),
    );
    return [
      for (final row in rows)
        PushTarget(
          token: row.toColumnMap()['token'] as String,
          platform: row.toColumnMap()['platform'] as String,
        ),
    ];
  }

  @override
  Future<int> deleteTokens(List<String> tokens) async {
    if (tokens.isEmpty) return 0;
    final removed = await PushToken.db.deleteWhere(
      _session(),
      where: (t) => t.token.inSet(tokens.toSet()),
    );
    return removed.length;
  }
}
