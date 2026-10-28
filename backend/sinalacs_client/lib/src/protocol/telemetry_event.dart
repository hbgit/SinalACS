/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:serverpod_client/serverpod_client.dart' as _i1;
import 'enums/telemetry_source.dart' as _i2;

/// Evento de telemetria do PRD §1.3 (#83). Só anexa: nunca se atualiza.
/// Sem `relation` para `alerts` nem `users`: o expurgo de um não depende do outro.
abstract class TelemetryEvent implements _i1.SerializableModel {
  TelemetryEvent._({
    this.id,
    required this.eventId,
    required this.eventName,
    int? schemaVersion,
    required this.source,
    required this.occurredAt,
    required this.receivedAt,
    this.clockSkewMs,
    this.actorId,
    this.devicePseudonym,
    this.patientPseudonym,
    this.alertId,
    required this.appVersion,
    required this.payload,
  }) : schemaVersion = schemaVersion ?? 1;

  factory TelemetryEvent({
    int? id,
    required _i1.UuidValue eventId,
    required String eventName,
    int? schemaVersion,
    required _i2.TelemetrySource source,
    required DateTime occurredAt,
    required DateTime receivedAt,
    int? clockSkewMs,
    _i1.UuidValue? actorId,
    String? devicePseudonym,
    String? patientPseudonym,
    _i1.UuidValue? alertId,
    required String appVersion,
    required String payload,
  }) = _TelemetryEventImpl;

  factory TelemetryEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return TelemetryEvent(
      id: jsonSerialization['id'] as int?,
      eventId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['eventId'],
      ),
      eventName: jsonSerialization['eventName'] as String,
      schemaVersion: jsonSerialization['schemaVersion'] as int?,
      source: _i2.TelemetrySource.fromJson(
        (jsonSerialization['source'] as String),
      ),
      occurredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['occurredAt'],
      ),
      receivedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['receivedAt'],
      ),
      clockSkewMs: jsonSerialization['clockSkewMs'] as int?,
      actorId: jsonSerialization['actorId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['actorId']),
      devicePseudonym: jsonSerialization['devicePseudonym'] as String?,
      patientPseudonym: jsonSerialization['patientPseudonym'] as String?,
      alertId: jsonSerialization['alertId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['alertId']),
      appVersion: jsonSerialization['appVersion'] as String,
      payload: jsonSerialization['payload'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  /// Identificador do evento, gerado por quem emite. Único: o reenvio do mesmo
  /// lote não duplica linha. Os eventos do backend usam UUID v5 determinístico.
  _i1.UuidValue eventId;

  /// Um de `alert_triggered`, `alert_received_acs`, `sync_attempt`,
  /// `sync_result` ou `visit_registered`.
  String eventName;

  /// Versão do esquema do `payload`. Hoje 1.
  int schemaVersion;

  _i2.TelemetrySource source;

  /// Relógio de quem emitiu (UTC). No app pode estar errado: ver `clockSkewMs`.
  DateTime occurredAt;

  /// Relógio do servidor ao gravar. Base da retenção.
  DateTime receivedAt;

  /// `receivedAt` menos o instante de envio do app. Nulo nos eventos do backend.
  int? clockSkewMs;

  /// ACS autor, vindo do token e nunca do cliente. Dado de profissional.
  _i1.UuidValue? actorId;

  /// HMAC-SHA-256 do id da instalação, domínio `device`. Nunca o id cru.
  String? devicePseudonym;

  /// HMAC-SHA-256 do UUID do paciente, domínio `patient`, calculado no servidor.
  String? patientPseudonym;

  _i1.UuidValue? alertId;

  String appVersion;

  /// JSON em texto, esquema fechado por evento, sem PII (sem UUID do paciente).
  String payload;

  /// Returns a shallow copy of this [TelemetryEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TelemetryEvent copyWith({
    int? id,
    _i1.UuidValue? eventId,
    String? eventName,
    int? schemaVersion,
    _i2.TelemetrySource? source,
    DateTime? occurredAt,
    DateTime? receivedAt,
    int? clockSkewMs,
    _i1.UuidValue? actorId,
    String? devicePseudonym,
    String? patientPseudonym,
    _i1.UuidValue? alertId,
    String? appVersion,
    String? payload,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TelemetryEvent',
      if (id != null) 'id': id,
      'eventId': eventId.toJson(),
      'eventName': eventName,
      'schemaVersion': schemaVersion,
      'source': source.toJson(),
      'occurredAt': occurredAt.toJson(),
      'receivedAt': receivedAt.toJson(),
      if (clockSkewMs != null) 'clockSkewMs': clockSkewMs,
      if (actorId != null) 'actorId': actorId?.toJson(),
      if (devicePseudonym != null) 'devicePseudonym': devicePseudonym,
      if (patientPseudonym != null) 'patientPseudonym': patientPseudonym,
      if (alertId != null) 'alertId': alertId?.toJson(),
      'appVersion': appVersion,
      'payload': payload,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TelemetryEventImpl extends TelemetryEvent {
  _TelemetryEventImpl({
    int? id,
    required _i1.UuidValue eventId,
    required String eventName,
    int? schemaVersion,
    required _i2.TelemetrySource source,
    required DateTime occurredAt,
    required DateTime receivedAt,
    int? clockSkewMs,
    _i1.UuidValue? actorId,
    String? devicePseudonym,
    String? patientPseudonym,
    _i1.UuidValue? alertId,
    required String appVersion,
    required String payload,
  }) : super._(
         id: id,
         eventId: eventId,
         eventName: eventName,
         schemaVersion: schemaVersion,
         source: source,
         occurredAt: occurredAt,
         receivedAt: receivedAt,
         clockSkewMs: clockSkewMs,
         actorId: actorId,
         devicePseudonym: devicePseudonym,
         patientPseudonym: patientPseudonym,
         alertId: alertId,
         appVersion: appVersion,
         payload: payload,
       );

  /// Returns a shallow copy of this [TelemetryEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TelemetryEvent copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? eventId,
    String? eventName,
    int? schemaVersion,
    _i2.TelemetrySource? source,
    DateTime? occurredAt,
    DateTime? receivedAt,
    Object? clockSkewMs = _Undefined,
    Object? actorId = _Undefined,
    Object? devicePseudonym = _Undefined,
    Object? patientPseudonym = _Undefined,
    Object? alertId = _Undefined,
    String? appVersion,
    String? payload,
  }) {
    return TelemetryEvent(
      id: id is int? ? id : this.id,
      eventId: eventId ?? this.eventId,
      eventName: eventName ?? this.eventName,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      source: source ?? this.source,
      occurredAt: occurredAt ?? this.occurredAt,
      receivedAt: receivedAt ?? this.receivedAt,
      clockSkewMs: clockSkewMs is int? ? clockSkewMs : this.clockSkewMs,
      actorId: actorId is _i1.UuidValue? ? actorId : this.actorId,
      devicePseudonym: devicePseudonym is String?
          ? devicePseudonym
          : this.devicePseudonym,
      patientPseudonym: patientPseudonym is String?
          ? patientPseudonym
          : this.patientPseudonym,
      alertId: alertId is _i1.UuidValue? ? alertId : this.alertId,
      appVersion: appVersion ?? this.appVersion,
      payload: payload ?? this.payload,
    );
  }
}
