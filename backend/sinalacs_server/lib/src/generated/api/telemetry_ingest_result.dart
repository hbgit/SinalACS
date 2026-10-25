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
import 'package:sinalacs_server/src/generated/protocol.dart' as _i2;

/// Resposta de `telemetry.ingest` (#83): o app apaga os aceitos e descarta
/// ou mantém os recusados. Um evento recusado nunca derruba o lote.
abstract class TelemetryIngestResult
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  TelemetryIngestResult._({
    required this.acceptedEventIds,
    required this.rejectedEventIds,
  });

  factory TelemetryIngestResult({
    required List<String> acceptedEventIds,
    required List<String> rejectedEventIds,
  }) = _TelemetryIngestResultImpl;

  factory TelemetryIngestResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return TelemetryIngestResult(
      acceptedEventIds: _i2.Protocol().deserialize<List<String>>(
        jsonSerialization['acceptedEventIds'],
      ),
      rejectedEventIds: _i2.Protocol().deserialize<List<String>>(
        jsonSerialization['rejectedEventIds'],
      ),
    );
  }

  List<String> acceptedEventIds;

  List<String> rejectedEventIds;

  /// Returns a shallow copy of this [TelemetryIngestResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TelemetryIngestResult copyWith({
    List<String>? acceptedEventIds,
    List<String>? rejectedEventIds,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TelemetryIngestResult',
      'acceptedEventIds': acceptedEventIds.toJson(),
      'rejectedEventIds': rejectedEventIds.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TelemetryIngestResult',
      'acceptedEventIds': acceptedEventIds.toJson(),
      'rejectedEventIds': rejectedEventIds.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TelemetryIngestResultImpl extends TelemetryIngestResult {
  _TelemetryIngestResultImpl({
    required List<String> acceptedEventIds,
    required List<String> rejectedEventIds,
  }) : super._(
         acceptedEventIds: acceptedEventIds,
         rejectedEventIds: rejectedEventIds,
       );

  /// Returns a shallow copy of this [TelemetryIngestResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TelemetryIngestResult copyWith({
    List<String>? acceptedEventIds,
    List<String>? rejectedEventIds,
  }) {
    return TelemetryIngestResult(
      acceptedEventIds:
          acceptedEventIds ?? this.acceptedEventIds.map((e0) => e0).toList(),
      rejectedEventIds:
          rejectedEventIds ?? this.rejectedEventIds.map((e0) => e0).toList(),
    );
  }
}
