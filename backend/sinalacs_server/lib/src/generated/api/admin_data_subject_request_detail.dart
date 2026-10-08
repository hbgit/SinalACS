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
import '../enums/data_subject_request_type.dart' as _i2;
import '../enums/data_subject_request_status.dart' as _i3;

/// Detalhe de um pedido do titular. `details` e `resolution` são decifrados
/// só aqui (nunca na lista) e a leitura é auditada antes do dado.
abstract class AdminDataSubjectRequestDetail
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminDataSubjectRequestDetail._({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.dueAt,
    required this.overdue,
    required this.patientLabel,
    this.details,
    this.resolution,
    this.decidedAt,
  });

  factory AdminDataSubjectRequestDetail({
    required String id,
    required _i2.DataSubjectRequestType type,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
    required bool overdue,
    required String patientLabel,
    String? details,
    String? resolution,
    DateTime? decidedAt,
  }) = _AdminDataSubjectRequestDetailImpl;

  factory AdminDataSubjectRequestDetail.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminDataSubjectRequestDetail(
      id: jsonSerialization['id'] as String,
      type: _i2.DataSubjectRequestType.fromJson(
        (jsonSerialization['type'] as String),
      ),
      status: _i3.DataSubjectRequestStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      dueAt: _i1.DateTimeJsonExtension.fromJson(jsonSerialization['dueAt']),
      overdue: _i1.BoolJsonExtension.fromJson(jsonSerialization['overdue']),
      patientLabel: jsonSerialization['patientLabel'] as String,
      details: jsonSerialization['details'] as String?,
      resolution: jsonSerialization['resolution'] as String?,
      decidedAt: jsonSerialization['decidedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['decidedAt']),
    );
  }

  String id;

  _i2.DataSubjectRequestType type;

  _i3.DataSubjectRequestStatus status;

  DateTime createdAt;

  DateTime dueAt;

  bool overdue;

  String patientLabel;

  String? details;

  String? resolution;

  DateTime? decidedAt;

  /// Returns a shallow copy of this [AdminDataSubjectRequestDetail]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminDataSubjectRequestDetail copyWith({
    String? id,
    _i2.DataSubjectRequestType? type,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
    bool? overdue,
    String? patientLabel,
    String? details,
    String? resolution,
    DateTime? decidedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminDataSubjectRequestDetail',
      'id': id,
      'type': type.toJson(),
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      'overdue': overdue,
      'patientLabel': patientLabel,
      if (details != null) 'details': details,
      if (resolution != null) 'resolution': resolution,
      if (decidedAt != null) 'decidedAt': decidedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminDataSubjectRequestDetail',
      'id': id,
      'type': type.toJson(),
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      'overdue': overdue,
      'patientLabel': patientLabel,
      if (details != null) 'details': details,
      if (resolution != null) 'resolution': resolution,
      if (decidedAt != null) 'decidedAt': decidedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminDataSubjectRequestDetailImpl extends AdminDataSubjectRequestDetail {
  _AdminDataSubjectRequestDetailImpl({
    required String id,
    required _i2.DataSubjectRequestType type,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
    required bool overdue,
    required String patientLabel,
    String? details,
    String? resolution,
    DateTime? decidedAt,
  }) : super._(
         id: id,
         type: type,
         status: status,
         createdAt: createdAt,
         dueAt: dueAt,
         overdue: overdue,
         patientLabel: patientLabel,
         details: details,
         resolution: resolution,
         decidedAt: decidedAt,
       );

  /// Returns a shallow copy of this [AdminDataSubjectRequestDetail]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminDataSubjectRequestDetail copyWith({
    String? id,
    _i2.DataSubjectRequestType? type,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
    bool? overdue,
    String? patientLabel,
    Object? details = _Undefined,
    Object? resolution = _Undefined,
    Object? decidedAt = _Undefined,
  }) {
    return AdminDataSubjectRequestDetail(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      dueAt: dueAt ?? this.dueAt,
      overdue: overdue ?? this.overdue,
      patientLabel: patientLabel ?? this.patientLabel,
      details: details is String? ? details : this.details,
      resolution: resolution is String? ? resolution : this.resolution,
      decidedAt: decidedAt is DateTime? ? decidedAt : this.decidedAt,
    );
  }
}
