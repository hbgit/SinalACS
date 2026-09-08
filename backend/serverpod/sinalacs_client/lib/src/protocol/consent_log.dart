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

/// Registro de consentimento LGPD. Append-only.
abstract class ConsentLog implements _i1.SerializableModel {
  ConsentLog._({
    this.id,
    required this.userId,
    required this.purpose,
    required this.action,
    required this.version,
    required this.timestamp,
    required this.ipHash,
    required this.userAgent,
    required this.signature,
  });

  factory ConsentLog({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
    required String ipHash,
    required String userAgent,
    required String signature,
  }) = _ConsentLogImpl;

  factory ConsentLog.fromJson(Map<String, dynamic> jsonSerialization) {
    return ConsentLog(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      purpose: jsonSerialization['purpose'] as String,
      action: jsonSerialization['action'] as String,
      version: jsonSerialization['version'] as String,
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      ipHash: jsonSerialization['ipHash'] as String,
      userAgent: jsonSerialization['userAgent'] as String,
      signature: jsonSerialization['signature'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  String purpose;

  String action;

  String version;

  DateTime timestamp;

  String ipHash;

  String userAgent;

  String signature;

  /// Returns a shallow copy of this [ConsentLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ConsentLog copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? purpose,
    String? action,
    String? version,
    DateTime? timestamp,
    String? ipHash,
    String? userAgent,
    String? signature,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ConsentLog',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'purpose': purpose,
      'action': action,
      'version': version,
      'timestamp': timestamp.toJson(),
      'ipHash': ipHash,
      'userAgent': userAgent,
      'signature': signature,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ConsentLogImpl extends ConsentLog {
  _ConsentLogImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
    required String ipHash,
    required String userAgent,
    required String signature,
  }) : super._(
         id: id,
         userId: userId,
         purpose: purpose,
         action: action,
         version: version,
         timestamp: timestamp,
         ipHash: ipHash,
         userAgent: userAgent,
         signature: signature,
       );

  /// Returns a shallow copy of this [ConsentLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ConsentLog copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? purpose,
    String? action,
    String? version,
    DateTime? timestamp,
    String? ipHash,
    String? userAgent,
    String? signature,
  }) {
    return ConsentLog(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      purpose: purpose ?? this.purpose,
      action: action ?? this.action,
      version: version ?? this.version,
      timestamp: timestamp ?? this.timestamp,
      ipHash: ipHash ?? this.ipHash,
      userAgent: userAgent ?? this.userAgent,
      signature: signature ?? this.signature,
    );
  }
}
