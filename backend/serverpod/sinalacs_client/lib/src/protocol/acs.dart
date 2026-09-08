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

/// Agente Comunitário de Saúde.
///
/// Mesma decisão de chave aplicada em Patient: o id desta tabela é o UUID do
/// usuário, fornecido na inserção.
abstract class Acs implements _i1.SerializableModel {
  Acs._({
    this.id,
    required this.enrollmentId,
    required this.ubsId,
    required this.active,
    this.lastSyncAt,
  });

  factory Acs({
    _i1.UuidValue? id,
    required String enrollmentId,
    required _i1.UuidValue ubsId,
    required bool active,
    DateTime? lastSyncAt,
  }) = _AcsImpl;

  factory Acs.fromJson(Map<String, dynamic> jsonSerialization) {
    return Acs(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      ubsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['ubsId']),
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
      lastSyncAt: jsonSerialization['lastSyncAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['lastSyncAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String enrollmentId;

  _i1.UuidValue ubsId;

  bool active;

  DateTime? lastSyncAt;

  /// Returns a shallow copy of this [Acs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Acs copyWith({
    _i1.UuidValue? id,
    String? enrollmentId,
    _i1.UuidValue? ubsId,
    bool? active,
    DateTime? lastSyncAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Acs',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'ubsId': ubsId.toJson(),
      'active': active,
      if (lastSyncAt != null) 'lastSyncAt': lastSyncAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsImpl extends Acs {
  _AcsImpl({
    _i1.UuidValue? id,
    required String enrollmentId,
    required _i1.UuidValue ubsId,
    required bool active,
    DateTime? lastSyncAt,
  }) : super._(
         id: id,
         enrollmentId: enrollmentId,
         ubsId: ubsId,
         active: active,
         lastSyncAt: lastSyncAt,
       );

  /// Returns a shallow copy of this [Acs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Acs copyWith({
    Object? id = _Undefined,
    String? enrollmentId,
    _i1.UuidValue? ubsId,
    bool? active,
    Object? lastSyncAt = _Undefined,
  }) {
    return Acs(
      id: id is _i1.UuidValue? ? id : this.id,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      ubsId: ubsId ?? this.ubsId,
      active: active ?? this.active,
      lastSyncAt: lastSyncAt is DateTime? ? lastSyncAt : this.lastSyncAt,
    );
  }
}
