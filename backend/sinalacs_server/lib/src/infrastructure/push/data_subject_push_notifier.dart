import 'dart:io';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/data_subject_case_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';

/// Aparelhos de UM titular que ainda consentem com push. Interface à parte do
/// ORM para o notificador ser testável sem banco.
abstract interface class DataSubjectPushTargets {
  /// Tokens do [userId] só se a linha **mais recente** de `segmentedPush` em
  /// `consent_logs` é `granted`; sem consentimento ou sem token, lista vazia.
  Future<List<PushTarget>> consentedTargetsOf(String userId);
}

class OrmDataSubjectPushTargets implements DataSubjectPushTargets {
  OrmDataSubjectPushTargets({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<List<PushTarget>> consentedTargetsOf(String userId) async {
    if (!Uuid.isValidUUID(fromString: userId)) return const [];
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT pt."token" AS token, pt."platform" AS platform
      FROM push_tokens pt
      WHERE pt."userId" = @user::uuid
        AND COALESCE((
              SELECT c."action" FROM consent_logs c
              WHERE c."userId" = pt."userId" AND c."purpose" = 'segmentedPush'
              ORDER BY c."timestamp" DESC, c."id" DESC LIMIT 1
            ), 'denied') = 'granted'
      ORDER BY pt."token"
      ''',
      parameters: QueryParameters.named({'user': userId}),
    );
    return [
      for (final row in rows)
        PushTarget(
          token: row.toColumnMap()['token'] as String,
          platform: row.toColumnMap()['platform'] as String,
        ),
    ];
  }
}

/// Avisa o titular, por push, que o pedido dele foi respondido. O texto é fixo
/// e genérico: nem a nota, nem o tipo do pedido, nem o resultado saem do
/// servidor; o detalhe fica em "Meus dados", atrás do login. Sem remetente
/// (`GORUSH_URL` ausente) é no-op. Qualquer falha é engolida: a decisão já foi
/// gravada e o aviso é melhor esforço.
class GorushDataSubjectNotifier implements DataSubjectNotifier {
  GorushDataSubjectNotifier({
    required DataSubjectPushTargets targets,
    required PushSender? sender,
  })  : _targets = targets,
        _sender = sender;

  final DataSubjectPushTargets _targets;
  final PushSender? _sender;

  static const title = 'Seu pedido foi respondido';
  static const body = 'Abra o SinalACS e veja a resposta em Meus dados.';
  static const screen = 'my_data';

  @override
  Future<void> decided(String userId, DataSubjectRequestStatus status) async {
    final sender = _sender;
    if (sender == null) return;
    if (status != DataSubjectRequestStatus.completed &&
        status != DataSubjectRequestStatus.rejected) {
      return;
    }
    try {
      final alvos = await _targets.consentedTargetsOf(userId);
      if (alvos.isEmpty) return;
      await sender.send(
        const PushMessage(title: title, body: body, data: {'screen': screen}),
        alvos,
      );
    } catch (e) {
      // Só o tipo: a mensagem do erro poderia citar token ou corpo.
      stderr.writeln('push ao titular falhou: ${e.runtimeType}');
    }
  }
}
