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

/// Resultado de escalonar um alerta pelo backoffice. `alreadyEscalated` torna
/// a operação idempotente: repetir o pedido não duplica o escalonamento.
abstract class AdminEscalationResult implements _i1.SerializableModel {
  AdminEscalationResult._({
    required this.alertId,
    required this.escalatedAt,
    required this.alreadyEscalated,
  });

  factory AdminEscalationResult({
    required String alertId,
    required DateTime escalatedAt,
    required bool alreadyEscalated,
  }) = _AdminEscalationResultImpl;

  factory AdminEscalationResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminEscalationResult(
      alertId: jsonSerialization['alertId'] as String,
      escalatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['escalatedAt'],
      ),
      alreadyEscalated: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['alreadyEscalated'],
      ),
    );
  }

  String alertId;

  DateTime escalatedAt;

  bool alreadyEscalated;

  /// Returns a shallow copy of this [AdminEscalationResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminEscalationResult copyWith({
    String? alertId,
    DateTime? escalatedAt,
    bool? alreadyEscalated,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminEscalationResult',
      'alertId': alertId,
      'escalatedAt': escalatedAt.toJson(),
      'alreadyEscalated': alreadyEscalated,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminEscalationResultImpl extends AdminEscalationResult {
  _AdminEscalationResultImpl({
    required String alertId,
    required DateTime escalatedAt,
    required bool alreadyEscalated,
  }) : super._(
         alertId: alertId,
         escalatedAt: escalatedAt,
         alreadyEscalated: alreadyEscalated,
       );

  /// Returns a shallow copy of this [AdminEscalationResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminEscalationResult copyWith({
    String? alertId,
    DateTime? escalatedAt,
    bool? alreadyEscalated,
  }) {
    return AdminEscalationResult(
      alertId: alertId ?? this.alertId,
      escalatedAt: escalatedAt ?? this.escalatedAt,
      alreadyEscalated: alreadyEscalated ?? this.alreadyEscalated,
    );
  }
}
