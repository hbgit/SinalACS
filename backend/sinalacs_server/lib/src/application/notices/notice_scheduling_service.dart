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

/// Item do histórico: deliberadamente SEM o texto da mensagem (o backoffice
/// lista títulos e contagens; o texto só existe no aviso e no envio).
class NoticeHistoryItem {
  const NoticeHistoryItem({
    required this.id,
    required this.createdBy,
    required this.microAreaId,
    required this.audience,
    required this.title,
    required this.scheduledFor,
    required this.status,
    this.recipients,
    this.accepted,
    this.sentAt,
  });

  factory NoticeHistoryItem.from(ScheduledNoticeSnapshot s) => NoticeHistoryItem(
        id: s.id,
        createdBy: s.createdBy,
        microAreaId: s.microAreaId,
        audience: s.audience,
        title: s.title,
        scheduledFor: s.scheduledFor,
        status: s.status,
        recipients: s.recipients,
        accepted: s.accepted,
        sentAt: s.sentAt,
      );

  final String id;

  /// Quem criou o aviso (id do usuário; o endpoint o traduz em matrícula).
  final String createdBy;
  final String microAreaId;
  final String audience;
  final String title;
  final DateTime scheduledFor;
  final ScheduledNoticeStatus status;
  final int? recipients;
  final int? accepted;
  final DateTime? sentAt;
}

/// Limites de paginação do histórico.
const int noticeHistoryDefaultLimit = 50;
const int noticeHistoryMaxLimit = 100;

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

  /// Linha pelo id, ou `null` se não existe.
  Future<ScheduledNoticeSnapshot?> findById(String id);

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

  /// Cancela um aviso ainda `pending`. Coordenador só cancela o da própria UBS.
  Future<void> cancel(AuthenticatedUser user, String id) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      await _deny(user, id, 'denied_role');
    }
    final notice = await _store.findById(id);
    if (notice == null) {
      throw AdminInvalidRequestException(message: 'Aviso não encontrado.');
    }
    if (user.role == UserRole.coordinator) {
      final own = await _store.ubsOfStaff(user.id);
      final target = await _store.ubsOfMicroArea(notice.microAreaId);
      if (own == null || target == null || own != target) {
        await _deny(user, id, 'denied_territory');
      }
    }
    // Atômico: se o despacho reservou o aviso entre a leitura e aqui, recusa.
    if (!await _store.cancelIfPending(id)) {
      throw AdminInvalidRequestException(message: 'Só avisos pendentes podem ser cancelados.');
    }
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'community_notice',
      resourceId: id,
      result: 'cancelled',
    ));
  }

  /// Histórico de avisos, sem o texto. Coordenador: só a própria UBS.
  Future<List<NoticeHistoryItem>> history(
    AuthenticatedUser user, {
    String? microAreaId,
    int limit = noticeHistoryDefaultLimit,
    int offset = 0,
  }) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      await _deny(user, microAreaId ?? '', 'denied_role', actionType: 'read');
    }
    String? ubsId;
    if (user.role == UserRole.coordinator) {
      ubsId = await _store.ubsOfStaff(user.id);
      if (ubsId == null) {
        await _deny(user, microAreaId ?? '', 'denied_territory', actionType: 'read');
      }
      if (microAreaId != null && await _store.ubsOfMicroArea(microAreaId) != ubsId) {
        await _deny(user, microAreaId, 'denied_territory', actionType: 'read');
      }
    }
    final rows = await _store.history(
      microAreaId: microAreaId,
      ubsId: ubsId,
      limit: limit.clamp(1, noticeHistoryMaxLimit),
      offset: offset < 0 ? 0 : offset,
    );
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'community_notice',
      result: 'granted',
    ));
    return rows.map(NoticeHistoryItem.from).toList();
  }

  /// Dispara os avisos vencidos. A reserva `pending -> sending` é atômica
  /// ([ScheduledNoticeStore.claimDue]), então duas chamadas nunca enviam o mesmo
  /// aviso. Sem reenvio automático: falha vira `failed`, resultado desconhecido
  /// vira `unknown`. Um erro num aviso nunca derruba os demais. Devolve quantos
  /// avisos esta chamada processou.
  Future<int> dispatchDue() async {
    final claimed = await _store.claimDue(_clock().toUtc());
    for (final notice in claimed) {
      try {
        final r = await _sendNow(
          microAreaId: notice.microAreaId,
          audience: notice.audience,
          title: notice.title,
          message: notice.message,
          actorId: notice.createdBy,
        );
        await _finish(notice, ScheduledNoticeStatus.sent,
            recipients: r.recipients, accepted: r.accepted);
      } on NoticeDeliveryException catch (e) {
        if (isNoticeOutcomeUnknown(e)) {
          // Já auditado como `unknown` por quem enviou.
          await _finish(notice, ScheduledNoticeStatus.unknown, reason: e.message);
        } else {
          await _failed(notice, e.message);
        }
      } catch (_) {
        await _failed(notice, 'Falha inesperada ao enviar o aviso.');
      }
    }
    return claimed.length;
  }

  Future<void> _failed(ScheduledNoticeSnapshot notice, String reason) async {
    await _finish(notice, ScheduledNoticeStatus.failed, reason: reason);
    await _audit.recordSafely(AuditEvent(
      userId: notice.createdBy,
      actionType: 'write',
      resourceType: 'community_notice',
      resourceId: notice.id,
      result: 'failed',
    ));
  }

  Future<void> _finish(
    ScheduledNoticeSnapshot notice,
    ScheduledNoticeStatus status, {
    int? recipients,
    int? accepted,
    String? reason,
  }) async {
    try {
      await _store.finish(
        notice.id,
        status: status,
        recipients: recipients,
        accepted: accepted,
        failureReason: reason,
        at: _clock().toUtc(),
      );
    } catch (_) {
      // Não derruba o laço: a linha fica `sending` (nunca reenviada).
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Grava a negação (só ator e microárea; nunca o texto) e lança. O
  /// `resourceId` vem do cliente: só vai se for UUID, senão a trilha ORM lançaria
  /// e `recordSafely` engoliria a negação.
  Future<Never> _deny(
    AuthenticatedUser user,
    String microAreaId,
    String result, {
    String actionType = 'write',
  }) async {
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: actionType,
      resourceType: 'community_notice',
      resourceId: _uuid.hasMatch(microAreaId) ? microAreaId : null,
      result: result,
    ));
    throw StateError('Sem permissão para agendar avisos nesta microárea.');
  }
}
