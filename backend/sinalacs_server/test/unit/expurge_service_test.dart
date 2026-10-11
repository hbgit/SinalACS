import 'package:sinalacs_server/src/application/retention/expurge_service.dart';
import 'package:test/test.dart';

class _FakeRetentionStore implements RetentionStore {
  _FakeRetentionStore([this.result]);

  ExpurgeCounts? result;
  RetentionCutoffs? received;

  @override
  Future<ExpurgeCounts> purgeDue(RetentionCutoffs cutoffs) async {
    received = cutoffs;
    return result ?? const ExpurgeCounts(
          alerts: 0,
          alertDeliveries: 0,
          alertIdempotencyKeys: 0,
          alertOutbox: 0,
          visits: 0,
          triageSessions: 0,
          alertsByRisk: {},
        );
  }
}

const _counts = ExpurgeCounts(
  alerts: 3,
  alertDeliveries: 2,
  alertIdempotencyKeys: 1,
  alertOutbox: 2,
  visits: 4,
  triageSessions: 5,
  alertsByRisk: {'red': 2, 'yellow': 1},
);

void main() {
  group('RetentionPolicy', () {
    test('calcula os cortes por tabela a partir de agora (UTC)', () {
      final policy = const RetentionPolicy(
        alertsDays: 730,
        visitsDays: 1825,
        triageSessionsDays: 1825,
      );
      final now = DateTime.utc(2026, 10, 7, 12);

      final cutoffs = policy.cutoffsAt(now);

      expect(cutoffs.alerts, DateTime.utc(2024, 10, 7, 12));
      // 1825 dias atrás cruzam o 29/02/2024 (ano bissexto): +1 dia civil.
      expect(cutoffs.visits, DateTime.utc(2021, 10, 8, 12));
      expect(cutoffs.triageSessions, DateTime.utc(2021, 10, 8, 12));
    });

    test('normaliza "agora" para UTC antes de calcular', () {
      final policy = const RetentionPolicy(
        alertsDays: 1,
        visitsDays: 2,
        triageSessionsDays: 3,
      );

      final cutoffs = policy.cutoffsAt(DateTime.utc(2026, 10, 7, 12));

      expect(cutoffs.alerts, DateTime.utc(2026, 10, 6, 12));
      expect(cutoffs.visits, DateTime.utc(2026, 10, 5, 12));
      expect(cutoffs.triageSessions, DateTime.utc(2026, 10, 4, 12));
    });
  });

  group('nextDailyRun', () {
    test('antes das 03:00 UTC: a janela de hoje', () {
      expect(
        nextDailyRun(DateTime.utc(2026, 10, 7, 2, 59)),
        DateTime.utc(2026, 10, 7, 3),
      );
    });

    test('exatamente às 03:00 UTC: a janela de amanhã (não reprocessa agora)', () {
      expect(
        nextDailyRun(DateTime.utc(2026, 10, 7, 3)),
        DateTime.utc(2026, 10, 8, 3),
      );
    });

    test('depois das 03:00 UTC: a janela de amanhã', () {
      expect(
        nextDailyRun(DateTime.utc(2026, 10, 7, 23)),
        DateTime.utc(2026, 10, 8, 3),
      );
    });

    test('virada de mês e de ano acontece naturalmente', () {
      expect(
        nextDailyRun(DateTime.utc(2026, 12, 31, 4)),
        DateTime.utc(2027, 1, 1, 3),
      );
    });
  });

  group('ExpurgeService', () {
    test('passa os cortes da política ao store e devolve o resultado', () async {
      final store = _FakeRetentionStore(_counts);
      final service = ExpurgeService(
        store: store,
        policy: const RetentionPolicy(
          alertsDays: 730,
          visitsDays: 1825,
          triageSessionsDays: 1825,
        ),
        clock: () => DateTime.utc(2026, 10, 7, 12),
      );

      final result = await service.run();

      expect(store.received?.alerts, DateTime.utc(2024, 10, 7, 12));
      expect(result.counts, same(_counts));
      expect(result.ranAtUtc, DateTime.utc(2026, 10, 7, 12));
    });
  });

  group('ExpurgeResult.describe', () {
    test('devolve contagens e cortes, sem dado de paciente', () {
      final policy = const RetentionPolicy(
        alertsDays: 730,
        visitsDays: 1825,
        triageSessionsDays: 1825,
      );
      final result = ExpurgeResult(
        ranAtUtc: DateTime.utc(2026, 10, 7, 3),
        cutoffs: policy.cutoffsAt(DateTime.utc(2026, 10, 7, 3)),
        counts: _counts,
      );

      final line = result.describe();

      expect(line, contains('alertas=3'));
      expect(line, contains('risco: red=2, yellow=1'));
      expect(line, contains('entregas=2'));
      expect(line, contains('idempotencia=1'));
      expect(line, contains('outbox=2'));
      expect(line, contains('visitas=4'));
      expect(line, contains('triagens=5'));
      expect(line, contains('cortes:'));
    });
  });
}
