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

/// Token de push (FCM/APNs) do aparelho de um paciente que consentiu com
/// `segmentedPush` (RF14, decisão §3.2). Uma linha por token: se o mesmo token
/// aparece para outro titular, a linha muda de dono, nunca duplica.
///
/// O token identifica um aparelho, não uma pessoa, mas junto de `userId` liga
/// aparelho a titular — por isso some na revogação do consentimento.
abstract class PushToken implements _i1.SerializableModel {
  PushToken._({
    this.id,
    required this.userId,
    this.microAreaId,
    required this.token,
    required this.platform,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PushToken({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    _i1.UuidValue? microAreaId,
    required String token,
    required String platform,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _PushTokenImpl;

  factory PushToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return PushToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      microAreaId: jsonSerialization['microAreaId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['microAreaId'],
            ),
      token: jsonSerialization['token'] as String,
      platform: jsonSerialization['platform'] as String,
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

  _i1.UuidValue userId;

  _i1.UuidValue? microAreaId;

  String token;

  String platform;

  DateTime createdAt;

  DateTime updatedAt;

  /// Returns a shallow copy of this [PushToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PushToken copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    _i1.UuidValue? microAreaId,
    String? token,
    String? platform,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PushToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'token': token,
      'platform': platform,
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

class _PushTokenImpl extends PushToken {
  _PushTokenImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    _i1.UuidValue? microAreaId,
    required String token,
    required String platform,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         userId: userId,
         microAreaId: microAreaId,
         token: token,
         platform: platform,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [PushToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PushToken copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    Object? microAreaId = _Undefined,
    String? token,
    String? platform,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PushToken(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      microAreaId: microAreaId is _i1.UuidValue?
          ? microAreaId
          : this.microAreaId,
      token: token ?? this.token,
      platform: platform ?? this.platform,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
