import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';

const int noticeTitleMaxLength = 60;
const int noticeMessageMaxLength = 240;

/// Quem recebe: todos os consentidos da microárea, ou só os crônicos.
const Set<String> noticeAudiences = {'everyone', 'chronic'};

/// Resolve os destinatários de um aviso. Interface aqui, implementação ORM em
/// `infrastructure/`, mesmo padrão dos demais stores.
abstract interface class NoticeRecipientStore {
  /// Aparelhos dos pacientes da [microAreaId] cuja linha de consentimento
  /// **mais recente** de `segmentedPush` é `granted` — a existência do token não
  /// basta. [chronicOnly] restringe a quem tem `patients.isChronic`.
  Future<List<PushTarget>> consentedTargets({
    required String microAreaId,
    required bool chronicOnly,
  });

  /// Apaga os tokens que o provedor declarou inválidos.
  Future<int> deleteTokens(List<String> tokens);
}

class NoticeSendSnapshot {
  const NoticeSendSnapshot({required this.recipients, required this.accepted});

  final int recipients;
  final int accepted;
}

/// Aviso comunitário do ACS aos pacientes da própria microárea (RF14).
///
/// A microárea vem SEMPRE do token do ACS, nunca de parâmetro (invariante de
/// território). O payload leva só o texto digitado e a tela a abrir: nenhum dado
/// do paciente (decisão §3.2).
class NoticeService {
  NoticeService({
    required NoticeRecipientStore store,
    required PushSender? sender,
    required AuditTrail audit,
  })  : _store = store,
        _sender = sender,
        _audit = audit;

  final NoticeRecipientStore _store;
  final PushSender? _sender;
  final AuditTrail _audit;

  Future<NoticeSendSnapshot> sendSegmented(
    AuthenticatedUser user, {
    required String title,
    required String message,
    required String audience,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () => StateError('Somente o ACS envia avisos à comunidade.'),
    );
    final cleanTitle = title.trim();
    final cleanMessage = message.trim();
    if (cleanTitle.isEmpty || cleanMessage.isEmpty) {
      throw DataRightsException(message: 'Informe o título e a mensagem do aviso.');
    }
    if (cleanTitle.length > noticeTitleMaxLength) {
      throw DataRightsException(
        message: 'O título pode ter no máximo $noticeTitleMaxLength caracteres.',
      );
    }
    if (cleanMessage.length > noticeMessageMaxLength) {
      throw DataRightsException(
        message: 'A mensagem pode ter no máximo $noticeMessageMaxLength caracteres.',
      );
    }
    if (!noticeAudiences.contains(audience)) {
      throw DataRightsException(message: 'Público do aviso desconhecido.');
    }
    final sender = _sender;
    if (sender == null) {
      throw NoticeDeliveryException(
        message: 'O envio de avisos não está configurado neste ambiente.',
      );
    }

    final microAreaId = user.microAreaId!;
    final targets = await _store.consentedTargets(
      microAreaId: microAreaId,
      chronicOnly: audience == 'chronic',
    );
    if (targets.isEmpty) {
      await _record(user, microAreaId, 'no_recipients');
      return const NoticeSendSnapshot(recipients: 0, accepted: 0);
    }

    final PushSendReport report;
    try {
      report = await sender.send(
        PushMessage(title: cleanTitle, body: cleanMessage, data: const {'screen': 'notices'}),
        targets,
      );
    } on PushGatewayException catch (error) {
      if (error.outcomeUnknown) {
        // O pedido saiu e a resposta não voltou: parte dos pacientes pode já ter
        // recebido. Dizer "tente de novo" levaria ao aviso em duplicata.
        await _record(user, microAreaId, 'unknown');
        throw NoticeDeliveryException(
          message: 'O envio demorou e o resultado é desconhecido: alguns pacientes '
              'podem já ter recebido o aviso. Confira antes de reenviar.',
        );
      }
      throw NoticeDeliveryException(
        message: 'Não foi possível entregar o aviso agora. Tente de novo em instantes.',
      );
    }
    if (report.invalidTokens.isNotEmpty) {
      await _store.deleteTokens(report.invalidTokens);
    }
    await _record(user, microAreaId, 'granted');
    return NoticeSendSnapshot(recipients: targets.length, accepted: report.accepted);
  }

  /// Só quem enviou e para qual microárea; o texto do aviso nunca entra aqui.
  Future<void> _record(AuthenticatedUser user, String microAreaId, String result) =>
      _audit.recordSafely(AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'community_notice',
        resourceId: microAreaId,
        result: result,
      ));
}
