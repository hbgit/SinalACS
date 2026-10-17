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

/// Alerta ainda não concluído da microárea do ACS, lido por HTTP (#80, R2):
/// a reserva para quando o MQTT do aparelho não está conectado.
///
/// Os campos espelham o envelope MQTT (`AlertDelivery.toJson`) mais o estado
/// persistido (`status`, `acknowledgedAt`) e o marcador de reforço. Nada de
/// `escalatedBy`, `escalationReason` ou `deviceId`: nenhuma identidade a mais.
abstract class AcsOpenAlert
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AcsOpenAlert._({
    required this.alertId,
    required this.patientId,
    required this.microAreaId,
    required this.riskLevel,
    required this.locationHash,
    this.locationCell,
    required this.triggeredAt,
    required this.status,
    this.acknowledgedAt,
    required this.escalated,
  });

  factory AcsOpenAlert({
    required String alertId,
    required String patientId,
    required String microAreaId,
    required _i2.RiskLevel riskLevel,
    required String locationHash,
    String? locationCell,
    required DateTime triggeredAt,
    required _i3.AlertStatus status,
    DateTime? acknowledgedAt,
    required bool escalated,
  }) = _AcsOpenAlertImpl;

  factory AcsOpenAlert.fromJson(Map<String, dynamic> jsonSerialization) {
    return AcsOpenAlert(
      alertId: jsonSerialization['alertId'] as String,
      patientId: jsonSerialization['patientId'] as String,
      microAreaId: jsonSerialization['microAreaId'] as String,
      riskLevel: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevel'] as String),
      ),
      locationHash: jsonSerialization['locationHash'] as String,
      locationCell: jsonSerialization['locationCell'] as String?,
      triggeredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['triggeredAt'],
      ),
      status: _i3.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      acknowledgedAt: jsonSerialization['acknowledgedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['acknowledgedAt'],
            ),
      escalated: _i1.BoolJsonExtension.fromJson(jsonSerialization['escalated']),
    );
  }

  String alertId;

  String patientId;

  String microAreaId;

  _i2.RiskLevel riskLevel;

  String locationHash;

  String? locationCell;

  DateTime triggeredAt;

  _i3.AlertStatus status;

  DateTime? acknowledgedAt;

  bool escalated;

  /// Returns a shallow copy of this [AcsOpenAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AcsOpenAlert copyWith({
    String? alertId,
    String? patientId,
    String? microAreaId,
    _i2.RiskLevel? riskLevel,
    String? locationHash,
    String? locationCell,
    DateTime? triggeredAt,
    _i3.AlertStatus? status,
    DateTime? acknowledgedAt,
    bool? escalated,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AcsOpenAlert',
      'alertId': alertId,
      'patientId': patientId,
      'microAreaId': microAreaId,
      'riskLevel': riskLevel.toJson(),
      'locationHash': locationHash,
      if (locationCell != null) 'locationCell': locationCell,
      'triggeredAt': triggeredAt.toJson(),
      'status': status.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
      'escalated': escalated,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AcsOpenAlert',
      'alertId': alertId,
      'patientId': patientId,
      'microAreaId': microAreaId,
      'riskLevel': riskLevel.toJson(),
      'locationHash': locationHash,
      if (locationCell != null) 'locationCell': locationCell,
      'triggeredAt': triggeredAt.toJson(),
      'status': status.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
      'escalated': escalated,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsOpenAlertImpl extends AcsOpenAlert {
  _AcsOpenAlertImpl({
    required String alertId,
    required String patientId,
    required String microAreaId,
    required _i2.RiskLevel riskLevel,
    required String locationHash,
    String? locationCell,
    required DateTime triggeredAt,
    required _i3.AlertStatus status,
    DateTime? acknowledgedAt,
    required bool escalated,
  }) : super._(
         alertId: alertId,
         patientId: patientId,
         microAreaId: microAreaId,
         riskLevel: riskLevel,
         locationHash: locationHash,
         locationCell: locationCell,
         triggeredAt: triggeredAt,
         status: status,
         acknowledgedAt: acknowledgedAt,
         escalated: escalated,
       );

  /// Returns a shallow copy of this [AcsOpenAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AcsOpenAlert copyWith({
    String? alertId,
    String? patientId,
    String? microAreaId,
    _i2.RiskLevel? riskLevel,
    String? locationHash,
    Object? locationCell = _Undefined,
    DateTime? triggeredAt,
    _i3.AlertStatus? status,
    Object? acknowledgedAt = _Undefined,
    bool? escalated,
  }) {
    return AcsOpenAlert(
      alertId: alertId ?? this.alertId,
      patientId: patientId ?? this.patientId,
      microAreaId: microAreaId ?? this.microAreaId,
      riskLevel: riskLevel ?? this.riskLevel,
      locationHash: locationHash ?? this.locationHash,
      locationCell: locationCell is String? ? locationCell : this.locationCell,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      status: status ?? this.status,
      acknowledgedAt: acknowledgedAt is DateTime?
          ? acknowledgedAt
          : this.acknowledgedAt,
      escalated: escalated ?? this.escalated,
    );
  }
}
