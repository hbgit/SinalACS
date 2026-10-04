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

/// Token de envio diferido do ACS (D7 do plano 2026-10-03). Deixa o aparelho
/// subir as visitas pendentes de um ACS que já saiu — com a autoria DELE —
/// sem sessão e sem nenhum outro poder: o único uso é `visits.syncDeferred`
/// (e `visits.revokeUploadToken`). Um vigente por (usuário, aparelho): a
/// emissão revoga o anterior. Validade de 7 dias, sem rotação.
///
/// **Nunca** o token: só o SHA-256 dele em hex. O token é 256 bits aleatórios,
/// então um hash simples basta (não há senha humana para adivinhar).
abstract class AcsUploadToken implements _i1.SerializableModel {
  AcsUploadToken._({
    this.id,
    required this.userId,
    required this.tokenHash,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
  });

  factory AcsUploadToken({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime expiresAt,
    DateTime? revokedAt,
  }) = _AcsUploadTokenImpl;

  factory AcsUploadToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return AcsUploadToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      tokenHash: jsonSerialization['tokenHash'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      issuedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['issuedAt'],
      ),
      expiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
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

  String tokenHash;

  /// Instalação que recebeu o token. Token apresentado por outro aparelho é
  /// recusado e revogado.
  String deviceId;

  DateTime issuedAt;

  /// Teto fixo (`issuedAt` + 7 dias); o uso não o estende.
  DateTime expiresAt;

  /// `null` = vigente. Preenchido na revogação (pedido do app, novo login no
  /// mesmo aparelho, aparelho divergente ou conta inativa/sem microárea).
  DateTime? revokedAt;

  /// Returns a shallow copy of this [AcsUploadToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AcsUploadToken copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? expiresAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AcsUploadToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'tokenHash': tokenHash,
      'deviceId': deviceId,
      'issuedAt': issuedAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsUploadTokenImpl extends AcsUploadToken {
  _AcsUploadTokenImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime expiresAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         userId: userId,
         tokenHash: tokenHash,
         deviceId: deviceId,
         issuedAt: issuedAt,
         expiresAt: expiresAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [AcsUploadToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AcsUploadToken copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? expiresAt,
    Object? revokedAt = _Undefined,
  }) {
    return AcsUploadToken(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      tokenHash: tokenHash ?? this.tokenHash,
      deviceId: deviceId ?? this.deviceId,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}
