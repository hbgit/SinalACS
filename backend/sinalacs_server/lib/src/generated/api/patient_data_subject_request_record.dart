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

/// Um pedido do próprio titular, para o painel "Meus Dados". `details` já
/// decifrado — é texto que o próprio titular escreveu (direito de acesso).
abstract class PatientDataSubjectRequestRecord
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  PatientDataSubjectRequestRecord._({
    required this.type,
    required this.status,
    this.details,
    required this.createdAt,
    required this.dueAt,
    this.resolution,
  });

  factory PatientDataSubjectRequestRecord({
    required _i2.DataSubjectRequestType type,
    required _i3.DataSubjectRequestStatus status,
    String? details,
    required DateTime createdAt,
    required DateTime dueAt,
    String? resolution,
  }) = _PatientDataSubjectRequestRecordImpl;

  factory PatientDataSubjectRequestRecord.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return PatientDataSubjectRequestRecord(
      type: _i2.DataSubjectRequestType.fromJson(
        (jsonSerialization['type'] as String),
      ),
      status: _i3.DataSubjectRequestStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      details: jsonSerialization['details'] as String?,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      dueAt: _i1.DateTimeJsonExtension.fromJson(jsonSerialization['dueAt']),
      resolution: jsonSerialization['resolution'] as String?,
    );
  }

  _i2.DataSubjectRequestType type;

  _i3.DataSubjectRequestStatus status;

  String? details;

  DateTime createdAt;

  DateTime dueAt;

  /// Nota de resposta do backoffice, já decifrada; nula até a decisão.
  String? resolution;

  /// Returns a shallow copy of this [PatientDataSubjectRequestRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PatientDataSubjectRequestRecord copyWith({
    _i2.DataSubjectRequestType? type,
    _i3.DataSubjectRequestStatus? status,
    String? details,
    DateTime? createdAt,
    DateTime? dueAt,
    String? resolution,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PatientDataSubjectRequestRecord',
      'type': type.toJson(),
      'status': status.toJson(),
      if (details != null) 'details': details,
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      if (resolution != null) 'resolution': resolution,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PatientDataSubjectRequestRecord',
      'type': type.toJson(),
      'status': status.toJson(),
      if (details != null) 'details': details,
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      if (resolution != null) 'resolution': resolution,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PatientDataSubjectRequestRecordImpl
    extends PatientDataSubjectRequestRecord {
  _PatientDataSubjectRequestRecordImpl({
    required _i2.DataSubjectRequestType type,
    required _i3.DataSubjectRequestStatus status,
    String? details,
    required DateTime createdAt,
    required DateTime dueAt,
    String? resolution,
  }) : super._(
         type: type,
         status: status,
         details: details,
         createdAt: createdAt,
         dueAt: dueAt,
         resolution: resolution,
       );

  /// Returns a shallow copy of this [PatientDataSubjectRequestRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PatientDataSubjectRequestRecord copyWith({
    _i2.DataSubjectRequestType? type,
    _i3.DataSubjectRequestStatus? status,
    Object? details = _Undefined,
    DateTime? createdAt,
    DateTime? dueAt,
    Object? resolution = _Undefined,
  }) {
    return PatientDataSubjectRequestRecord(
      type: type ?? this.type,
      status: status ?? this.status,
      details: details is String? ? details : this.details,
      createdAt: createdAt ?? this.createdAt,
      dueAt: dueAt ?? this.dueAt,
      resolution: resolution is String? ? resolution : this.resolution,
    );
  }
}
