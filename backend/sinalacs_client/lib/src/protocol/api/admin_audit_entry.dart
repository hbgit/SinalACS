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

/// Linha de auditoria para o backoffice. Sem `ipHash`, `previousHash` nem
/// `entryHash`: a cadeia de hash é do servidor, não da tela.
abstract class AdminAuditEntry implements _i1.SerializableModel {
  AdminAuditEntry._({
    required this.id,
    required this.sequence,
    required this.userLabel,
    required this.actionType,
    required this.resourceType,
    required this.timestamp,
    required this.result,
  });

  factory AdminAuditEntry({
    required String id,
    required int sequence,
    required String userLabel,
    required String actionType,
    required String resourceType,
    required DateTime timestamp,
    required String result,
  }) = _AdminAuditEntryImpl;

  factory AdminAuditEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAuditEntry(
      id: jsonSerialization['id'] as String,
      sequence: jsonSerialization['sequence'] as int,
      userLabel: jsonSerialization['userLabel'] as String,
      actionType: jsonSerialization['actionType'] as String,
      resourceType: jsonSerialization['resourceType'] as String,
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      result: jsonSerialization['result'] as String,
    );
  }

  String id;

  int sequence;

  String userLabel;

  String actionType;

  String resourceType;

  DateTime timestamp;

  String result;

  /// Returns a shallow copy of this [AdminAuditEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAuditEntry copyWith({
    String? id,
    int? sequence,
    String? userLabel,
    String? actionType,
    String? resourceType,
    DateTime? timestamp,
    String? result,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAuditEntry',
      'id': id,
      'sequence': sequence,
      'userLabel': userLabel,
      'actionType': actionType,
      'resourceType': resourceType,
      'timestamp': timestamp.toJson(),
      'result': result,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminAuditEntryImpl extends AdminAuditEntry {
  _AdminAuditEntryImpl({
    required String id,
    required int sequence,
    required String userLabel,
    required String actionType,
    required String resourceType,
    required DateTime timestamp,
    required String result,
  }) : super._(
         id: id,
         sequence: sequence,
         userLabel: userLabel,
         actionType: actionType,
         resourceType: resourceType,
         timestamp: timestamp,
         result: result,
       );

  /// Returns a shallow copy of this [AdminAuditEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAuditEntry copyWith({
    String? id,
    int? sequence,
    String? userLabel,
    String? actionType,
    String? resourceType,
    DateTime? timestamp,
    String? result,
  }) {
    return AdminAuditEntry(
      id: id ?? this.id,
      sequence: sequence ?? this.sequence,
      userLabel: userLabel ?? this.userLabel,
      actionType: actionType ?? this.actionType,
      resourceType: resourceType ?? this.resourceType,
      timestamp: timestamp ?? this.timestamp,
      result: result ?? this.result,
    );
  }
}
