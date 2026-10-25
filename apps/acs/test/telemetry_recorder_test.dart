import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_recorder.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';

const _owner = 'acs-001';
const _patient = '11111111-1111-4111-8111-111111111111';
const _alert = '22222222-2222-4222-8222-222222222222';

class _ThrowingStore implements TelemetryStore {
  @override
  Future<void> append(TelemetryEventRecord e) async => throw StateError('disco cheio');
  @override
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}) async => [];
  @override
  Future<void> deleteByIds(Iterable<String> ids) async {}
  @override
  Future<int> countForOwner(String owner) async => 0;
}

TelemetryRecorder _rec(TelemetryStore s, NetworkKind k) => TelemetryRecorder(
      store: s,
      owner: _owner,
      probe: () async => k,
      clock: () => DateTime.utc(2026, 10, 25, 12, 0, 0, 123, 456),
    );

Future<List<TelemetryEventRecord>> _all(TelemetryStore s) => s.oldestForOwner(_owner, limit: 100);

void main() {
  test('syncAttempt grava records_count e network_type e devolve o id', () async {
    final s = InMemoryTelemetryStore();
    final id = await _rec(s, NetworkKind.wifi).syncAttempt(recordsCount: 3);
    final e = (await _all(s)).single;
    expect(e.eventId, id);
    expect(e.name, 'sync_attempt');
    expect(e.payload, {'records_count': 3, 'network_type': 'wifi', 'channel': 'sync'});
    expect(e.occurredAt.isUtc, isTrue);
    expect(e.occurredAt.microsecond, 0);
  });

  test('syncAttempt com lote vazio não grava', () async {
    final s = InMemoryTelemetryStore();
    expect(await _rec(s, NetworkKind.wifi).syncAttempt(recordsCount: 0), isNull);
    expect(await _all(s), isEmpty);
  });

  test('syncResult liga attempt_event_id', () async {
    final s = InMemoryTelemetryStore();
    final r = _rec(s, NetworkKind.mobile);
    final id = await r.syncAttempt(recordsCount: 2);
    await r.syncResult(
      attemptEventId: id,
      successCount: 1,
      failureCount: 0,
      conflictCount: 1,
      rejectedCount: 0,
      outcome: 'conflict',
      transportError: false,
      duration: const Duration(milliseconds: 250),
    );
    final e = (await _all(s)).last;
    expect(e.name, 'sync_result');
    expect(e.payload, {
      'attempt_event_id': id,
      'success_count': 1,
      'failure_count': 0,
      'conflict_count': 1,
      'rejected_count': 0,
      'outcome': 'conflict',
      'transport_error': false,
      'duration_ms': 250,
    });
  });

  test('syncResult sem attemptEventId não grava', () async {
    final s = InMemoryTelemetryStore();
    await _rec(s, NetworkKind.wifi).syncResult(
      attemptEventId: null,
      successCount: 0,
      failureCount: 0,
      conflictCount: 0,
      rejectedCount: 0,
      outcome: 'error',
      transportError: true,
      duration: Duration.zero,
    );
    expect(await _all(s), isEmpty);
  });

  test('visitRegistered de alerta leva alert_id; de rotina não', () async {
    final s = InMemoryTelemetryStore();
    final r = _rec(s, NetworkKind.wifi);
    final v = OfflineVisitRecord(patientId: _patient, risk: 'red', status: 'done');
    await r.visitRegistered(visit: v, alertId: _alert);
    await r.visitRegistered(visit: v);
    final es = await _all(s);
    expect(es[0].payload, {
      'local_id': v.localId,
      'patient_id': _patient,
      'visit_type': 'alert',
      'alert_id': _alert,
      'offline_flag': false,
      'network_type': 'wifi',
      'sync_status': 'queued',
    });
    expect(es[1].payload.containsKey('alert_id'), isFalse);
    expect(es[1].payload['visit_type'], 'routine');
  });

  test('offline_flag acompanha a sonda', () async {
    for (final (k, off) in [
      (NetworkKind.none, true),
      (NetworkKind.mobile, false),
      (NetworkKind.unknown, false),
    ]) {
      final s = InMemoryTelemetryStore();
      await _rec(s, k).visitRegistered(
          visit: OfflineVisitRecord(patientId: _patient, risk: 'red', status: 'done'));
      final p = (await _all(s)).single.payload;
      expect(p['offline_flag'], off);
      expect(p['network_type'], k.wireName);
    }
  });

  test('store lançando e sonda lançando não propagam', () async {
    final r = _rec(_ThrowingStore(), NetworkKind.wifi);
    expect(await r.syncAttempt(recordsCount: 1), isNull);
    await r.visitRegistered(
        visit: OfflineVisitRecord(patientId: _patient, risk: 'red', status: 'done'));
    final s = InMemoryTelemetryStore();
    final r2 = TelemetryRecorder(store: s, owner: _owner, probe: () async => throw Exception('x'));
    await r2.syncAttempt(recordsCount: 1);
    expect((await _all(s)).single.payload['network_type'], 'unknown');
  });

  test('payload nunca contém notes nem outcome da visita', () async {
    final s = InMemoryTelemetryStore();
    final v = OfflineVisitRecord(
        patientId: _patient, risk: 'red', status: 'done', notes: 'SEGREDO-CLINICO', outcome: 'DESFECHO-X');
    await _rec(s, NetworkKind.wifi).visitRegistered(visit: v, alertId: _alert);
    final e = (await _all(s)).single;
    expect(e.payload.containsKey('notes'), isFalse);
    expect(e.payload.containsKey('outcome'), isFalse);
    final j = jsonEncode(e.payload);
    expect(j.contains('SEGREDO-CLINICO'), isFalse);
    expect(j.contains('DESFECHO-X'), isFalse);
  });

  group('networkKindOf', () {
    test('mapeamento e prioridade', () {
      expect(networkKindOf([]), NetworkKind.none);
      expect(networkKindOf([ConnectivityResult.none]), NetworkKind.none);
      expect(networkKindOf([ConnectivityResult.mobile, ConnectivityResult.wifi]), NetworkKind.wifi);
      expect(networkKindOf([ConnectivityResult.vpn, ConnectivityResult.mobile]), NetworkKind.mobile);
      expect(networkKindOf([ConnectivityResult.ethernet, ConnectivityResult.mobile]), NetworkKind.ethernet);
      expect(networkKindOf([ConnectivityResult.vpn]), NetworkKind.vpn);
      expect(networkKindOf([ConnectivityResult.bluetooth]), NetworkKind.other);
      expect(networkKindOf([ConnectivityResult.other, ConnectivityResult.none]), NetworkKind.other);
    });
  });
}
