/// Política de retenção (LGPD-RF07).
///
/// Os valores vêm do `AppConfig` (`RETENTION_*_DAYS`, com defaults na tabela
/// de retenção de spec/lgpd_design.md §5.6: alertas 2 anos; visitas e triagens
/// 5 anos). Esta classe só carrega os prazos e calcula os cortes — a validação
/// de inteiro positivo fica no `AppConfig`, que é quem lê o ambiente.
class RetentionPolicy {
  const RetentionPolicy({
    required this.alertsDays,
    required this.visitsDays,
    required this.triageSessionsDays,
  })  : assert(alertsDays > 0),
        assert(visitsDays > 0),
        assert(triageSessionsDays > 0);

  /// Retenção de `alerts`, em dias.
  final int alertsDays;

  /// Retenção de `visits`, em dias.
  final int visitsDays;

  /// Retenção de `triage_sessions`, em dias.
  final int triageSessionsDays;

  /// Os instantes-limite por tabela: linhas anteriores a estes cortes estão
  /// vencidas e são candidatas ao expurgo.
  RetentionCutoffs cutoffsAt(DateTime nowUtc) {
    final now = nowUtc.toUtc();
    return RetentionCutoffs(
      alerts: now.subtract(Duration(days: alertsDays)),
      visits: now.subtract(Duration(days: visitsDays)),
      triageSessions: now.subtract(Duration(days: triageSessionsDays)),
    );
  }
}

/// Os cortes por tabela, calculados por [RetentionPolicy.cutoffsAt].
class RetentionCutoffs {
  const RetentionCutoffs({
    required this.alerts,
    required this.visits,
    required this.triageSessions,
  });

  final DateTime alerts;
  final DateTime visits;
  final DateTime triageSessions;
}

/// Contagens do expurgo, apuradas ANTES dos DELETEs (decisão B3): são o único
/// resíduo operacional que sobra do que foi removido, e vão para o log da
/// rotina — a trilha de auditoria em si (`audit_logs`) não é tocada.
class ExpurgeCounts {
  const ExpurgeCounts({
    required this.alerts,
    required this.alertDeliveries,
    required this.alertIdempotencyKeys,
    required this.alertOutbox,
    required this.visits,
    required this.triageSessions,
    required this.alertsByRisk,
  });

  final int alerts;
  final int alertDeliveries;
  final int alertIdempotencyKeys;
  final int alertOutbox;
  final int visits;
  final int triageSessions;

  /// `alerts` desdobrados por `riskLevel` — a parte "série epidemiológica" que
  /// a contagem preserva antes do DELETE físico.
  final Map<String, int> alertsByRisk;
}

/// Persistência do expurgo: conta e remove as linhas vencidas de forma
/// atômica. A implementação ORM faz tudo numa única transação sob advisory
/// lock.
abstract interface class RetentionStore {
  Future<ExpurgeCounts> purgeDue(RetentionCutoffs cutoffs);
}

/// Resultado de uma rodada, pronto para o log operacional (decisão C1).
class ExpurgeResult {
  const ExpurgeResult({
    required this.ranAtUtc,
    required this.cutoffs,
    required this.counts,
  });

  final DateTime ranAtUtc;
  final RetentionCutoffs cutoffs;
  final ExpurgeCounts counts;

  /// A linha do log operacional — nunca carrega dado de paciente, só contagens
  /// e cortes (a regra de sanitização VAZ-01 vale também aqui).
  String describe() {
    final porRisco = counts.alertsByRisk.isEmpty
        ? 'nenhum'
        : counts.alertsByRisk.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(', ');
    return 'alertas=${counts.alerts} (risco: $porRisco), '
        'entregas=${counts.alertDeliveries}, '
        'idempotencia=${counts.alertIdempotencyKeys}, '
        'outbox=${counts.alertOutbox}, '
        'visitas=${counts.visits}, '
        'triagens=${counts.triageSessions}; '
        'cortes: alertas<${cutoffs.alerts.toIso8601String()}, '
        'visitas<${cutoffs.visits.toIso8601String()}, '
        'triagens<${cutoffs.triageSessions.toIso8601String()}';
  }
}

/// Rotina de retenção (LGPD-RF07): calcula os cortes e delega a contagem +
/// remoção ao [RetentionStore].
///
/// DELETE físico (decisão B1): o requisito aceita "anonimizados **ou
/// eliminados** de forma segura" (lgpd_design §143; RT09), e o schema não
/// permite anonimização in-place sem migração (`patientId` é FK NOT NULL) —
/// decisões e evolução em spec/lgpd_data_audit_action.md §4.
class ExpurgeService {
  ExpurgeService({
    required RetentionStore store,
    required RetentionPolicy policy,
    DateTime Function()? clock,
  })  : _store = store,
        _policy = policy,
        _clock = clock ?? DateTime.now;

  final RetentionStore _store;
  final RetentionPolicy _policy;
  final DateTime Function() _clock;

  Future<ExpurgeResult> run() async {
    final nowUtc = _clock().toUtc();
    final cutoffs = _policy.cutoffsAt(nowUtc);
    final counts = await _store.purgeDue(cutoffs);
    return ExpurgeResult(ranAtUtc: nowUtc, cutoffs: cutoffs, counts: counts);
  }
}

/// Próxima execução diária às [hourUtc] horas UTC: hoje, se essa hora ainda
/// não passou; senão amanhã. Pura — testável com relógio fixo.
DateTime nextDailyRun(DateTime nowUtc, {int hourUtc = 3}) {
  final now = nowUtc.toUtc();
  final today = DateTime.utc(now.year, now.month, now.day, hourUtc);
  return today.isAfter(now)
      ? today
      : DateTime.utc(now.year, now.month, now.day + 1, hourUtc);
}
