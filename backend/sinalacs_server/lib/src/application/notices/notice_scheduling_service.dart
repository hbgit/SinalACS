import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Envia agora um aviso a uma microárea (a Task 1.4 extrai isto de
/// `NoticeService`). O texto só trafega por aqui, nunca pela auditoria.
typedef NoticeSender = Future<NoticeSendSnapshot> Function({
  required String microAreaId,
  required String audience,
  required String title,
  required String message,
  required String actorId,
});

/// Antecedência mínima entre o pedido e o horário agendado.
const Duration noticeMinimumLeadTime = Duration(minutes: 1);

/// Linha de `scheduled_notices` como a camada de aplicação a enxerga.
class ScheduledNoticeSnapshot {
  const ScheduledNoticeSnapshot({
    required this.id,
    required this.createdBy,
    required this.microAreaId,
    required this.audience,
    required this.title,
    required this.message,
    required this.scheduledFor,
    required this.status,
    required this.createdAt,
    this.recipients,
    this.accepted,
    this.failureReason,
    this.sentAt,
  });

  final String id;
  final String createdBy;
  final String microAreaId;
  final String audience;
  final String title;
  final String message;
  final DateTime scheduledFor;
  final ScheduledNoticeStatus status;
  final int? recipients;
  final int? accepted;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? sentAt;
}

/// Persistência dos avisos agendados. A implementação ORM fica em
/// `infrastructure/` (Task 1.5).
abstract interface class ScheduledNoticeStore {
  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOfStaff(String userId);

  /// UBS da microárea, ou `null` se a microárea não existe.
  Future<String?> ubsOfMicroArea(String microAreaId);

  Future<String> insert({
    required String createdBy,
    required String microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
    required DateTime createdAt,
  });

  Future<bool> cancelIfPending(String id);

  /// pending -> sending atômico: devolve só as linhas que ESTA chamada reservou.
  Future<List<ScheduledNoticeSnapshot>> claimDue(DateTime now, {int limit = 20});

  Future<void> finish(
    String id, {
    required ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime at,
  });

  Future<List<ScheduledNoticeSnapshot>> history({
    String? microAreaId,
    String? ubsId,
    required int limit,
    required int offset,
  });
}

/// Agendamento de aviso comunitário pelo backoffice (RF14, #46).
///
/// Só `coordinator`/`admin`; o coordenador só agenda para microárea da própria
/// UBS (fail-closed sem UBS). Toda negação é auditada com `await` antes de
/// lançar. O texto do aviso nunca entra na auditoria.
class NoticeSchedulingService {
  NoticeSchedulingService({
    required ScheduledNoticeStore store,
    required AuditTrail audit,
    required NoticeSender sendNow,
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _sendNow = sendNow,
        _clock = clock ?? DateTime.now;

  final ScheduledNoticeStore _store;
  final AuditTrail _audit;
  // Usado pelo despacho (Task 1.4); o agendamento não envia nada.
  // ignore: unused_field
  final NoticeSender _sendNow;
  final DateTime Function() _clock;

  Future<String> schedule(
    AuthenticatedUser user, {
    required String microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
  }) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      await _deny(user, microAreaId, 'denied_role');
    }
    final target = await _store.ubsOfMicroArea(microAreaId);
    if (user.role == UserRole.coordinator) {
      final own = await _store.ubsOfStaff(user.id);
      if (own == null || target == null || own != target) {
        await _deny(user, microAreaId, 'denied_territory');
      }
    } else if (target == null) {
      // Admin: microárea inexistente é entrada inválida, não negação.
      throw AdminInvalidRequestException(message: 'Microárea não encontrada.');
    }

    final cleanTitle = title.trim();
    final cleanMessage = message.trim();
    if (cleanTitle.isEmpty || cleanMessage.isEmpty) {
      throw AdminInvalidRequestException(message: 'Informe o título e a mensagem do aviso.');
    }
    if (cleanTitle.length > noticeTitleMaxLength) {
      throw AdminInvalidRequestException(
        message: 'O título pode ter no máximo $noticeTitleMaxLength caracteres.',
      );
    }
    if (cleanMessage.length > noticeMessageMaxLength) {
      throw AdminInvalidRequestException(
        message: 'A mensagem pode ter no máximo $noticeMessageMaxLength caracteres.',
      );
    }
    if (!noticeAudiences.contains(audience)) {
      throw AdminInvalidRequestException(message: 'Público do aviso desconhecido.');
    }
    final now = _clock();
    if (scheduledFor.isBefore(now.add(noticeMinimumLeadTime))) {
      throw AdminInvalidRequestException(
        message: 'O horário do aviso deve ser pelo menos 1 minuto à frente.',
      );
    }

    final id = await _store.insert(
      createdBy: user.id,
      microAreaId: microAreaId,
      audience: audience,
      title: cleanTitle,
      message: cleanMessage,
      scheduledFor: scheduledFor.toUtc(),
      createdAt: now.toUtc(),
    );
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'community_notice',
      resourceId: id,
      result: 'scheduled',
    ));
    return id;
  }

  /// Grava a negação (só ator e microárea; nunca o texto) e lança.
  Future<Never> _deny(AuthenticatedUser user, String microAreaId, String result) async {
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'community_notice',
      resourceId: microAreaId,
      result: result,
    ));
    throw StateError('Sem permissão para agendar avisos nesta microárea.');
  }
}
