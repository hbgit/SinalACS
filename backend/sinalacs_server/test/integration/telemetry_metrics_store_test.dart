import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_telemetry_metrics_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_telemetry_store.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Métricas do PRD §1.3 calculadas a partir de `telemetry_events` (#83),
/// contra Postgres real. Dados sintéticos apenas (LGPD).
const _patientId = '00000000-0000-4000-8000-0000000000e1';

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _from = DateTime.utc(2026, 10, 1);
final _to = DateTime.utc(2026, 11, 1);
final _t = DateTime.utc(2026, 10, 15, 12);

TelemetryRecord _ev(
  int n,
  String name,
  Map<String, Object?> payload, {
  DateTime? at,
  int? skewMs,
  String? alertId,
}) => TelemetryRecord(
  eventId: _id(n),
  eventName: name,
  source: TelemetrySource.acsApp,
  occurredAt: at ?? _t,
  receivedAt: at ?? _t,
  clockSkewMs: skewMs,
  alertId: alertId,
  appVersion: '1.0.0',
  payload: payload,
);

TelemetryRecord _attempt(int n, int records, {DateTime? at}) => _ev(
  n,
  'sync_attempt',
  {'records_count': records, 'network_type': 'wifi', 'channel': 'sync'},
  at: at,
);

TelemetryRecord _result(int n, int attempt, int success, {DateTime? at}) => _ev(
  n,
  'sync_result',
  {
    'attempt_event_id': _id(attempt),
    'success_count': success,
    'failure_count': 0,
    'conflict_count': 0,
    'rejected_count': 0,
    'outcome': 'synced',
    'transport_error': false,
    'duration_ms': 120,
  },
  at: at,
);

TelemetryRecord _visit(
  int n,
  String localId, {
  String? alertId,
  DateTime? at,
  int? skewMs,
}) => _ev(
  n,
  'visit_registered',
  {
    'local_id': localId,
    'visit_type': alertId == null ? 'routine' : 'alert',
    'alert_id': ?alertId,
    'offline_flag': true,
    'network_type': 'none',
    'sync_status': 'queued',
  },
  at: at,
  skewMs: skewMs,
  alertId: alertId,
);

Future<void> _seedPatient(Session session) async {
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'metricas-paciente',
      name: 'Paciente Métricas',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      createdAt: _t,
      updatedAt: _t,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato métricas',
      isChronic: false,
    ),
  );
}

Future<void> _seedVisit(Session session, String localId) => Visit.db.insertRow(
  session,
  Visit(
    patientId: UuidValue.fromString(_patientId),
    scheduledAt: _t,
    status: 'realizada',
    syncStatus: SyncStatus.synced,
    localId: UuidValue.fromString(localId),
    version: 1,
  ),
);

Future<String> _seedAlert(Session session, DateTime triggeredAt) async {
  final a = await Alert.db.insertRow(
    session,
    Alert(
      patientId: UuidValue.fromString(_patientId),
      triggeredAt: triggeredAt,
      riskLevel: RiskLevel.red,
      locationHash: 'hash-metricas',
      status: AlertStatus.acknowledged,
      mqttTopic: 'sinalacs/v1/alerts/metricas',
      deviceId: 'device-metricas',
      retryCount: 0,
      version: 0,
    ),
  );
  return a.id!.uuid;
}

