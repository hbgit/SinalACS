import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [AlertStore] sobre o ORM do Serverpod.
///
/// Substitui o `PostgresAlertStore`, que executava SQL cru sobre o cliente
/// `postgres` v2 — API incompatível com a v3 que o Serverpod usa.
///
/// A sessão é obtida por chamada, e não guardada no construtor, porque o
/// Serverpod amarra o ciclo de vida da conexão à `Session` da requisição.
///
/// Quando [transaction] é fornecida, todas as escritas participam dela: é o que
/// torna atômico o trio gravar alerta, registrar chave de idempotência e
/// publicar no broker.
class OrmAlertStore implements AlertStore {
  OrmAlertStore({
    required Session Function() session,
    required Future<void> Function(
      Session session,
      Transaction transaction,
      AuditEvent event,
    ) appendAudit,
    Transaction? transaction,
  })  : _session = session,
        _appendAudit = appendAudit,
        _transaction = transaction;

  /// Grava a auditoria DENTRO da transação do ACK (fail-closed): em produção é
  /// `OrmAuditTrail.recordInTransaction`.
  final Future<void> Function(Session, Transaction, AuditEvent) _appendAudit;

  final Session Function() _session;
  final Transaction? _transaction;

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async {
    await Alert.db.insertRow(
      _session(),
      Alert(
        id: UuidValue.fromString(alert.alertId),
        patientId: UuidValue.fromString(alert.patientId),
        microAreaId: UuidValue.fromString(alert.microAreaId),
        triggeredAt: alert.triggeredAt,
        riskLevel: RiskLevel.red,
        locationHash: alert.locationHash,
        locationCell: alert.locationCell,
        status: AlertStatus.pending,
        mqttTopic: alert.topic,
        deviceId: deviceId,
        retryCount: 0,
        version: 1,
      ),
      transaction: _transaction,
    );
  }

