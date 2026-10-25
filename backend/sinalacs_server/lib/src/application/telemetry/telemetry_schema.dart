import '../common/uuid_format.dart';

/// Nomes dos eventos da telemetria (PRD §1.3).
abstract final class TelemetryEventNames {
  static const alertTriggered = 'alert_triggered';
  static const alertReceivedAcs = 'alert_received_acs';
  static const syncAttempt = 'sync_attempt';
  static const syncResult = 'sync_result';
  static const visitRegistered = 'visit_registered';

  /// Eventos que o aparelho pode emitir; os demais nascem no backend.
  static const deviceEmitted = {syncAttempt, syncResult, visitRegistered};
}

const _networkTypes = {
  'wifi',
  'mobile',
  'ethernet',
  'vpn',
  'none',
  'other',
  'unknown',
};

/// Um campo do esquema fechado: valida o valor e diz se é opcional.
class _Field {
  const _Field(this.accepts, {this.optional = false});

  final bool Function(Object value) accepts;
  final bool optional;
}

_Field _uuid({bool optional = false}) => _Field(
  (v) => v is String && isUuidFormat(v),
  optional: optional,
);

_Field _intRange(int min, int max) =>
    _Field((v) => v is int && v >= min && v <= max);

_Field _oneOf(Set<String> values) =>
    _Field((v) => v is String && values.contains(v));

const _bool = _Field(_isBool);
bool _isBool(Object v) => v is bool;

final _intNonNegative = _Field((v) => v is int && v >= 0);

final Map<String, Map<String, _Field>> _schemas = {
  TelemetryEventNames.syncAttempt: {
    'records_count': _intRange(1, 10000),
    'network_type': _oneOf(_networkTypes),
    'channel': _oneOf({'sync'}),
  },
  TelemetryEventNames.syncResult: {
    'attempt_event_id': _uuid(),
    'success_count': _intRange(0, 10000),
    'failure_count': _intRange(0, 10000),
    'conflict_count': _intRange(0, 10000),
    'rejected_count': _intRange(0, 10000),
    'outcome': _oneOf({'synced', 'conflict', 'error', 'rejected'}),
    'transport_error': _bool,
    'duration_ms': _intNonNegative,
  },
  TelemetryEventNames.visitRegistered: {
    'local_id': _uuid(),
    'patient_id': _uuid(),
    'visit_type': _oneOf({'alert', 'routine'}),
    'alert_id': _uuid(optional: true),
    'offline_flag': _bool,
    'network_type': _oneOf(_networkTypes),
    'sync_status': _oneOf({'queued'}),
  },
};

/// Valida o payload de um evento emitido pelo aparelho contra o esquema v1
/// fechado: chave desconhecida, ausente, de tipo ou domínio errado recusa o
/// evento (devolve `null`). `alert_id` nulo vale como ausente. Quando válido,
/// devolve uma cópia só com as chaves do esquema, ainda com `patient_id`: quem
/// o troca pelo pseudônimo e o remove é o serviço de ingestão.
Map<String, Object?>? validateDevicePayload(
  String eventName,
  Map<String, Object?> payload,
) {
  if (!TelemetryEventNames.deviceEmitted.contains(eventName)) return null;
  final schema = _schemas[eventName]!;

  final normalized = <String, Object?>{};
  for (final entry in payload.entries) {
    if (!schema.containsKey(entry.key)) return null;
    if (entry.value != null) normalized[entry.key] = entry.value;
  }
  for (final entry in schema.entries) {
    final value = normalized[entry.key];
    if (value == null) {
      if (!entry.value.optional) return null;
    } else if (!entry.value.accepts(value)) {
      return null;
    }
  }

  if (eventName == TelemetryEventNames.visitRegistered) {
    final hasAlert = normalized.containsKey('alert_id');
    final isAlertVisit = normalized['visit_type'] == 'alert';
    if (hasAlert != isAlertVisit) return null;
  }
  return normalized;
}
