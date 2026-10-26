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

import 'package:serverpod/serverpod.dart' as _i1;

/// Um evento enviado pelo app do ACS a `telemetry.ingest` (#83).
/// O servidor valida o `payloadJson` contra o esquema fechado do evento.
abstract class TelemetryEventInput
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  TelemetryEventInput._({
    required this.eventId,
    required this.eventName,
    required this.occurredAt,
    required this.appVersion,
    required this.payloadJson,
  });

  factory TelemetryEventInput({
    required String eventId,
    required String eventName,
    required DateTime occurredAt,
    required String appVersion,
    required String payloadJson,
  }) = _TelemetryEventInputImpl;

  factory TelemetryEventInput.fromJson(Map<String, dynamic> jsonSerialization) {
    return TelemetryEventInput(
      eventId: jsonSerialization['eventId'] as String,
      eventName: jsonSerialization['eventName'] as String,
      occurredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['occurredAt'],
      ),
      appVersion: jsonSerialization['appVersion'] as String,
      payloadJson: jsonSerialization['payloadJson'] as String,
    );
  }

  String eventId;

  String eventName;

  DateTime occurredAt;

  String appVersion;

  String payloadJson;

  /// Returns a shallow copy of this [TelemetryEventInput]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TelemetryEventInput copyWith({
    String? eventId,
    String? eventName,
    DateTime? occurredAt,
    String? appVersion,
    String? payloadJson,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TelemetryEventInput',
      'eventId': eventId,
      'eventName': eventName,
      'occurredAt': occurredAt.toJson(),
      'appVersion': appVersion,
      'payloadJson': payloadJson,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TelemetryEventInput',
      'eventId': eventId,
      'eventName': eventName,
      'occurredAt': occurredAt.toJson(),
      'appVersion': appVersion,
      'payloadJson': payloadJson,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TelemetryEventInputImpl extends TelemetryEventInput {
  _TelemetryEventInputImpl({
    required String eventId,
    required String eventName,
    required DateTime occurredAt,
    required String appVersion,
    required String payloadJson,
  }) : super._(
         eventId: eventId,
         eventName: eventName,
         occurredAt: occurredAt,
         appVersion: appVersion,
         payloadJson: payloadJson,
       );

  /// Returns a shallow copy of this [TelemetryEventInput]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TelemetryEventInput copyWith({
    String? eventId,
    String? eventName,
    DateTime? occurredAt,
    String? appVersion,
    String? payloadJson,
  }) {
    return TelemetryEventInput(
      eventId: eventId ?? this.eventId,
      eventName: eventName ?? this.eventName,
      occurredAt: occurredAt ?? this.occurredAt,
      appVersion: appVersion ?? this.appVersion,
      payloadJson: payloadJson ?? this.payloadJson,
    );
  }
}
