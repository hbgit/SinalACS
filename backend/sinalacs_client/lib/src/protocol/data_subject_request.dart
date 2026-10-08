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
import 'enums/data_subject_request_type.dart' as _i2;
import 'enums/data_subject_request_status.dart' as _i3;

/// Pedido do titular sobre os próprios dados (LGPD-RF08): exclusão ou
/// correção, com prazo de resposta de 15 dias (spec/lgpd_design.md 596-597).
///
/// `details` é texto livre do titular e pode citar condição de saúde — por
/// isso é cifrado na aplicação (AES-256-GCM), pelo mesmo motivo e com o
/// mesmo `HealthDataCipher` de `visits.notes` (RNF03/INV-04). Num pedido de
/// exclusão guarda o JSON `null` cifrado.
abstract class DataSubjectRequest implements _i1.SerializableModel {
  DataSubjectRequest._({
    this.id,
    required this.userId,
    required this.requestType,
    required this.detailsEncrypted,
    required this.detailsKeyVersion,
    required this.status,
    required this.createdAt,
    required this.dueAt,
    this.decidedAt,
    this.decidedBy,
    this.resolutionEncrypted,
    this.resolutionKeyVersion,
  });

  factory DataSubjectRequest({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i2.DataSubjectRequestType requestType,
    required String detailsEncrypted,
    required int detailsKeyVersion,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
    DateTime? decidedAt,
    _i1.UuidValue? decidedBy,
    String? resolutionEncrypted,
    int? resolutionKeyVersion,
  }) = _DataSubjectRequestImpl;

  factory DataSubjectRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return DataSubjectRequest(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      requestType: _i2.DataSubjectRequestType.fromJson(
        (jsonSerialization['requestType'] as String),
      ),
      detailsEncrypted: jsonSerialization['detailsEncrypted'] as String,
      detailsKeyVersion: jsonSerialization['detailsKeyVersion'] as int,
      status: _i3.DataSubjectRequestStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      dueAt: _i1.DateTimeJsonExtension.fromJson(jsonSerialization['dueAt']),
      decidedAt: jsonSerialization['decidedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['decidedAt']),
      decidedBy: jsonSerialization['decidedBy'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['decidedBy']),
      resolutionEncrypted: jsonSerialization['resolutionEncrypted'] as String?,
      resolutionKeyVersion: jsonSerialization['resolutionKeyVersion'] as int?,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  _i2.DataSubjectRequestType requestType;

  String detailsEncrypted;

  int detailsKeyVersion;

  _i3.DataSubjectRequestStatus status;

  DateTime createdAt;

  /// Prazo de resposta: `createdAt` + 15 dias.
  DateTime dueAt;

  /// Decisão do backoffice (#42); nulos enquanto o pedido está `open`.
  DateTime? decidedAt;

  _i1.UuidValue? decidedBy;

  /// Nota de resposta/motivo da recusa: texto livre, cifrado como `details`.
  String? resolutionEncrypted;

  int? resolutionKeyVersion;

  /// Returns a shallow copy of this [DataSubjectRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DataSubjectRequest copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    _i2.DataSubjectRequestType? requestType,
    String? detailsEncrypted,
    int? detailsKeyVersion,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
    DateTime? decidedAt,
    _i1.UuidValue? decidedBy,
    String? resolutionEncrypted,
    int? resolutionKeyVersion,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DataSubjectRequest',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'requestType': requestType.toJson(),
      'detailsEncrypted': detailsEncrypted,
      'detailsKeyVersion': detailsKeyVersion,
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
      if (decidedAt != null) 'decidedAt': decidedAt?.toJson(),
      if (decidedBy != null) 'decidedBy': decidedBy?.toJson(),
      if (resolutionEncrypted != null)
        'resolutionEncrypted': resolutionEncrypted,
      if (resolutionKeyVersion != null)
        'resolutionKeyVersion': resolutionKeyVersion,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DataSubjectRequestImpl extends DataSubjectRequest {
  _DataSubjectRequestImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i2.DataSubjectRequestType requestType,
    required String detailsEncrypted,
    required int detailsKeyVersion,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
    DateTime? decidedAt,
    _i1.UuidValue? decidedBy,
    String? resolutionEncrypted,
    int? resolutionKeyVersion,
  }) : super._(
         id: id,
         userId: userId,
         requestType: requestType,
         detailsEncrypted: detailsEncrypted,
         detailsKeyVersion: detailsKeyVersion,
         status: status,
         createdAt: createdAt,
         dueAt: dueAt,
         decidedAt: decidedAt,
         decidedBy: decidedBy,
         resolutionEncrypted: resolutionEncrypted,
         resolutionKeyVersion: resolutionKeyVersion,
       );

  /// Returns a shallow copy of this [DataSubjectRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DataSubjectRequest copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    _i2.DataSubjectRequestType? requestType,
    String? detailsEncrypted,
    int? detailsKeyVersion,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
    Object? decidedAt = _Undefined,
    Object? decidedBy = _Undefined,
    Object? resolutionEncrypted = _Undefined,
    Object? resolutionKeyVersion = _Undefined,
  }) {
    return DataSubjectRequest(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      requestType: requestType ?? this.requestType,
      detailsEncrypted: detailsEncrypted ?? this.detailsEncrypted,
      detailsKeyVersion: detailsKeyVersion ?? this.detailsKeyVersion,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      dueAt: dueAt ?? this.dueAt,
      decidedAt: decidedAt is DateTime? ? decidedAt : this.decidedAt,
      decidedBy: decidedBy is _i1.UuidValue? ? decidedBy : this.decidedBy,
      resolutionEncrypted: resolutionEncrypted is String?
          ? resolutionEncrypted
          : this.resolutionEncrypted,
      resolutionKeyVersion: resolutionKeyVersion is int?
          ? resolutionKeyVersion
          : this.resolutionKeyVersion,
    );
  }
}
