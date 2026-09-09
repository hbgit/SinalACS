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

/// Resultado da confirmação de recebimento.
///
/// O servidor dart:io distinguia 200 de 404 pelo status HTTP; no RPC essa
/// distinção vira o campo acknowledged: false significa que não havia alerta
/// com esse id na microárea do ACS.
abstract class AlertAckResult implements _i1.SerializableModel {
  AlertAckResult._({
    required this.alertId,
    required this.acknowledged,
    this.status,
  });

  factory AlertAckResult({
    required String alertId,
    required bool acknowledged,
    _i2.AlertStatus? status,
  }) = _AlertAckResultImpl;

  factory AlertAckResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertAckResult(
      alertId: jsonSerialization['alertId'] as String,
      acknowledged: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['acknowledged'],
      ),
      status: jsonSerialization['status'] == null
          ? null
          : _i2.AlertStatus.fromJson((jsonSerialization['status'] as String)),
    );
  }

  String alertId;

  bool acknowledged;

  _i2.AlertStatus? status;

  /// Returns a shallow copy of this [AlertAckResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertAckResult copyWith({
    String? alertId,
    bool? acknowledged,
    _i2.AlertStatus? status,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertAckResult',
      'alertId': alertId,
      'acknowledged': acknowledged,
      if (status != null) 'status': status?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertAckResultImpl extends AlertAckResult {
  _AlertAckResultImpl({
    required String alertId,
    required bool acknowledged,
    _i2.AlertStatus? status,
  }) : super._(
         alertId: alertId,
         acknowledged: acknowledged,
         status: status,
       );

  /// Returns a shallow copy of this [AlertAckResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertAckResult copyWith({
    String? alertId,
    bool? acknowledged,
    Object? status = _Undefined,
  }) {
    return AlertAckResult(
      alertId: alertId ?? this.alertId,
      acknowledged: acknowledged ?? this.acknowledged,
      status: status is _i2.AlertStatus? ? status : this.status,
    );
  }
}
