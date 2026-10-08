import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/retention/expurge_service.dart';

/// Implementação de [RetentionStore] sobre SQL cru.
///
/// O lote de DELETEs não tem equivalente expressivo no ORM (subquery `IN` +
/// `COALESCE`), e o SQL cru mantém contagem + remoção numa ÚNICA transação,
/// sob advisory lock — duas rodadas concorrentes (ou um boot duplicado) não
/// podem contar+deletar ao mesmo tempo.
class OrmRetentionStore implements RetentionStore {
  OrmRetentionStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  /// Chave própria do advisory lock do expurgo — irmã da de `OrmAuditTrail`,
  /// mas independente: expurgo e apêndice de auditoria não se serializam.
  static const _expurgeLockKey = 725100824;

  @override
  Future<ExpurgeCounts> purgeDue(RetentionCutoffs cutoffs) async {
    final session = _session();
    return session.db.transaction((transaction) async {
      await session.db.unsafeExecute(
        'SELECT pg_advisory_xact_lock(@key);',
        parameters: QueryParameters.named({'key': _expurgeLockKey}),
        transaction: transaction,
      );

      // B3: contagens ANTES dos DELETEs — são o único resíduo do que saiu.
      final counts = ExpurgeCounts(
        alerts: await _count(
          'SELECT COUNT(*) FROM alerts WHERE "triggeredAt" < @cutoff',
          cutoffs.alerts,
          transaction,
        ),
        alertDeliveries: await _count(
          'SELECT COUNT(*) FROM alert_deliveries WHERE "alertId" IN '
          '(SELECT id FROM alerts WHERE "triggeredAt" < @cutoff)',
          cutoffs.alerts,
          transaction,
        ),
        alertIdempotencyKeys: await _count(
          'SELECT COUNT(*) FROM alert_idempotency_keys WHERE "alertId" IN '
          '(SELECT id FROM alerts WHERE "triggeredAt" < @cutoff)',
          cutoffs.alerts,
          transaction,
        ),
        alertOutbox: await _count(
          'SELECT COUNT(*) FROM alert_outbox WHERE "alertId" IN '
          '(SELECT id FROM alerts WHERE "triggeredAt" < @cutoff)',
          cutoffs.alerts,
          transaction,
        ),
        visits: await _count(
          'SELECT COUNT(*) FROM visits '
          'WHERE COALESCE("completedAt", "scheduledAt") < @cutoff',
          cutoffs.visits,
          transaction,
        ),
        triageSessions: await _count(
          'SELECT COUNT(*) FROM triage_sessions WHERE "createdAt" < @cutoff',
          cutoffs.triageSessions,
          transaction,
        ),
        alertsByRisk: await _alertsByRisk(cutoffs.alerts, transaction),
      );

      // Ordem importa: as FKs dos dependentes de alerts são ON DELETE NO
      // ACTION, então saem antes do alerta pai.
      await _delete(
        'DELETE FROM alert_deliveries WHERE "alertId" IN '
        '(SELECT id FROM alerts WHERE "triggeredAt" < @cutoff)',
        cutoffs.alerts,
        transaction,
      );
      await _delete(
        'DELETE FROM alert_idempotency_keys WHERE "alertId" IN '
        '(SELECT id FROM alerts WHERE "triggeredAt" < @cutoff)',
        cutoffs.alerts,
        transaction,
      );
      await _delete(
        'DELETE FROM alert_outbox WHERE "alertId" IN '
        '(SELECT id FROM alerts WHERE "triggeredAt" < @cutoff)',
        cutoffs.alerts,
        transaction,
      );
      await _delete(
        'DELETE FROM alerts WHERE "triggeredAt" < @cutoff',
        cutoffs.alerts,
        transaction,
      );
      // Visitas: `completedAt` quando existe (data real do cuidado), senão
      // `scheduledAt` (NOT NULL) — nenhuma linha escapa por NULL.
      await _delete(
        'DELETE FROM visits '
        'WHERE COALESCE("completedAt", "scheduledAt") < @cutoff',
        cutoffs.visits,
        transaction,
      );
      await _delete(
        'DELETE FROM triage_sessions WHERE "createdAt" < @cutoff',
        cutoffs.triageSessions,
        transaction,
      );

      return counts;
    });
  }

  Future<int> _count(
    String sql,
    DateTime cutoff,
    Transaction transaction,
  ) async {
    final rows = await _session().db.unsafeQuery(
      sql,
      parameters: QueryParameters.named({'cutoff': cutoff}),
      transaction: transaction,
    );
    return rows.single.single as int;
  }

  Future<int> _delete(
    String sql,
    DateTime cutoff,
    Transaction transaction,
  ) =>
      _session().db.unsafeExecute(
        sql,
        parameters: QueryParameters.named({'cutoff': cutoff}),
        transaction: transaction,
      );

  Future<Map<String, int>> _alertsByRisk(
    DateTime cutoff,
    Transaction transaction,
  ) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT "riskLevel", COUNT(*) FROM alerts '
      'WHERE "triggeredAt" < @cutoff GROUP BY "riskLevel"',
      parameters: QueryParameters.named({'cutoff': cutoff}),
      transaction: transaction,
    );
    return {for (final row in rows) row[0] as String: row[1] as int};
  }
}
