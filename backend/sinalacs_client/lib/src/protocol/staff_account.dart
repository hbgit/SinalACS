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
  });

  factory StaffAccount({
    _i1.UuidValue? id,
    required String enrollmentId,
    required bool active,
  }) = _StaffAccountImpl;

  factory StaffAccount.fromJson(Map<String, dynamic> jsonSerialization) {
    return StaffAccount(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String enrollmentId;

  bool active;

  /// Returns a shallow copy of this [StaffAccount]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  StaffAccount copyWith({
    _i1.UuidValue? id,
    String? enrollmentId,
    bool? active,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'StaffAccount',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'active': active,
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
  }) : super._(
         id: id,
         enrollmentId: enrollmentId,
         active: active,
       );

  /// Returns a shallow copy of this [StaffAccount]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  StaffAccount copyWith({
    Object? id = _Undefined,
    String? enrollmentId,
    bool? active,
  }) {
    return StaffAccount(
      id: id is _i1.UuidValue? ? id : this.id,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      active: active ?? this.active,
    );
  }
}
