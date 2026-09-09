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

/// Resultado da criação de um alerta vermelho.
/// Equivale ao corpo {alert_id, status} que o servidor dart:io devolvia com 202.
abstract class RedAlertResult implements _i1.SerializableModel {
  RedAlertResult._({
    required this.alertId,
    required this.status,
  });

  factory RedAlertResult({
    required String alertId,
    required _i2.AlertStatus status,
  }) = _RedAlertResultImpl;

  factory RedAlertResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return RedAlertResult(
      alertId: jsonSerialization['alertId'] as String,
      status: _i2.AlertStatus.fromJson((jsonSerialization['status'] as String)),
    );
  }

  String alertId;

  _i2.AlertStatus status;

  /// Returns a shallow copy of this [RedAlertResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  RedAlertResult copyWith({
    String? alertId,
    _i2.AlertStatus? status,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RedAlertResult',
      'alertId': alertId,
      'status': status.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _RedAlertResultImpl extends RedAlertResult {
  _RedAlertResultImpl({
    required String alertId,
    required _i2.AlertStatus status,
  }) : super._(
         alertId: alertId,
         status: status,
       );

  /// Returns a shallow copy of this [RedAlertResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  RedAlertResult copyWith({
    String? alertId,
    _i2.AlertStatus? status,
  }) {
    return RedAlertResult(
      alertId: alertId ?? this.alertId,
      status: status ?? this.status,
    );
  }
}
