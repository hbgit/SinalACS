import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/common/uuid_format.dart';
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
  String? auditResourceId,
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
    this.microAreaName,
    this.createdByLabel,
  });

  final String id;
  final String createdBy;
  final String microAreaId;

  /// Nome da microárea e matrícula de quem criou: só o `history` do store os
  /// resolve (JOIN); nas demais leituras ficam nulos.
  final String? microAreaName;
  final String? createdByLabel;
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
    this.failureReason,
    this.microAreaName,
    this.createdByLabel,
  });

  factory NoticeHistoryItem.from(ScheduledNoticeSnapshot s) =>
      NoticeHistoryItem(
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
        failureReason: s.failureReason,
        microAreaName: s.microAreaName,
        createdByLabel: s.createdByLabel,
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
  final String? failureReason;
  final String? microAreaName;

  /// Matrícula de quem criou (nunca nome de paciente).
  final String? createdByLabel;
}

/// Janela após a qual um aviso preso em `sending` é dado como de resultado
/// desconhecido na partida.
const Duration noticeStuckSendingAfter = Duration(minutes: 10);
const String noticeStuckSendingReason =
    'Resultado desconhecido: o servidor reiniciou durante o envio';

/// Motivo gravado quando o disparo recusa o aviso porque quem o agendou já não
/// pode enviar para a microárea (desativado, sem conta de staff, papel ou UBS
/// trocados). Não há reenvio: o aviso termina `failed`.
const String noticeAuthorRevokedReason =
    'Quem agendou já não pode enviar avisos para esta microárea';

/// Autoridade atual de um usuário de staff, lida no disparo (não no token).
class StaffAuthority {
  const StaffAuthority({required this.role, required this.active, this.ubsId});

  final UserRole role;
  final bool active;

  /// UBS do coordenador; nula para administrador.
  final String? ubsId;
}

/// Limites de paginação do histórico.
const int noticeHistoryDefaultLimit = 50;
const int noticeHistoryMaxLimit = 100;

/// Aviso que a varredura de partida levou de `sending` a `unknown`: só id e
/// autor, nunca o texto.
class StuckNotice {
  const StuckNotice({required this.id, required this.createdBy});

  final String id;
  final String createdBy;
}

/// Persistência dos avisos agendados. A implementação ORM fica em
/// `infrastructure/` (Task 1.5).
abstract interface class ScheduledNoticeStore {
  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOfStaff(String userId);

  /// UBS da microárea, ou `null` se a microárea não existe.
  Future<String?> ubsOfMicroArea(String microAreaId);

  /// Papel, situação e UBS atuais do usuário de staff, ou `null` se ele não tem
  /// linha em `staff_accounts` (o disparo trata isso como recusa).
  Future<StaffAuthority?> authorityOf(String userId);

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