  @override
  Future<RedAlertRecord?> findByIdempotencyKey(String idempotencyKey) async {
    final session = _session();
    final stored = await AlertIdempotencyKey.db.findFirstRow(
      session,
      where: (t) => t.key.equals(idempotencyKey),
      transaction: _transaction,
    );
    if (stored == null) return null;

    final alert = await Alert.db.findById(
      session,
      stored.alertId,
      transaction: _transaction,
    );
    if (alert == null) return null;

    return RedAlertRecord(
      delivery: AlertDelivery(
        alertId: alert.id!.uuid,
        patientId: alert.patientId.uuid,
        microAreaId: alert.microAreaId!.uuid,
        riskLevel: alert.riskLevel.name,
        locationHash: alert.locationHash,
        locationCell: alert.locationCell,
        triggeredAt: alert.triggeredAt,
      ),
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<void> rememberIdempotencyKey(RedAlertRecord record) async {
    await AlertIdempotencyKey.db.insertRow(
      _session(),
      AlertIdempotencyKey(
        key: record.idempotencyKey,
        alertId: UuidValue.fromString(record.delivery.alertId),
        locationHash: record.delivery.locationHash,
        createdAt: DateTime.now().toUtc(),
      ),
      transaction: _transaction,
    );
  }

  @override
  Future<AlertAckRecord?> acknowledge({
    required String alertId,
    required String acsId,
    required String microAreaId,
    required AuditEvent Function(AlertAckOutcome outcome) auditFor,
  }) async {
    final session = _session();
    final alertUuid = UuidValue.fromString(alertId);
    final acsUuid = UuidValue.fromString(acsId);

    Future<AlertAckRecord?> run(Transaction transaction) async {
      // O predicado de microárea é a barreira de territorialização: um ACS
      // nunca confirma alerta fora do seu território (INV-01).
      // Trava antes de ler (#76): um `resolve` concorrente que já gravou
      // `resolved` é visto aqui, em vez de ser sobrescrito por um ACK que leu
      // a linha antes dele.
      final travado = await session.db.unsafeQuery(
        '''
        SELECT id FROM alerts
        WHERE id = @id::uuid AND "microAreaId" = @ma::uuid
        FOR UPDATE
        ''',
        parameters: QueryParameters.named({'id': alertId, 'ma': microAreaId}),
        transaction: transaction,
      );
      if (travado.isEmpty) return null;
      final alert =
          (await Alert.db.findById(session, alertUuid, transaction: transaction))!;

      final now = DateTime.now().toUtc();
      // Lido sob a trava, antes do UPDATE: o desfecho é o que a linha era, não
      // o que o chamador supõe (#86).
      final outcome = switch (alert.status) {
        AlertStatus.resolved => AlertAckOutcome.alreadyResolved,
        AlertStatus.acknowledged => AlertAckOutcome.alreadyAcknowledged,
        AlertStatus.pending || AlertStatus.escalated => AlertAckOutcome.acknowledged,
      };
      // Também lido sob a trava: só o primeiro ACK emite a telemetria
      // `alert_received_acs` (#83).
      final acknowledgedAt = alert.acknowledgedAt ?? now;
      await Alert.db.updateRow(
        session,
        alert.copyWith(
          acsId: acsUuid,
          receivedAt: alert.receivedAt ?? now,
          acknowledgedAt: acknowledgedAt,
          // ACK depois da conclusão (reentrega, outro aparelho) não rebaixa
          // o atendimento já concluído (#76).
          status: alert.status == AlertStatus.resolved
              ? AlertStatus.resolved
              : AlertStatus.acknowledged,
        ),
        // A linha agora é lida sob FOR UPDATE (acima). Restringir às colunas
        // do ACK fica como defesa extra: um UPDATE da linha inteira não pode
        // apagar o escalonamento (#44) nem a conclusão (#76).
        columns: (t) => [t.acsId, t.receivedAt, t.acknowledgedAt, t.status],
        transaction: transaction,
      );

      // Reconfirmação pelo mesmo ACS não duplica a linha de entrega — o par
      // (alertId, acsId) tem índice UNIQUE.
      final already = await AlertDeliveryRecord.db.findFirstRow(
        session,
        where: (t) => t.alertId.equals(alertUuid) & t.acsId.equals(acsUuid),
        transaction: transaction,
      );
      if (already == null) {
        await AlertDeliveryRecord.db.insertRow(
          session,
          AlertDeliveryRecord(
            alertId: alertUuid,
            acsId: acsUuid,
            acknowledgedAt: now,
          ),
          transaction: transaction,
        );
      }

      // Fail-closed: se a trilha falhar, a transação inteira (status incluso)
      // é desfeita. Roda por último, pois o lock da cadeia nunca precede outro.
      await _appendAudit(session, transaction, auditFor(outcome));

      return AlertAckRecord(
        outcome: outcome,
        triggeredAt: alert.triggeredAt,
        acknowledgedAt: acknowledgedAt,
        firstAcknowledgement: alert.acknowledgedAt == null,
      );
    }

    final existing = _transaction;
    return existing != null ? run(existing) : session.db.transaction(run);
  }

  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    // Id que não é UUID é "não existe", não erro de servidor: mesma resposta
    // de um alerta de outra microárea.
    if (!Uuid.isValidUUID(fromString: alertId) ||
        !Uuid.isValidUUID(fromString: microAreaId)) {
      return const AlertResolveAttempt(AlertResolveOutcome.notFound);
    }
    final session = _session();

    Future<AlertResolveAttempt> run(Transaction transaction) async {
      // Escopo e trava numa instrução. O predicado de microárea é a barreira
      // de territorialização (INV-01); o FOR UPDATE serializa com o ACK e com
      // o escalonamento, que releem o status sob a mesma trava.
      final linhas = await session.db.unsafeQuery(
        '''
        SELECT status, "resolvedAt"
        FROM alerts
        WHERE id = @id::uuid AND "microAreaId" = @ma::uuid
        FOR UPDATE
        ''',
        parameters: QueryParameters.named({'id': alertId, 'ma': microAreaId}),
        transaction: transaction,
      );
      if (linhas.isEmpty) {
        return const AlertResolveAttempt(AlertResolveOutcome.notFound);
      }

      final status = linhas.single[0] as String;
      final AlertResolveAttempt attempt;
      if (status == AlertStatus.resolved.name) {
        attempt = AlertResolveAttempt(
          AlertResolveOutcome.alreadyResolved,
          resolvedAt: (linhas.single[1] as DateTime?)?.toUtc(),
        );
      } else if (status != AlertStatus.acknowledged.name) {
        attempt = const AlertResolveAttempt(AlertResolveOutcome.notAcknowledged);
      } else {
        final agora = now.toUtc();
        // Só status e resolvedAt: as colunas do ACK e do escalonamento ficam.
        await session.db.unsafeExecute(
          '''
          UPDATE alerts
          SET status = @resolvido, "resolvedAt" = @agora::timestamp
          WHERE id = @id::uuid
          ''',
          parameters: QueryParameters.named({
            'id': alertId,
            'resolvido': AlertStatus.resolved.name,
            'agora': agora,
          }),
          transaction: transaction,
        );
        attempt = AlertResolveAttempt(AlertResolveOutcome.resolved, resolvedAt: agora);
      }

      // Fail-closed e por último, como no ACK: a trava da cadeia nunca
      // precede outra.
      await _appendAudit(session, transaction, auditFor(attempt.outcome));
      return attempt;
    }

    final existing = _transaction;
    return existing != null ? run(existing) : session.db.transaction(run);
  }

  @override
  Future<AlertStatusSnapshot?> latestForPatient(String patientId) async {
    final row = await Alert.db.findFirstRow(
      _session(),
      where: (t) => t.patientId.equals(UuidValue.fromString(patientId)),
      orderBy: (t) => t.triggeredAt,
      orderDescending: true,
      transaction: _transaction,
    );
    if (row == null) return null;

    return AlertStatusSnapshot(
      alertId: row.id!.uuid,
      riskLevel: row.riskLevel,
      status: row.status,
      triggeredAt: row.triggeredAt,
      acknowledgedAt: row.acknowledgedAt,
      resolvedAt: row.resolvedAt,
    );
  }

  /// Duas consultas em vez de uma ordenação por status: os não confirmados
  /// enchem o teto primeiro, e só o que sobra vai para os confirmados. Cada
  /// grupo é lido do MAIS NOVO para trás e devolvido do mais antigo para a
  /// frente: o corte cai sempre nos antigos, nunca num vermelho recém-chegado
  /// a uma microárea com pendentes acumulados (INV-03).
  @override
  Future<List<OpenAlertSnapshot>> openInMicroArea(String microAreaId, {required int limit}) async {
    final area = UuidValue.fromString(microAreaId);
    final naoConfirmados = await Alert.db.find(
      _session(),
      where: (t) => t.microAreaId.equals(area) & t.status.inSet({AlertStatus.pending, AlertStatus.escalated}),
      orderBy: (t) => t.triggeredAt,
      orderDescending: true,
      limit: limit,
      transaction: _transaction,
    );
    final restante = limit - naoConfirmados.length;
    final confirmados = restante <= 0
        ? const <Alert>[]
        : await Alert.db.find(
            _session(),
            where: (t) => t.microAreaId.equals(area) & t.status.equals(AlertStatus.acknowledged),
            orderBy: (t) => t.triggeredAt,
            orderDescending: true,
            limit: restante,
            transaction: _transaction,
          );

    return [
      for (final row in [...naoConfirmados.reversed, ...confirmados.reversed])
        OpenAlertSnapshot(
          alertId: row.id!.uuid,
          patientId: row.patientId.uuid,
          microAreaId: microAreaId,
          riskLevel: row.riskLevel,
          locationHash: row.locationHash,
          locationCell: row.locationCell,
          triggeredAt: row.triggeredAt,
          status: row.status,
          acknowledgedAt: row.acknowledgedAt,
          escalated: row.escalatedAt != null || row.status == AlertStatus.escalated,
        ),
    ];
  }
}
