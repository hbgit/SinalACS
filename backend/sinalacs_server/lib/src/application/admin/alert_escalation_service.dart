import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

export 'package:sinalacs_server/src/application/admin/admin_scope.dart';

/// Como terminou a tentativa de escalonar (issue #44).
enum EscalationOutcome {
  /// Escalonou agora.
  escalated,

  /// Já estava escalonado: nada foi escrito, vale o carimbo original.
  alreadyEscalated,

  /// Ainda dentro do prazo (ou `triggeredAt` no futuro): não vence.
  notDue,

  /// Já confirmado/resolvido.
  notPending,

  /// Alerta amarelo/verde: só o vermelho escala.
  notRed,

  /// Não existe **ou** é de outra UBS: a mesma resposta para os dois.
  notFound,
}

/// Desfecho do store: [escalatedAt] vem preenchido em `escalated` e
/// `alreadyEscalated` (neste último, o carimbo ORIGINAL).
class EscalationAttempt {
  const EscalationAttempt(this.outcome, {this.escalatedAt});

  final EscalationOutcome outcome;
  final DateTime? escalatedAt;
}

/// Porta do escalonamento sobre o banco. O serviço não conhece SQL.
abstract interface class AlertEscalationStore implements AdminScopeStore {
  /// Decide e escreve numa **única** transação: trava a linha, relê, avalia o
  /// escopo, `status='pending'`, `riskLevel='red'`, `escalatedAt IS NULL` e o
  /// prazo (`@now - triggeredAt > @threshold`, estritamente; `triggeredAt` no
  /// futuro nunca vence) — o serviço não decide sobre estado velho.
  ///
  /// A auditoria de sucesso é gravada **pelo store**, na mesma transação do
  /// `UPDATE`, a partir de [auditFor] (`escalated` / `alreadyEscalated`); se a
  /// linha não grava, nada é escrito. Nas recusas o store não audita: quem
  /// audita é o serviço. Nunca altera `AlertStatus` (o alerta segue pendente).
  Future<EscalationAttempt> escalate(
    AdminScope scope, {
    required String alertId,
    required String actorId,
    required EscalationReason reason,
    required DateTime now,
    required Duration threshold,
    required AuditEvent Function(EscalationOutcome) auditFor,
  });
}

/// Escalonamento de alerta vermelho sem confirmação (issue #44).
///
/// Papel e escopo vêm do [AdminScopeResolver] (`write`). Toda recusa é auditada
/// com `record` (nunca `recordSafely`) **antes** de a exceção subir.
class AlertEscalationService {
  AlertEscalationService({
    required this.store,
    required this.audit,
    required this.threshold,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AlertEscalationStore store;
  final AuditTrail audit;

  /// `AppConfig.redAlertEscalationSeconds` como [Duration].
  final Duration threshold;
  final DateTime Function() _clock;

  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: store,
    audit: audit,
  );

  static const _recurso = 'admin_alert';
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<AdminEscalationResult> escalate(
    AuthenticatedUser user, {
    required String alertId,
    required EscalationReason reason,
  }) async {
    final scope = await _resolver.resolve(
      user,
      recurso: _recurso,
      actionType: 'write',
    );

    if (!_uuid.hasMatch(alertId)) {
      await _negar(
        user,
        'denied_invalid_id',
        null,
        'Identificador de alerta inválido.',
      );
    }
    final id = alertId.toLowerCase();

    final attempt = await store.escalate(
      scope,
      alertId: id,
      actorId: user.id,
      reason: reason,
      now: _clock().toUtc(),
      threshold: threshold,
      auditFor: (outcome) => AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: _recurso,
        resourceId: id,
        result:
            '${outcome == EscalationOutcome.alreadyEscalated ? 'already_escalated' : 'escalated'}:${_snake(reason)}',
      ),
    );

    switch (attempt.outcome) {
      case EscalationOutcome.escalated:
      case EscalationOutcome.alreadyEscalated:
        return AdminEscalationResult(
          alertId: id,
          escalatedAt: attempt.escalatedAt!,
          alreadyEscalated:
              attempt.outcome == EscalationOutcome.alreadyEscalated,
        );
      case EscalationOutcome.notDue:
        return _negar(
          user,
          'denied_not_due',
          id,
          'O prazo para escalonar este alerta ainda não venceu.',
        );
      case EscalationOutcome.notPending:
        return _negar(user, 'denied_not_pending', id, 'Alerta já confirmado.');
      case EscalationOutcome.notRed:
        return _negar(
          user,
          'denied_not_red',
          id,
          'Só alertas vermelhos podem ser escalonados.',
        );
      case EscalationOutcome.notFound:
        return _negar(
          user,
          'denied_not_found',
          id,
          'Alerta não encontrado.',
        );
    }
  }

  Future<Never> _negar(
    AuthenticatedUser user,
    String result,
    String? resourceId,
    String message,
  ) async {
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: _recurso,
        resourceId: resourceId,
        result: result,
      ),
    );
    throw AdminInvalidRequestException(message: message);
  }

  static String _snake(EscalationReason r) => switch (r) {
    EscalationReason.noAckTimeout => 'no_ack_timeout',
    EscalationReason.acsUnreachable => 'acs_unreachable',
    EscalationReason.patientRecontact => 'patient_recontact',
  };
}
