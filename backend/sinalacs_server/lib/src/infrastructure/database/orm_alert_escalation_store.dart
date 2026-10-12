import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/alert_escalation_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_outbox.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_case_store.dart'
    show AuditAppender;

/// Escalonamento de alerta vermelho (#44) sobre Postgres.
///
/// Uma transação por chamada: trava a linha do alerta (`SELECT … FOR UPDATE`),
/// relê o estado já sob o lock, decide em SQL e, se vencido, grava as três
/// colunas de escalonamento, enfileira **um** reforço no outbox e audita — as
/// três escritas vivem ou morrem juntas. Status, `acknowledgedAt`, `acsId` e
/// `version` nunca são tocados (D3: o alerta segue pendente para o ACS).
///
/// Escopo como em `OrmAdminReadStore`: `alerts → micro_areas.ubsId` por junção
/// `LEFT`; o coordenador não enxerga alerta sem microárea, o administrador sim.
///
/// Ordem dos locks, sempre a mesma: linha do alerta, depois a cadeia de
/// auditoria (tomada dentro de [appendAudit], por último). O ACK
/// (`OrmAlertStore.acknowledge`) pega a linha pelo `UPDATE` e a cadeia depois,
/// na mesma ordem — não há deadlock entre os dois.
class OrmAlertEscalationStore implements AlertEscalationStore {
  OrmAlertEscalationStore({required this.session, required this.appendAudit});

  /// A sessão da requisição, por chamada (padrão dos stores ORM).
  final Session Function() session;

  /// Onde o desfecho gravado é auditado, dentro da transação dele. Em produção
  /// é `OrmAuditTrail.recordInTransaction`; o teste injeta uma falha por aqui.
  final AuditAppender appendAudit;

  /// `UuidValue.fromString` não valida: a string inválida só estoura no
  /// Postgres (22P02). Id malformado = alerta inexistente.
  static UuidValue? _uuid(String id) =>
      Uuid.isValidUUID(fromString: id) ? UuidValue.fromString(id) : null;

  @override
  Future<String?> ubsOf(String staffId) async {
    final id = _uuid(staffId);
    if (id == null) return null;
    final conta = await StaffAccount.db.findById(session(), id);
    return conta?.ubsId?.toString();
  }

  @override
  Future<EscalationAttempt> escalate(
    AdminScope scope, {
    required String alertId,
    required String actorId,
    required EscalationReason reason,
    required DateTime now,
    required Duration threshold,
    required AuditEvent Function(EscalationOutcome) auditFor,
  }) async {
    final id = _uuid(alertId);
    if (id == null) return const EscalationAttempt(EscalationOutcome.notFound);
    final sessao = session();
    final agora = now.toUtc();

    return sessao.db.transaction((transaction) async {
      // 1. Escopo e lock numa instrução só. `FOR UPDATE OF a`: a microárea fica
      //    do lado anulável da junção e não pode (nem precisa) ser travada.
      //    Fora do escopo e inexistente dão a mesma resposta.
      final travado = await sessao.db.unsafeQuery(
        '''
        SELECT a.id
        FROM alerts a
        LEFT JOIN micro_areas m ON m.id = a."microAreaId"
        WHERE a.id = @id::uuid
          AND (@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)
        FOR UPDATE OF a
        ''',
        parameters: QueryParameters.named({'id': id.uuid, 'ubs': scope.ubsId}),
        transaction: transaction,
      );
      if (travado.isEmpty) {
        return const EscalationAttempt(EscalationOutcome.notFound);
      }

      // 2. Releitura já sob o lock: quem esperou a outra transação enxerga o
      //    que ela gravou. O prazo é decidido aqui, em SQL, com o `@now` e o
      //    limite recebidos: vencido só se `now − triggeredAt > limite`,
      //    estritamente; `triggeredAt` no futuro dá intervalo negativo e nunca
      //    vence. A concordância com `OrmAdminReadStore` (`overdue`) é pinada
      //    por test/integration/admin_read_store_test.dart ('acordo: …').
      final linha = (await sessao.db.unsafeQuery(
        '''
        SELECT a."riskLevel", a.status, a."escalatedAt",
               (@now::timestamp - a."triggeredAt")
                 > (@limite::bigint * interval '1 microsecond') AS vencido,
               a."patientId", a."microAreaId", a."locationHash",
               a."locationCell", a."triggeredAt"
        FROM alerts a
        WHERE a.id = @id::uuid
        ''',
        parameters: QueryParameters.named({
          'id': id.uuid,
          'now': agora,
          'limite': threshold.inMicroseconds,
        }),
        transaction: transaction,
      )).single;

      // 3. Precedência fixa (a mesma do store falso do teste do serviço):
      //    notFound > notRed > notPending > alreadyEscalated > notDue.
      if (linha[0] != RiskLevel.red.name) {
        return const EscalationAttempt(EscalationOutcome.notRed);
      }
      if (linha[1] != AlertStatus.pending.name) {
        return const EscalationAttempt(EscalationOutcome.notPending);
      }
      final original = linha[2] as DateTime?;
      if (original != null) {
        // Repetição: nada muda no alerta nem no outbox; só a linha da trilha,
        // com o motivo PEDIDO agora (`already_escalated:<motivo>`).
        await appendAudit(
          sessao,
          transaction,
          auditFor(EscalationOutcome.alreadyEscalated),
        );
        return EscalationAttempt(
          EscalationOutcome.alreadyEscalated,
          escalatedAt: original.toUtc(),
        );
      }
      if (linha[3] != true) {
        return const EscalationAttempt(EscalationOutcome.notDue);
      }

      // 4. Só as três colunas de escalonamento; o status fica pendente.
      await sessao.db.unsafeExecute(
        '''
        UPDATE alerts
        SET "escalatedAt" = @now::timestamp,
            "escalatedBy" = @por::uuid,
            "escalationReason" = @motivo
        WHERE id = @id::uuid
        ''',
        parameters: QueryParameters.named({
          'id': id.uuid,
          'now': agora,
          'por': actorId,
          'motivo': reason.name,
        }),
        transaction: transaction,
      );

      // 5. Reforço (D2): uma entrega nova no outbox de sempre, elegível já,
      //    com o mesmo envelope do alerta mais o marcador `escalated`. Alerta
      //    sem microárea (só o administrador o vê) não tem tópico de
      //    território: escalona e audita, sem reforço — não há a quem entregar.
      //    `alert_outbox` não tem índice único por `alertId`: cada reforço é
      //    uma linha própria, e a entrega original (publicada ou não) fica
      //    como está.
      final microArea = linha[5];
      if (microArea != null) {
        await OrmAlertOutbox(
          session: () => sessao,
          transaction: transaction,
          clock: () => agora,
        ).enqueue(
          AlertDelivery(
            alertId: id.uuid,
            patientId: linha[4].toString(),
            microAreaId: microArea.toString(),
            riskLevel: RiskLevel.red.name,
            locationHash: linha[6] as String,
            locationCell: linha[7] as String?,
            triggeredAt: (linha[8] as DateTime).toUtc(),
            escalated: true,
          ),
        );
      }

      // 6. Por último e na mesma transação: se a trilha falhar, nada fica.
      await appendAudit(
        sessao,
        transaction,
        auditFor(EscalationOutcome.escalated),
      );
      return EscalationAttempt(EscalationOutcome.escalated, escalatedAt: agora);
    });
  }
}
