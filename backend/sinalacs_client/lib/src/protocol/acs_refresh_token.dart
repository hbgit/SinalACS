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

/// Refresh token do ACS (LGPD-RT06). Uma linha por token emitido; os tokens de
/// um mesmo login formam uma *família* (`familyId`) e a rotação encadeia
/// dentro dela.
///
/// **Nunca** o token: só o SHA-256 dele em hex. O token é 256 bits aleatórios,
/// então um hash simples basta (não há senha humana para adivinhar).
abstract class AcsRefreshToken implements _i1.SerializableModel {
  AcsRefreshToken._({
    this.id,
    required this.userId,
    required this.familyId,
    required this.tokenHash,
    required this.deviceId,
    required this.issuedAt,
    required this.idleExpiresAt,
    required this.absoluteExpiresAt,
    this.rotatedAt,
    this.revokedAt,
  });

  factory AcsRefreshToken({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i1.UuidValue familyId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime idleExpiresAt,
    required DateTime absoluteExpiresAt,
    DateTime? rotatedAt,
    DateTime? revokedAt,
  }) = _AcsRefreshTokenImpl;

  factory AcsRefreshToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return AcsRefreshToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      familyId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['familyId'],
      ),
      tokenHash: jsonSerialization['tokenHash'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      issuedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['issuedAt'],
      ),
      idleExpiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['idleExpiresAt'],
      ),
      absoluteExpiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['absoluteExpiresAt'],
      ),
      rotatedAt: jsonSerialization['rotatedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['rotatedAt']),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  /// Todos os tokens nascidos do mesmo login por senha+TOTP.
  _i1.UuidValue familyId;

  String tokenHash;

  /// Aparelho que recebeu o token. Token apresentado por outro aparelho
  /// revoga a família.
  String deviceId;

  DateTime issuedAt;

  /// Janela ociosa: renovada a cada rotação, nunca além de `absoluteExpiresAt`.
  DateTime idleExpiresAt;

  /// Teto do turno, fixado no login por senha+TOTP e herdado pelos filhos.
  DateTime absoluteExpiresAt;

  /// `null` = ainda não usado. Preenchido na rotação.
  DateTime? rotatedAt;

  /// `null` = vigente. Preenchido na revogação da família ou no logout.
  DateTime? revokedAt;

  /// Returns a shallow copy of this [AcsRefreshToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AcsRefreshToken copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    _i1.UuidValue? familyId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? idleExpiresAt,
    DateTime? absoluteExpiresAt,
    DateTime? rotatedAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AcsRefreshToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'familyId': familyId.toJson(),
      'tokenHash': tokenHash,
      'deviceId': deviceId,
      'issuedAt': issuedAt.toJson(),
      'idleExpiresAt': idleExpiresAt.toJson(),
      'absoluteExpiresAt': absoluteExpiresAt.toJson(),
      if (rotatedAt != null) 'rotatedAt': rotatedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsRefreshTokenImpl extends AcsRefreshToken {
  _AcsRefreshTokenImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i1.UuidValue familyId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime idleExpiresAt,
    required DateTime absoluteExpiresAt,
    DateTime? rotatedAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         userId: userId,
         familyId: familyId,
         tokenHash: tokenHash,
         deviceId: deviceId,
         issuedAt: issuedAt,
         idleExpiresAt: idleExpiresAt,
         absoluteExpiresAt: absoluteExpiresAt,
         rotatedAt: rotatedAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [AcsRefreshToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AcsRefreshToken copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    _i1.UuidValue? familyId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? idleExpiresAt,
    DateTime? absoluteExpiresAt,
    Object? rotatedAt = _Undefined,
    Object? revokedAt = _Undefined,
  }) {
    return AcsRefreshToken(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      familyId: familyId ?? this.familyId,
      tokenHash: tokenHash ?? this.tokenHash,
      deviceId: deviceId ?? this.deviceId,
      issuedAt: issuedAt ?? this.issuedAt,
      idleExpiresAt: idleExpiresAt ?? this.idleExpiresAt,
      absoluteExpiresAt: absoluteExpiresAt ?? this.absoluteExpiresAt,
      rotatedAt: rotatedAt is DateTime? ? rotatedAt : this.rotatedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}