  /// Varredura de partida: leva `sending` com `scheduledFor` anterior a
  /// [before] a `unknown` (nunca de volta a `pending`: não há reenvio
  /// automático). Devolve os avisos que moveu (id e autor), para a trilha.
  Future<List<StuckNotice>> markStaleSendingUnknown({
    required DateTime before,
    required String reason,
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
    _requireUuid(microAreaId);
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
    await _audit.record(AuditEvent(
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
    _requireUuid(id);
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
    await _audit.record(AuditEvent(
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
    if (microAreaId != null) _requireUuid(microAreaId);
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
    // Fail-closed: audita ANTES de consultar; se não grava, o store não é chamado.
    await _audit.record(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'community_notice',
      result: 'granted',
    ));
    final rows = await _store.history(
      microAreaId: microAreaId,
      ubsId: ubsId,
      limit: limit.clamp(1, noticeHistoryMaxLimit),
      offset: offset < 0 ? 0 : offset,
    );
    return rows.map(NoticeHistoryItem.from).toList();
  }

  /// Dispara os avisos vencidos. A reserva `pending -> sending` é atômica
  /// ([ScheduledNoticeStore.claimDue]), então duas chamadas nunca enviam o mesmo
  /// aviso. Sem reenvio automático: falha vira `failed`, resultado desconhecido
  /// vira `unknown`. Um erro num aviso nunca derruba os demais. Devolve quantos
  /// avisos esta chamada processou. Antes de enviar, reconfere a autoridade de
  /// quem agendou ([_authorMayStillSend]): quem perdeu o direito não envia, e o
  /// aviso termina `failed`.
  Future<int> dispatchDue() async {
    final claimed = await _store.claimDue(_clock().toUtc());
    for (final notice in claimed) {
      try {
        if (!await _authorMayStillSend(notice)) {
          await _finish(notice, ScheduledNoticeStatus.failed, reason: noticeAuthorRevokedReason);
          await _audit.recordSafely(AuditEvent(
            userId: notice.createdBy,
            actionType: 'write',
            resourceType: 'community_notice',
            resourceId: notice.id,
            result: 'denied_author_revoked',
          ));
          continue;
        }
        final r = await _sendNow(
          microAreaId: notice.microAreaId,
          audience: notice.audience,
          title: notice.title,
          message: notice.message,
          actorId: notice.createdBy,
          auditResourceId: notice.id,
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

  /// Varredura de partida: `sending` há mais de [noticeStuckSendingAfter] vira
  /// `unknown` (o processo caiu entre a reserva e o fim; o envio pode ter
  /// ocorrido, então jamais volta a `pending`). Grava uma linha de auditoria
  /// (`unknown_after_restart`, autor = quem agendou, recurso = o aviso) por aviso
  /// movido, com `recordSafely`: é a partida do servidor e a trilha não pode
  /// impedir o boot. Devolve quantas linhas moveu.
  Future<int> recoverStuckSending() async {
    final moved = await _store.markStaleSendingUnknown(
      before: _clock().toUtc().subtract(noticeStuckSendingAfter),
      reason: noticeStuckSendingReason,
      at: _clock().toUtc(),
    );
    for (final notice in moved) {
      await _audit.recordSafely(AuditEvent(
        userId: notice.createdBy,
        actionType: 'write',
        resourceType: 'community_notice',
        resourceId: notice.id,
        result: 'unknown_after_restart',
      ));
    }
    return moved.length;
  }

  /// Regra do agendamento reaplicada no disparo, com o estado de AGORA: staff
  /// ativo; coordenador só para microárea da própria UBS. Fail-closed.
  Future<bool> _authorMayStillSend(ScheduledNoticeSnapshot notice) async {
    final authority = await _store.authorityOf(notice.createdBy);
    if (authority == null || !authority.active) return false;
    if (!Authorization.staffRoles.contains(authority.role)) return false;
    if (authority.role == UserRole.coordinator) {
      final target = await _store.ubsOfMicroArea(notice.microAreaId);
      return authority.ubsId != null && target != null && authority.ubsId == target;
    }
    return true;
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

  /// Identificador do cliente que não é UUID é entrada inválida, não erro 500
  /// do `::uuid` do SQL. Vem depois da autorização e antes de qualquer store.
  static void _requireUuid(String value) {
    if (!isUuidFormat(value)) {
      throw AdminInvalidRequestException(message: 'Identificador inválido.');
    }
  }

  /// Grava a negação (só ator e microárea; nunca o texto) e lança. Fail-closed:
  /// `record` (não `recordSafely`), então se a gravação falha a exceção sobe e a
  /// operação continua negada. O `resourceId` vem do cliente: só vai se for UUID,
  /// senão a trilha ORM lançaria.
  Future<Never> _deny(
    AuthenticatedUser user,
    String microAreaId,
    String result, {
    String actionType = 'write',
  }) async {
    await _audit.record(AuditEvent(
      userId: user.id,
      actionType: actionType,
      resourceType: 'community_notice',
      resourceId: isUuidFormat(microAreaId) ? microAreaId : null,
      result: result,
    ));
    throw StateError('Sem permissão para esta operação de avisos.');
  }
}
