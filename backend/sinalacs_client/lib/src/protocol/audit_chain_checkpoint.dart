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

/// Ponto de verificação da cadeia de `audit_logs` (#45): `entryHash` na
/// posição `sequence`, assinado, para detectar truncamento do final da cadeia.
abstract class AuditChainCheckpoint implements _i1.SerializableModel {
  AuditChainCheckpoint._({
    this.id,
    required this.sequence,
    required this.entryHash,
    required this.signature,
    required this.createdAt,
  });

  factory AuditChainCheckpoint({
    _i1.UuidValue? id,
    required int sequence,
    required String entryHash,
    required String signature,
    required DateTime createdAt,
  }) = _AuditChainCheckpointImpl;

  factory AuditChainCheckpoint.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AuditChainCheckpoint(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      sequence: jsonSerialization['sequence'] as int,
      entryHash: jsonSerialization['entryHash'] as String,
      signature: jsonSerialization['signature'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  int sequence;

  String entryHash;

  String signature;

  DateTime createdAt;

  /// Returns a shallow copy of this [AuditChainCheckpoint]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AuditChainCheckpoint copyWith({
    _i1.UuidValue? id,
    int? sequence,
    String? entryHash,
    String? signature,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AuditChainCheckpoint',
      if (id != null) 'id': id?.toJson(),
      'sequence': sequence,
      'entryHash': entryHash,
      'signature': signature,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AuditChainCheckpointImpl extends AuditChainCheckpoint {
  _AuditChainCheckpointImpl({
    _i1.UuidValue? id,
    required int sequence,
    required String entryHash,
    required String signature,
    required DateTime createdAt,
  }) : super._(
         id: id,
         sequence: sequence,
         entryHash: entryHash,
         signature: signature,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [AuditChainCheckpoint]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AuditChainCheckpoint copyWith({
    Object? id = _Undefined,
    int? sequence,
    String? entryHash,
    String? signature,
    DateTime? createdAt,
  }) {
    return AuditChainCheckpoint(
      id: id is _i1.UuidValue? ? id : this.id,
      sequence: sequence ?? this.sequence,
      entryHash: entryHash ?? this.entryHash,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
