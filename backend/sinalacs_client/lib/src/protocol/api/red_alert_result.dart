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
    required this.published,
  });

  factory RedAlertResult({
    required String alertId,
    required _i2.AlertStatus status,
    required bool published,
  }) = _RedAlertResultImpl;

  factory RedAlertResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return RedAlertResult(
      alertId: jsonSerialization['alertId'] as String,
      status: _i2.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      published: _i1.BoolJsonExtension.fromJson(jsonSerialization['published']),
    );
  }

  String alertId;

  _i2.AlertStatus status;

  /// Falso quando o broker estava indisponível e a entrega ficou pendente no
  /// outbox. O alerta está gravado de qualquer forma e será publicado pela
  /// varredura assim que o broker voltar.
  bool published;

  /// Returns a shallow copy of this [RedAlertResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  RedAlertResult copyWith({
    String? alertId,
    _i2.AlertStatus? status,
    bool? published,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RedAlertResult',
      'alertId': alertId,
      'status': status.toJson(),
      'published': published,
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
    required bool published,
  }) : super._(
         alertId: alertId,
         status: status,
         published: published,
       );

  /// Returns a shallow copy of this [RedAlertResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  RedAlertResult copyWith({
    String? alertId,
    _i2.AlertStatus? status,
    bool? published,
  }) {
    return RedAlertResult(
      alertId: alertId ?? this.alertId,
      status: status ?? this.status,
      published: published ?? this.published,
    );
  }
}
