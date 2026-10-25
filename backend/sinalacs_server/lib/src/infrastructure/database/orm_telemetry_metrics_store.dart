import 'package:postgres/postgres.dart' as pg;
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_metrics.dart';

/// Executa um SQL com parâmetros nomeados (`@nome`) e devolve as linhas como
/// mapas de coluna.
typedef _Query =
    Future<List<Map<String, dynamic>>> Function(
      String sql,
      Map<String, Object?> params,
    );

/// [TelemetryMetricsStore] sobre SQL parametrizado (#83).
///
/// O mesmo SQL serve ao servidor (sessão do Serverpod) e à CLI de operação
/// `bin/telemetry_report.dart` (conexão direta do pacote `postgres`, como em
/// `bin/issue_staff_activation_code.dart`). As datas vão como texto ISO sem
/// fuso e viram `timestamp` no SQL: as colunas guardam UTC sem fuso, e assim o
/// `TimeZone` da sessão do Postgres não desloca a janela.
class OrmTelemetryMetricsStore implements TelemetryMetricsStore {
  OrmTelemetryMetricsStore(Session session)
    : _query = ((sql, params) async {
        final rows = await session.db.unsafeQuery(
          sql,
          parameters: QueryParameters.named(params),
        );
        return [for (final r in rows) r.toColumnMap()];
      });

  OrmTelemetryMetricsStore.postgres(pg.Session db)
    : _query = ((sql, params) async {
        final rows = await db.execute(pg.Sql.named(sql), parameters: params);
        return [for (final r in rows) r.toColumnMap()];
      });

  final _Query _query;

  /// Tentativas da janela, cada uma com no máximo um resultado (o mais
  /// recente, se o app reenviou) — um resultado repetido não infla a soma.
  static const _attemptsSql = '''
SELECT count(*)::bigint AS attempts,
       count(r.success)::bigint AS with_result,
       COALESCE(sum(a.records) FILTER (WHERE r.success IS NOT NULL), 0)::bigint AS records_attempted,
       COALESCE(sum(r.success), 0)::bigint AS records_succeeded
FROM (
  SELECT "eventId", (payload::jsonb->>'records_count')::bigint AS records
  FROM telemetry_events
  WHERE "eventName" = 'sync_attempt'
    AND "occurredAt" >= @from::timestamp AND "occurredAt" < @to::timestamp
) a
LEFT JOIN LATERAL (
  SELECT (t.payload::jsonb->>'success_count')::bigint AS success
  FROM telemetry_events t
  WHERE t."eventName" = 'sync_result'
    AND (t.payload::jsonb->>'attempt_event_id')::uuid = a."eventId"
  ORDER BY t."occurredAt" DESC, t.id DESC
  LIMIT 1
) r ON true''';

  static const _visitsSql = '''
SELECT count(*)::bigint AS registered,
       count(v."localId")::bigint AS synced
FROM telemetry_events t
LEFT JOIN visits v ON v."localId" = (t.payload::jsonb->>'local_id')::uuid
WHERE t."eventName" = 'visit_registered'
  AND t."occurredAt" >= @from::timestamp AND t."occurredAt" < @to::timestamp''';

  /// As medianas passam por `::numeric` antes do `round`: em `double
  /// precision` o Postgres arredonda metade para o par (1000,5 → 1000).
  ///
  /// H1: o `occurredAt` é relógio do aparelho; somar `clockSkewMs`
  /// (`receivedAt − sentAt`) o traz para o relógio do servidor, o mesmo de
  /// `alerts."triggeredAt"`.
  static const _alertToVisitSql = '''
SELECT count(*)::bigint AS n,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM
         (t."occurredAt" + COALESCE(t."clockSkewMs", 0) * interval '1 millisecond')
         - a."triggeredAt"))::numeric)::bigint AS median_s
FROM telemetry_events t
JOIN alerts a ON a.id = t."alertId"
WHERE t."eventName" = 'visit_registered'
  AND t."occurredAt" >= @from::timestamp AND t."occurredAt" < @to::timestamp''';

  static const _ackSql = '''
SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY
         (payload::jsonb->>'latency_ms')::bigint)::numeric)::bigint AS median_ms
FROM telemetry_events
WHERE "eventName" = 'alert_received_acs'
  AND "occurredAt" >= @from::timestamp AND "occurredAt" < @to::timestamp''';

  @override
  Future<TelemetryReport> report({
    required DateTime from,
    required DateTime to,
  }) async {
    final params = {'from': _ts(from), 'to': _ts(to)};
    final a = (await _query(_attemptsSql, params)).single;
    final v = (await _query(_visitsSql, params)).single;
    final h1 = (await _query(_alertToVisitSql, params)).single;
    final ack = (await _query(_ackSql, params)).single;

    final attempts = a['attempts'] as int;
    final withResult = a['with_result'] as int;
    final recordsAttempted = a['records_attempted'] as int;
    final recordsSucceeded = a['records_succeeded'] as int;
    final registered = v['registered'] as int;
    final synced = v['synced'] as int;

    return TelemetryReport(
      attempts: attempts,
      attemptsWithResult: withResult,
      interruptedAttempts: attempts - withResult,
      recordsAttempted: recordsAttempted,
      recordsSucceeded: recordsSucceeded,
      perAttemptSuccessRate: recordsAttempted == 0
          ? null
          : recordsSucceeded / recordsAttempted,
      registeredVisits: registered,
      registeredVisitsSynced: synced,
      eventualSyncRate: registered == 0 ? null : synced / registered,
      alertLinkedVisits: h1['n'] as int,
      medianAlertToVisitSeconds: h1['median_s'] as int?,
      medianAckLatencyMs: ack['median_ms'] as int?,
    );
  }

  /// UTC em ISO sem o `Z`, para o cast `::timestamp` não depender do fuso.
  static String _ts(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('Z', '');
}
