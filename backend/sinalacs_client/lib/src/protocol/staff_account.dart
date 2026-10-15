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

/// Conta de staff do backoffice (coordenador ou administrador).
///
/// Tabela própria, e não uma coluna em `acs`: staff não é ACS, não tem UBS nem
/// sincronização, e misturar os dois faria `acs.enrollmentId` virar um
/// namespace compartilhado. O id é o UUID do usuário (mesma decisão de `Acs`).
/// O papel mora em `users.role` (`coordinator` | `admin`); a credencial, em
/// `user_credentials`.
abstract class StaffAccount implements _i1.SerializableModel {
  StaffAccount._({
    this.id,
    required this.enrollmentId,
    required this.active,
    this.ubsId,
    this.activationCodeHash,
    this.activationCodeExpiresAt,
    this.activationCodeIssuedBy,
    this.activationCodeIssuedAt,
  });

  factory StaffAccount({
    _i1.UuidValue? id,
    required String enrollmentId,
    required bool active,
    _i1.UuidValue? ubsId,
    String? activationCodeHash,
    DateTime? activationCodeExpiresAt,
    String? activationCodeIssuedBy,
    DateTime? activationCodeIssuedAt,
  }) = _StaffAccountImpl;

  factory StaffAccount.fromJson(Map<String, dynamic> jsonSerialization) {
    return StaffAccount(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
      ubsId: jsonSerialization['ubsId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['ubsId']),
      activationCodeHash: jsonSerialization['activationCodeHash'] as String?,
      activationCodeExpiresAt:
          jsonSerialization['activationCodeExpiresAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['activationCodeExpiresAt'],
            ),
      activationCodeIssuedBy:
          jsonSerialization['activationCodeIssuedBy'] as String?,
      activationCodeIssuedAt:
          jsonSerialization['activationCodeIssuedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['activationCodeIssuedAt'],
            ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String enrollmentId;

  bool active;

  /// UBS do coordenador; nulo para administrador. Coordenador sem UBS é recusado.
  _i1.UuidValue? ubsId;

  String? activationCodeHash;

  DateTime? activationCodeExpiresAt;

  String? activationCodeIssuedBy;

  DateTime? activationCodeIssuedAt;

  /// Returns a shallow copy of this [StaffAccount]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  StaffAccount copyWith({
    _i1.UuidValue? id,
    String? enrollmentId,
    bool? active,
    _i1.UuidValue? ubsId,
    String? activationCodeHash,
    DateTime? activationCodeExpiresAt,
    String? activationCodeIssuedBy,
    DateTime? activationCodeIssuedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'StaffAccount',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'active': active,
      if (ubsId != null) 'ubsId': ubsId?.toJson(),
      if (activationCodeHash != null) 'activationCodeHash': activationCodeHash,
      if (activationCodeExpiresAt != null)
        'activationCodeExpiresAt': activationCodeExpiresAt?.toJson(),
      if (activationCodeIssuedBy != null)
        'activationCodeIssuedBy': activationCodeIssuedBy,
      if (activationCodeIssuedAt != null)
        'activationCodeIssuedAt': activationCodeIssuedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _StaffAccountImpl extends StaffAccount {
  _StaffAccountImpl({
    _i1.UuidValue? id,
    required String enrollmentId,
    required bool active,
    _i1.UuidValue? ubsId,
    String? activationCodeHash,
    DateTime? activationCodeExpiresAt,
    String? activationCodeIssuedBy,
    DateTime? activationCodeIssuedAt,
  }) : super._(
         id: id,
         enrollmentId: enrollmentId,
         active: active,
         ubsId: ubsId,
         activationCodeHash: activationCodeHash,
         activationCodeExpiresAt: activationCodeExpiresAt,
         activationCodeIssuedBy: activationCodeIssuedBy,
         activationCodeIssuedAt: activationCodeIssuedAt,
       );

  /// Returns a shallow copy of this [StaffAccount]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  StaffAccount copyWith({
    Object? id = _Undefined,
    String? enrollmentId,
    bool? active,
    Object? ubsId = _Undefined,
    Object? activationCodeHash = _Undefined,
    Object? activationCodeExpiresAt = _Undefined,
    Object? activationCodeIssuedBy = _Undefined,
    Object? activationCodeIssuedAt = _Undefined,
  }) {
    return StaffAccount(
      id: id is _i1.UuidValue? ? id : this.id,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      active: active ?? this.active,
      ubsId: ubsId is _i1.UuidValue? ? ubsId : this.ubsId,
      activationCodeHash: activationCodeHash is String?
          ? activationCodeHash
          : this.activationCodeHash,
      activationCodeExpiresAt: activationCodeExpiresAt is DateTime?
          ? activationCodeExpiresAt
          : this.activationCodeExpiresAt,
      activationCodeIssuedBy: activationCodeIssuedBy is String?
          ? activationCodeIssuedBy
          : this.activationCodeIssuedBy,
      activationCodeIssuedAt: activationCodeIssuedAt is DateTime?
          ? activationCodeIssuedAt
          : this.activationCodeIssuedAt,
    );
  }
}
