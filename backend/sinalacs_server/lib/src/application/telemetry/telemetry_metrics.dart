/// Métricas do PRD §1.3 calculadas a partir de `telemetry_events` (#83).
///
/// A janela `[from, to)` vale pelo `occurredAt` do evento-base de cada
/// métrica: `sync_attempt` para as taxas de tentativa, `visit_registered` para
/// a taxa final e para H1, `alert_received_acs` para o ACK. Sem amostra, a
/// taxa ou a mediana é `null`, nunca `0` (mesmo critério do TMRAV).
class TelemetryReport {
  const TelemetryReport({
    required this.attempts,
    required this.attemptsWithResult,
    required this.interruptedAttempts,
    required this.recordsAttempted,
    required this.recordsSucceeded,
    required this.perAttemptSuccessRate,
    required this.registeredVisits,
    required this.registeredVisitsSynced,
    required this.eventualSyncRate,
    required this.alertLinkedVisits,
    required this.medianAlertToVisitSeconds,
    required this.medianAckLatencyMs,
  });

  /// `sync_attempt` na janela.
  final int attempts;

  /// Tentativas da janela com um `sync_result` ligado por `attempt_event_id`,
  /// mesmo que o resultado tenha caído fora da janela.
  final int attemptsWithResult;

  /// Tentativas sem `sync_result` (app morto no meio): nunca contam como
  /// sucesso nem entram na taxa por tentativa.
  final int interruptedAttempts;

  /// Σ `records_count` das tentativas **com resultado**: o denominador de
  /// [perAttemptSuccessRate]. As interrompidas ficam de fora.
  final int recordsAttempted;

  /// Σ `success_count` dos resultados dessas tentativas.
  final int recordsSucceeded;

  /// [recordsSucceeded] / [recordsAttempted] (RNF02/H4); `null` sem denominador.
  final double? perAttemptSuccessRate;

  /// `visit_registered` na janela.
  final int registeredVisits;

  /// Desses, os que têm `local_id` em `visits."localId"` (chegaram ao servidor).
  final int registeredVisitsSynced;

  /// [registeredVisitsSynced] / [registeredVisits]; `null` sem denominador.
  final double? eventualSyncRate;

  /// `visit_registered` com `alertId` de um alerta existente: a amostra de H1.
  final int alertLinkedVisits;

  /// Mediana (H1) de `occurredAt + clockSkewMs − alerts.triggeredAt`, em
  /// segundos inteiros.
  final int? medianAlertToVisitSeconds;

  /// Mediana de `latency_ms` dos `alert_received_acs`, em ms inteiros.
  final int? medianAckLatencyMs;

  Map<String, Object?> toJson() => {
    'attempts': attempts,
    'attemptsWithResult': attemptsWithResult,
    'interruptedAttempts': interruptedAttempts,
    'recordsAttempted': recordsAttempted,
    'recordsSucceeded': recordsSucceeded,
    'perAttemptSuccessRate': perAttemptSuccessRate,
    'registeredVisits': registeredVisits,
    'registeredVisitsSynced': registeredVisitsSynced,
    'eventualSyncRate': eventualSyncRate,
    'alertLinkedVisits': alertLinkedVisits,
    'medianAlertToVisitSeconds': medianAlertToVisitSeconds,
    'medianAckLatencyMs': medianAckLatencyMs,
  };
}

/// Porta de leitura das métricas de telemetria.
abstract interface class TelemetryMetricsStore {
  Future<TelemetryReport> report({required DateTime from, required DateTime to});
}
