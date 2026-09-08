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
import 'enums/user_role.dart' as _i2;

/// Usuário institucional. O CPF nunca é armazenado em claro — só o hash.
abstract class User implements _i1.SerializableModel {
  User._({
    this.id,
    required this.cpfHash,
    required this.name,
    required this.birthDate,
    required this.role,
    this.microAreaId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User({
    _i1.UuidValue? id,
    required String cpfHash,
    required String name,
    required DateTime birthDate,
    required _i2.UserRole role,
    _i1.UuidValue? microAreaId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _UserImpl;

  factory User.fromJson(Map<String, dynamic> jsonSerialization) {
    return User(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      cpfHash: jsonSerialization['cpfHash'] as String,
      name: jsonSerialization['name'] as String,
      birthDate: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['birthDate'],
      ),
      role: _i2.UserRole.fromJson((jsonSerialization['role'] as String)),
      microAreaId: jsonSerialization['microAreaId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['microAreaId'],
            ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String cpfHash;

  String name;

  DateTime birthDate;

  _i2.UserRole role;

  /// Territorialização: restringe o acesso do ACS ao seu território (INV-01).
  _i1.UuidValue? microAreaId;

  DateTime createdAt;

  DateTime updatedAt;

  /// Returns a shallow copy of this [User]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  User copyWith({
    _i1.UuidValue? id,
    String? cpfHash,
    String? name,
    DateTime? birthDate,
    _i2.UserRole? role,
    _i1.UuidValue? microAreaId,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'User',
      if (id != null) 'id': id?.toJson(),
      'cpfHash': cpfHash,
      'name': name,
      'birthDate': birthDate.toJson(),
      'role': role.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _UserImpl extends User {
  _UserImpl({
    _i1.UuidValue? id,
    required String cpfHash,
    required String name,
    required DateTime birthDate,
    required _i2.UserRole role,
    _i1.UuidValue? microAreaId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         cpfHash: cpfHash,
         name: name,
         birthDate: birthDate,
         role: role,
         microAreaId: microAreaId,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [User]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  User copyWith({
    Object? id = _Undefined,
    String? cpfHash,
    String? name,
    DateTime? birthDate,
    _i2.UserRole? role,
    Object? microAreaId = _Undefined,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id is _i1.UuidValue? ? id : this.id,
      cpfHash: cpfHash ?? this.cpfHash,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      role: role ?? this.role,
      microAreaId: microAreaId is _i1.UuidValue?
          ? microAreaId
          : this.microAreaId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
