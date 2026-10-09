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

/// Linha da lista de pedidos do titular no backoffice. Sem nome nem CPF:
/// `patientLabel` é um rótulo curto (`#A18F`) derivado do id do titular.
abstract class AdminDataSubjectRequest
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminDataSubjectRequest._({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.dueAt,
    required this.overdue,
    required this.patientLabel,
  });

  factory AdminDataSubjectRequest({
    required String id,
    required _i2.DataSubjectRequestType type,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
    required bool overdue,
    required String patientLabel,
  }) = _AdminDataSubjectRequestImpl;

  factory AdminDataSubjectRequest.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminDataSubjectRequest(
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
    );
  }

  String id;

  _i2.DataSubjectRequestType type;

  _i3.DataSubjectRequestStatus status;

  DateTime createdAt;

  DateTime dueAt;

  /// Vencido: status `open`/`inReview` e agora > `dueAt`.
  bool overdue;

  String patientLabel;

  /// Returns a shallow copy of this [AdminDataSubjectRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminDataSubjectRequest copyWith({
    String? id,
    _i2.DataSubjectRequestType? type,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
    bool? overdue,
    String? patientLabel,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminDataSubjectRequest',
      'id': id,
      'type': type.toJson(),
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      'overdue': overdue,
      'patientLabel': patientLabel,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminDataSubjectRequest',
      'id': id,
      'type': type.toJson(),
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      'overdue': overdue,
      'patientLabel': patientLabel,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminDataSubjectRequestImpl extends AdminDataSubjectRequest {
  _AdminDataSubjectRequestImpl({
    required String id,
    required _i2.DataSubjectRequestType type,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
    required bool overdue,
    required String patientLabel,
  }) : super._(
         id: id,
         type: type,
         status: status,
         createdAt: createdAt,
         dueAt: dueAt,
         overdue: overdue,
         patientLabel: patientLabel,
       );

  /// Returns a shallow copy of this [AdminDataSubjectRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminDataSubjectRequest copyWith({
    String? id,
    _i2.DataSubjectRequestType? type,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
    bool? overdue,
    String? patientLabel,
  }) {
    return AdminDataSubjectRequest(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      dueAt: dueAt ?? this.dueAt,
      overdue: overdue ?? this.overdue,
      patientLabel: patientLabel ?? this.patientLabel,
    );
  }
}
