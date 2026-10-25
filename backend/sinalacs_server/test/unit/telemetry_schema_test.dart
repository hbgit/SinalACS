import 'package:sinalacs_server/src/application/telemetry/telemetry_schema.dart';
import 'package:test/test.dart';

const _u1 = '3f2b8c1e-5a4d-4e6f-9b0a-1c2d3e4f5a6b';
const _u2 = '7a1d2c3b-4e5f-4a6b-8c9d-0e1f2a3b4c5d';

Map<String, Object?> _visit({Map<String, Object?> extra = const {}}) => {
  'local_id': _u1,
  'patient_id': _u2,
  'visit_type': 'routine',
  'offline_flag': true,
  'network_type': 'none',
  'sync_status': 'queued',
  ...extra,
};

void main() {
  test('válido: sync_attempt', () {
    final p = {'records_count': 3, 'network_type': 'wifi', 'channel': 'sync'};
    expect(validateDevicePayload(TelemetryEventNames.syncAttempt, p), p);
  });

  test('válido: sync_result', () {
    final p = {
      'attempt_event_id': _u1,
      'success_count': 2,
      'failure_count': 0,
      'conflict_count': 1,
      'rejected_count': 0,
      'outcome': 'synced',
      'transport_error': false,
      'duration_ms': 120,
    };
    expect(validateDevicePayload(TelemetryEventNames.syncResult, p), p);
  });

  test('válido: visit_registered', () {
    final p = _visit();
    expect(validateDevicePayload(TelemetryEventNames.visitRegistered, p), p);
  });

  test('chave desconhecida recusa o evento', () {
    expect(
      validateDevicePayload(
        TelemetryEventNames.visitRegistered,
        _visit(extra: {'notes': 'x'}),
      ),
      isNull,
    );
  });

  test('alert_id obrigatório em visit_type alert e proibido em routine', () {
    const n = TelemetryEventNames.visitRegistered;
    expect(
      validateDevicePayload(n, _visit(extra: {'visit_type': 'alert'})),
      isNull,
    );
    expect(
      validateDevicePayload(
        n,
        _visit(extra: {'visit_type': 'alert', 'alert_id': _u1}),
      ),
      isNotNull,
    );
    expect(validateDevicePayload(n, _visit(extra: {'alert_id': _u1})), isNull);
    // null explícito vale como ausente.
    final ok = validateDevicePayload(n, _visit(extra: {'alert_id': null}));
    expect(ok, isNotNull);
    expect(ok!.containsKey('alert_id'), isFalse);
    expect(
      validateDevicePayload(
        n,
        _visit(extra: {'visit_type': 'alert', 'alert_id': null}),
      ),
      isNull,
    );
  });

  test('chave obrigatória ausente recusa o evento', () {
    final p = _visit()..remove('offline_flag');
    expect(
      validateDevicePayload(TelemetryEventNames.visitRegistered, p),
      isNull,
    );
  });

  test('network_type fora do domínio recusa', () {
    expect(
      validateDevicePayload(TelemetryEventNames.syncAttempt, {
        'records_count': 1,
        'network_type': '5g',
        'channel': 'sync',
      }),
      isNull,
    );
  });

  test('contagem negativa ou acima de 10000 recusa', () {
    Map<String, Object?> a(Object? n) => {
      'records_count': n,
      'network_type': 'wifi',
      'channel': 'sync',
    };
    const n = TelemetryEventNames.syncAttempt;
    expect(validateDevicePayload(n, a(-1)), isNull);
    expect(validateDevicePayload(n, a(0)), isNull);
    expect(validateDevicePayload(n, a(10001)), isNull);
    expect(validateDevicePayload(n, a(10000)), isNotNull);
    expect(validateDevicePayload(n, a('3')), isNull);
    expect(validateDevicePayload(n, a(1.5)), isNull);
  });

  test('bool exige bool JSON', () {
    expect(
      validateDevicePayload(
        TelemetryEventNames.visitRegistered,
        _visit(extra: {'offline_flag': 1}),
      ),
      isNull,
    );
  });

  test('patient_id que não é UUID recusa', () {
    expect(
      validateDevicePayload(
        TelemetryEventNames.visitRegistered,
        _visit(extra: {'patient_id': 'Maria da Silva'}),
      ),
      isNull,
    );
  });

  test('nome de evento do backend vindo do aparelho recusa', () {
    expect(
      validateDevicePayload(TelemetryEventNames.alertTriggered, {
        'risk_level': 'red',
        'mqtt_topic': 't',
        'location_known': true,
        'published': true,
      }),
      isNull,
    );
  });
}
