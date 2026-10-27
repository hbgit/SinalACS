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
import '../enums/risk_level.dart' as _i2;
import '../enums/alert_status.dart' as _i3;

/// Alerta para o backoffice. `patientLabel` é `#` + 4 hex do UUID: o backoffice
/// identifica, não qualifica (spec/lgpd_design.md). Nunca nome, CPF ou contato.
abstract class AdminAlert implements _i1.SerializableModel {
  AdminAlert._({
    required this.id,
    required this.patientLabel,
    required this.microAreaName,
    required this.riskLevel,
    required this.status,
    required this.triggeredAt,
    this.escalatedAt,
    this.resolvedAt,
    required this.overdue,
  });

  factory AdminAlert({
    required String id,
    required String patientLabel,
    required String microAreaName,
    required _i2.RiskLevel riskLevel,
    required _i3.AlertStatus status,
    required DateTime triggeredAt,
    DateTime? escalatedAt,
    DateTime? resolvedAt,
    required bool overdue,
  }) = _AdminAlertImpl;

  factory AdminAlert.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAlert(
      id: jsonSerialization['id'] as String,
      patientLabel: jsonSerialization['patientLabel'] as String,
      microAreaName: jsonSerialization['microAreaName'] as String,
      riskLevel: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevel'] as String),
      ),
      status: _i3.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      triggeredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['triggeredAt'],
      ),
      escalatedAt: jsonSerialization['escalatedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['escalatedAt'],
            ),
      resolvedAt: jsonSerialization['resolvedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['resolvedAt']),
      overdue: _i1.BoolJsonExtension.fromJson(jsonSerialization['overdue']),
    );
  }

  String id;

  String patientLabel;

  String microAreaName;

  _i2.RiskLevel riskLevel;

  _i3.AlertStatus status;

  DateTime triggeredAt;

  DateTime? escalatedAt;

  /// Conclusão do atendimento (#76), se houve. Nulo também numa linha
  /// `resolved` anterior à coluna: a tela mostra o estado sem a hora.
  DateTime? resolvedAt;

  /// Sem reconhecimento além do prazo configurado; calculado na leitura.
  bool overdue;

  /// Returns a shallow copy of this [AdminAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAlert copyWith({
    String? id,
    String? patientLabel,
    String? microAreaName,
    _i2.RiskLevel? riskLevel,
    _i3.AlertStatus? status,
    DateTime? triggeredAt,
    DateTime? escalatedAt,
    DateTime? resolvedAt,
    bool? overdue,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAlert',
      'id': id,
      'patientLabel': patientLabel,
      'microAreaName': microAreaName,
      'riskLevel': riskLevel.toJson(),
      'status': status.toJson(),
      'triggeredAt': triggeredAt.toJson(),
      if (escalatedAt != null) 'escalatedAt': escalatedAt?.toJson(),
      if (resolvedAt != null) 'resolvedAt': resolvedAt?.toJson(),
      'overdue': overdue,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAlertImpl extends AdminAlert {
  _AdminAlertImpl({
    required String id,
    required String patientLabel,
    required String microAreaName,
    required _i2.RiskLevel riskLevel,
    required _i3.AlertStatus status,
    required DateTime triggeredAt,
    DateTime? escalatedAt,
    DateTime? resolvedAt,
    required bool overdue,
  }) : super._(
         id: id,
         patientLabel: patientLabel,
         microAreaName: microAreaName,
         riskLevel: riskLevel,
         status: status,
         triggeredAt: triggeredAt,
         escalatedAt: escalatedAt,
         resolvedAt: resolvedAt,
         overdue: overdue,
       );

  /// Returns a shallow copy of this [AdminAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAlert copyWith({
    String? id,
    String? patientLabel,
    String? microAreaName,
    _i2.RiskLevel? riskLevel,
    _i3.AlertStatus? status,
    DateTime? triggeredAt,
    Object? escalatedAt = _Undefined,
    Object? resolvedAt = _Undefined,
    bool? overdue,
  }) {
    return AdminAlert(
      id: id ?? this.id,
      patientLabel: patientLabel ?? this.patientLabel,
      microAreaName: microAreaName ?? this.microAreaName,
      riskLevel: riskLevel ?? this.riskLevel,
      status: status ?? this.status,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      escalatedAt: escalatedAt is DateTime? ? escalatedAt : this.escalatedAt,
      resolvedAt: resolvedAt is DateTime? ? resolvedAt : this.resolvedAt,
      overdue: overdue ?? this.overdue,
    );
  }
}
