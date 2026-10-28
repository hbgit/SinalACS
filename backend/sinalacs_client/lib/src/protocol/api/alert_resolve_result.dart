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
import '../enums/alert_status.dart' as _i2;

/// Resultado de alerts.resolve (#76).
///
/// Mesmo desenho de AlertAckResult: resolved: false significa que não havia
/// alerta com esse id na microárea do ACS. Concluir duas vezes devolve
/// resolved: true com o resolvedAt da primeira conclusão.
abstract class AlertResolveResult implements _i1.SerializableModel {
  AlertResolveResult._({
    required this.alertId,
    required this.resolved,
    this.status,
    this.resolvedAt,
  });

  factory AlertResolveResult({
    required String alertId,
    required bool resolved,
    _i2.AlertStatus? status,
    DateTime? resolvedAt,
  }) = _AlertResolveResultImpl;

  factory AlertResolveResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertResolveResult(
      alertId: jsonSerialization['alertId'] as String,
      resolved: _i1.BoolJsonExtension.fromJson(jsonSerialization['resolved']),
      status: jsonSerialization['status'] == null
          ? null
          : _i2.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      resolvedAt: jsonSerialization['resolvedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['resolvedAt']),
    );
  }

  String alertId;

  bool resolved;

  _i2.AlertStatus? status;

  DateTime? resolvedAt;

  /// Returns a shallow copy of this [AlertResolveResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertResolveResult copyWith({
    String? alertId,
    bool? resolved,
    _i2.AlertStatus? status,
    DateTime? resolvedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertResolveResult',
      'alertId': alertId,
      'resolved': resolved,
      if (status != null) 'status': status?.toJson(),
      if (resolvedAt != null) 'resolvedAt': resolvedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertResolveResultImpl extends AlertResolveResult {
  _AlertResolveResultImpl({
    required String alertId,
    required bool resolved,
    _i2.AlertStatus? status,
    DateTime? resolvedAt,
  }) : super._(
         alertId: alertId,
         resolved: resolved,
         status: status,
         resolvedAt: resolvedAt,
       );

  /// Returns a shallow copy of this [AlertResolveResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertResolveResult copyWith({
    String? alertId,
    bool? resolved,
    Object? status = _Undefined,
    Object? resolvedAt = _Undefined,
  }) {
    return AlertResolveResult(
      alertId: alertId ?? this.alertId,
      resolved: resolved ?? this.resolved,
      status: status is _i2.AlertStatus? ? status : this.status,
      resolvedAt: resolvedAt is DateTime? ? resolvedAt : this.resolvedAt,
    );
  }
}
