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

/// Trilha de auditoria de acesso a dados sensíveis. Append-only.
///
/// `sequence`/`previousHash`/`entryHash` formam uma cadeia de hash (LGPD-RT03):
/// cada linha encadeia à anterior via `previousHash == entryHash` da linha de
/// `sequence - 1`, e `entryHash` é um HMAC-SHA256 sobre o conteúdo da própria
/// linha (ver `application/audit/audit_chain.dart`). Isso torna qualquer
/// edição, remoção ou reordenação de linha detectável — inclusive por quem tem
/// acesso de escrita direto ao Postgres, que é o adversário que a §458 de
/// spec/lgpd_design.md descreve. O índice único em `sequence` é o segundo
/// cinto: uma bifurcação da cadeia por concorrência estoura na hora em vez de
/// corromper em silêncio.
abstract class AuditLog implements _i1.SerializableModel {
  AuditLog._({
    this.id,
    required this.userId,
    required this.actionType,
    required this.resourceType,
    this.resourceId,
    required this.timestamp,
    required this.ipHash,
    required this.result,
    required this.sequence,
    required this.previousHash,
    required this.entryHash,
  });

  factory AuditLog({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String actionType,
    required String resourceType,
    _i1.UuidValue? resourceId,
    required DateTime timestamp,
    required String ipHash,
    required String result,
    required int sequence,
    required String previousHash,
    required String entryHash,
  }) = _AuditLogImpl;

  factory AuditLog.fromJson(Map<String, dynamic> jsonSerialization) {
    return AuditLog(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      actionType: jsonSerialization['actionType'] as String,
      resourceType: jsonSerialization['resourceType'] as String,
      resourceId: jsonSerialization['resourceId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['resourceId'],
            ),
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      ipHash: jsonSerialization['ipHash'] as String,
      result: jsonSerialization['result'] as String,
      sequence: jsonSerialization['sequence'] as int,
      previousHash: jsonSerialization['previousHash'] as String,
      entryHash: jsonSerialization['entryHash'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  String actionType;

  String resourceType;

  _i1.UuidValue? resourceId;

  DateTime timestamp;

  String ipHash;

  String result;

  /// Posição na cadeia, começando em 1. Contígua por construção — um buraco
  /// aqui é uma linha apagada.
  int sequence;

  /// `entryHash` da linha anterior, ou `AuditChain.genesisHash` (64 zeros) na
  /// primeira linha. Nunca nulo: gênese e "escrito antes da cadeia existir"
  /// não podem ter a mesma representação.
  String previousHash;

  /// HMAC-SHA256(AUDIT_CHAIN_SECRET, conteúdo da linha). Ver AuditChain.compute.
  String entryHash;

  /// Returns a shallow copy of this [AuditLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AuditLog copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? actionType,
    String? resourceType,
    _i1.UuidValue? resourceId,
    DateTime? timestamp,
    String? ipHash,
    String? result,
    int? sequence,
    String? previousHash,
    String? entryHash,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AuditLog',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'actionType': actionType,
      'resourceType': resourceType,
      if (resourceId != null) 'resourceId': resourceId?.toJson(),
      'timestamp': timestamp.toJson(),
      'ipHash': ipHash,
      'result': result,
      'sequence': sequence,
      'previousHash': previousHash,
      'entryHash': entryHash,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AuditLogImpl extends AuditLog {
  _AuditLogImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String actionType,
    required String resourceType,
    _i1.UuidValue? resourceId,
    required DateTime timestamp,
    required String ipHash,
    required String result,
    required int sequence,
    required String previousHash,
    required String entryHash,
  }) : super._(
         id: id,
         userId: userId,
         actionType: actionType,
         resourceType: resourceType,
         resourceId: resourceId,
         timestamp: timestamp,
         ipHash: ipHash,
         result: result,
         sequence: sequence,
         previousHash: previousHash,
         entryHash: entryHash,
       );

  /// Returns a shallow copy of this [AuditLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AuditLog copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? actionType,
    String? resourceType,
    Object? resourceId = _Undefined,
    DateTime? timestamp,
    String? ipHash,
    String? result,
    int? sequence,
    String? previousHash,
    String? entryHash,
  }) {
    return AuditLog(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      actionType: actionType ?? this.actionType,
      resourceType: resourceType ?? this.resourceType,
      resourceId: resourceId is _i1.UuidValue? ? resourceId : this.resourceId,
      timestamp: timestamp ?? this.timestamp,
      ipHash: ipHash ?? this.ipHash,
      result: result ?? this.result,
      sequence: sequence ?? this.sequence,
      previousHash: previousHash ?? this.previousHash,
      entryHash: entryHash ?? this.entryHash,
    );
  }
}