void main() {
  withServerpod('OrmTelemetryMetricsStore', (sessionBuilder, _) {
    late Session session;
    late OrmTelemetryMetricsStore metrics;

    Future<void> gravar(List<TelemetryRecord> r) =>
        OrmTelemetryStore(session).insertIgnoringDuplicates(r);

    setUp(() {
      session = sessionBuilder.build();
      metrics = OrmTelemetryMetricsStore(session);
    });

    test('taxa por tentativa = sucesso/registros', () async {
      await gravar([
        _attempt(1, 10),
        _result(2, 1, 7),
        _attempt(3, 10),
        _result(4, 3, 10),
        // Fora da janela: não conta, nem o resultado ligado a ela.
        _attempt(5, 50, at: DateTime.utc(2026, 9, 30)),
        _result(6, 5, 0),
      ]);

      final r = await metrics.report(from: _from, to: _to);

      expect(r.attempts, 2);
      expect(r.attemptsWithResult, 2);
      expect(r.interruptedAttempts, 0);
      expect(r.recordsAttempted, 20);
      expect(r.recordsSucceeded, 17);
      expect(r.perAttemptSuccessRate, closeTo(0.85, 1e-9));
    });

    test(
      'resultado fora da janela conta para a tentativa dentro dela',
      () async {
        await gravar([
          _attempt(1, 4, at: DateTime.utc(2026, 10, 31, 23, 59)),
          _result(2, 1, 4, at: DateTime.utc(2026, 11, 1, 0, 1)),
        ]);

        final r = await metrics.report(from: _from, to: _to);

        expect(r.attemptsWithResult, 1);
        expect(r.recordsSucceeded, 4);
        expect(r.perAttemptSuccessRate, 1.0);
      },
    );

    test(
      'dois sync_result da mesma tentativa não inflam recordsSucceeded',
      () async {
        await gravar([
          _attempt(1, 10),
          _result(2, 1, 4, at: DateTime.utc(2026, 10, 10, 12, 0, 1)),
          // Reenvio do app: vale o mais recente, e só ele.
          _result(3, 1, 7, at: DateTime.utc(2026, 10, 10, 12, 0, 2)),
        ]);

        final r = await metrics.report(from: _from, to: _to);

        expect(r.attempts, 1);
        expect(r.attemptsWithResult, 1);
        expect(r.recordsAttempted, 10);
        expect(r.recordsSucceeded, 7);
        expect(r.perAttemptSuccessRate, closeTo(0.7, 1e-9));
      },
    );

    test(
      'tentativa sem resultado conta como interrompida, não como sucesso',
      () async {
        await gravar([
          _attempt(1, 10),
          _result(2, 1, 5),
          // App morto entre o sync_attempt e o sync_result.
          _attempt(3, 30),
        ]);

        final r = await metrics.report(from: _from, to: _to);

        expect(r.attempts, 2);
        expect(r.attemptsWithResult, 1);
        expect(r.interruptedAttempts, 1);
        // A órfã fica fora do denominador e do numerador.
        expect(r.recordsAttempted, 10);
        expect(r.recordsSucceeded, 5);
        expect(r.perAttemptSuccessRate, closeTo(0.5, 1e-9));
      },
    );

    test('só tentativas interrompidas dão taxa nula, não zero', () async {
      await gravar([_attempt(1, 10)]);

      final r = await metrics.report(from: _from, to: _to);

      expect(r.interruptedAttempts, 1);
      expect(r.perAttemptSuccessRate, isNull);
    });

    test('taxa final junta visit_registered com visits.localId', () async {
      await _seedPatient(session);
      await _seedVisit(session, _id(901));
      await _seedVisit(session, _id(902));
      await gravar([
        _visit(1, _id(901)),
        _visit(2, _id(902)),
        _visit(3, _id(903)), // nunca chegou ao servidor
        _visit(4, _id(904)), // idem
      ]);

      final r = await metrics.report(from: _from, to: _to);

      expect(r.registeredVisits, 4);
      expect(r.registeredVisitsSynced, 2);
      expect(r.eventualSyncRate, closeTo(0.5, 1e-9));
    });

    test('mediana alerta→visita corrige pelo clockSkewMs', () async {
      await _seedPatient(session);
      final disparo = DateTime.utc(2026, 10, 15, 10);
      final a1 = await _seedAlert(session, disparo);
      final a2 = await _seedAlert(session, disparo);
      final a3 = await _seedAlert(session, disparo);
      await gravar([
        // Relógio do aparelho 5 min atrasado: 10 min no aparelho + 5 min = 15.
        _visit(
          1,
          _id(901),
          alertId: a1,
          at: disparo.add(const Duration(minutes: 10)),
          skewMs: 300000,
        ),
        // Sem desvio conhecido: 20 min.
        _visit(
          2,
          _id(902),
          alertId: a2,
          at: disparo.add(const Duration(minutes: 20)),
        ),
        // Relógio 2 min adiantado: 32 min no aparelho − 2 = 30.
        _visit(
          3,
          _id(903),
          alertId: a3,
          at: disparo.add(const Duration(minutes: 32)),
          skewMs: -120000,
        ),
        // Visita de rotina: fora da amostra.
        _visit(4, _id(904)),
      ]);

      final r = await metrics.report(from: _from, to: _to);

      expect(r.alertLinkedVisits, 3);
      // Sem a correção, a mediana seria 20 min do mesmo jeito; a amostra de
      // um elemento abaixo prova o ajuste isoladamente.
      expect(r.medianAlertToVisitSeconds, 20 * 60);

      final so = await metrics.report(
        from: disparo.add(const Duration(minutes: 9)),
        to: disparo.add(const Duration(minutes: 11)),
      );
      expect(so.alertLinkedVisits, 1);
      expect(so.medianAlertToVisitSeconds, 15 * 60);
    });

    test('mediana da latência do ACK', () async {
      await gravar([
        for (final (n, ms) in [(1, 800), (2, 1500), (3, 1201), (4, 300)])
          _ev(n, 'alert_received_acs', {'latency_ms': ms, 'channel': 'rpc'}),
      ]);

      final r = await metrics.report(from: _from, to: _to);

      // percentile_cont(0.5) de {300, 800, 1201, 1500} = 1000.5 → 1001.
      expect(r.medianAckLatencyMs, 1001);
    });

    test('janela sem eventos devolve nulos', () async {
      final r = await metrics.report(from: _from, to: _to);

      expect(r.attempts, 0);
      expect(r.attemptsWithResult, 0);
      expect(r.interruptedAttempts, 0);
      expect(r.recordsAttempted, 0);
      expect(r.recordsSucceeded, 0);
      expect(r.perAttemptSuccessRate, isNull);
      expect(r.registeredVisits, 0);
      expect(r.registeredVisitsSynced, 0);
      expect(r.eventualSyncRate, isNull);
      expect(r.alertLinkedVisits, 0);
      expect(r.medianAlertToVisitSeconds, isNull);
      expect(r.medianAckLatencyMs, isNull);
      expect(r.toJson(), {
        'attempts': 0,
        'attemptsWithResult': 0,
        'interruptedAttempts': 0,
        'recordsAttempted': 0,
        'recordsSucceeded': 0,
        'perAttemptSuccessRate': null,
        'registeredVisits': 0,
        'registeredVisitsSynced': 0,
        'eventualSyncRate': null,
        'alertLinkedVisits': 0,
        'medianAlertToVisitSeconds': null,
        'medianAckLatencyMs': null,
      });
    });
  });
}
