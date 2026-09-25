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
import '../enums/risk_level.dart' as _i2;
import '../enums/alert_status.dart' as _i3;

/// Status do alerta mais recente do paciente autenticado (RF05, decisão §5,
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md).
///
/// `found: false` quando o paciente nunca disparou um alerta — os demais
/// campos ficam nulos, mesmo padrão de AlertAckResult.acknowledged: false.
abstract class AlertStatusResult
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AlertStatusResult._({
    required this.found,
    this.alertId,
    this.riskLevel,
    this.status,
    this.triggeredAt,
    this.acknowledgedAt,
  });

  factory AlertStatusResult({
    required bool found,
    String? alertId,
    _i2.RiskLevel? riskLevel,
    _i3.AlertStatus? status,
    DateTime? triggeredAt,
    DateTime? acknowledgedAt,
  }) = _AlertStatusResultImpl;

  factory AlertStatusResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertStatusResult(
      found: _i1.BoolJsonExtension.fromJson(jsonSerialization['found']),
      alertId: jsonSerialization['alertId'] as String?,
      riskLevel: jsonSerialization['riskLevel'] == null
          ? null
          : _i2.RiskLevel.fromJson((jsonSerialization['riskLevel'] as String)),
      status: jsonSerialization['status'] == null
          ? null
          : _i3.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      triggeredAt: jsonSerialization['triggeredAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['triggeredAt'],
            ),
      acknowledgedAt: jsonSerialization['acknowledgedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['acknowledgedAt'],
            ),
    );
  }

  bool found;

  String? alertId;

  _i2.RiskLevel? riskLevel;

  _i3.AlertStatus? status;

  DateTime? triggeredAt;

  DateTime? acknowledgedAt;

  /// Returns a shallow copy of this [AlertStatusResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertStatusResult copyWith({
    bool? found,
    String? alertId,
    _i2.RiskLevel? riskLevel,
    _i3.AlertStatus? status,
    DateTime? triggeredAt,
    DateTime? acknowledgedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertStatusResult',
      'found': found,
      if (alertId != null) 'alertId': alertId,
      if (riskLevel != null) 'riskLevel': riskLevel?.toJson(),
      if (status != null) 'status': status?.toJson(),
      if (triggeredAt != null) 'triggeredAt': triggeredAt?.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AlertStatusResult',
      'found': found,
      if (alertId != null) 'alertId': alertId,
      if (riskLevel != null) 'riskLevel': riskLevel?.toJson(),
      if (status != null) 'status': status?.toJson(),
      if (triggeredAt != null) 'triggeredAt': triggeredAt?.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertStatusResultImpl extends AlertStatusResult {
  _AlertStatusResultImpl({
    required bool found,
    String? alertId,
    _i2.RiskLevel? riskLevel,
    _i3.AlertStatus? status,
    DateTime? triggeredAt,
    DateTime? acknowledgedAt,
  }) : super._(
         found: found,
         alertId: alertId,
         riskLevel: riskLevel,
         status: status,
         triggeredAt: triggeredAt,
         acknowledgedAt: acknowledgedAt,
       );

  /// Returns a shallow copy of this [AlertStatusResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertStatusResult copyWith({
    bool? found,
    Object? alertId = _Undefined,
    Object? riskLevel = _Undefined,
    Object? status = _Undefined,
    Object? triggeredAt = _Undefined,
    Object? acknowledgedAt = _Undefined,
  }) {
    return AlertStatusResult(
      found: found ?? this.found,
      alertId: alertId is String? ? alertId : this.alertId,
      riskLevel: riskLevel is _i2.RiskLevel? ? riskLevel : this.riskLevel,
      status: status is _i3.AlertStatus? ? status : this.status,
      triggeredAt: triggeredAt is DateTime? ? triggeredAt : this.triggeredAt,
      acknowledgedAt: acknowledgedAt is DateTime?
          ? acknowledgedAt
          : this.acknowledgedAt,
    );
  }
}
