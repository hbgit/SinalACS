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

/// Convite de uso único gerado pelo ACS para um paciente já cadastrado em
/// sua microárea concluir o onboarding no próprio aparelho. Não cria
/// identidade nova (RF01/RF07 — autenticação institucional — segue sem
/// decisão própria); ativa o acesso de um paciente que já existe em
/// `patients`, na microárea de quem gerou o convite.
abstract class EnrollmentToken implements _i1.SerializableModel {
  EnrollmentToken._({
    this.id,
    required this.tokenHash,
    required this.patientId,
    required this.microAreaId,
    required this.createdByAcsId,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
  });

  factory EnrollmentToken({
    _i1.UuidValue? id,
    required String tokenHash,
    required _i1.UuidValue patientId,
    required _i1.UuidValue microAreaId,
    required _i1.UuidValue createdByAcsId,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) = _EnrollmentTokenImpl;

  factory EnrollmentToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return EnrollmentToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      tokenHash: jsonSerialization['tokenHash'] as String,
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      microAreaId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['microAreaId'],
      ),
      createdByAcsId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['createdByAcsId'],
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      expiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      consumedAt: jsonSerialization['consumedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['consumedAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  /// sha256 do token real. O valor em claro só existe no momento da geração
  /// (devolvido ao ACS para virar QR Code) e nunca é persistido — mesmo
  /// padrão de `users.cpfHash`.
  String tokenHash;

  _i1.UuidValue patientId;

  _i1.UuidValue microAreaId;

  _i1.UuidValue createdByAcsId;

  DateTime createdAt;

  DateTime expiresAt;

  /// Marca o consumo atômico. `null` = ainda válido para uso.
  DateTime? consumedAt;

  /// Returns a shallow copy of this [EnrollmentToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  EnrollmentToken copyWith({
    _i1.UuidValue? id,
    String? tokenHash,
    _i1.UuidValue? patientId,
    _i1.UuidValue? microAreaId,
    _i1.UuidValue? createdByAcsId,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? consumedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EnrollmentToken',
      if (id != null) 'id': id?.toJson(),
      'tokenHash': tokenHash,
      'patientId': patientId.toJson(),
      'microAreaId': microAreaId.toJson(),
      'createdByAcsId': createdByAcsId.toJson(),
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _EnrollmentTokenImpl extends EnrollmentToken {
  _EnrollmentTokenImpl({
    _i1.UuidValue? id,
    required String tokenHash,
    required _i1.UuidValue patientId,
    required _i1.UuidValue microAreaId,
    required _i1.UuidValue createdByAcsId,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) : super._(
         id: id,
         tokenHash: tokenHash,
         patientId: patientId,
         microAreaId: microAreaId,
         createdByAcsId: createdByAcsId,
         createdAt: createdAt,
         expiresAt: expiresAt,
         consumedAt: consumedAt,
       );

  /// Returns a shallow copy of this [EnrollmentToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  EnrollmentToken copyWith({
    Object? id = _Undefined,
    String? tokenHash,
    _i1.UuidValue? patientId,
    _i1.UuidValue? microAreaId,
    _i1.UuidValue? createdByAcsId,
    DateTime? createdAt,
    DateTime? expiresAt,
    Object? consumedAt = _Undefined,
  }) {
    return EnrollmentToken(
      id: id is _i1.UuidValue? ? id : this.id,
      tokenHash: tokenHash ?? this.tokenHash,
      patientId: patientId ?? this.patientId,
      microAreaId: microAreaId ?? this.microAreaId,
      createdByAcsId: createdByAcsId ?? this.createdByAcsId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt is DateTime? ? consumedAt : this.consumedAt,
    );
  }
}
