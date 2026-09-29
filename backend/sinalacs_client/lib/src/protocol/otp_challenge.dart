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

/// Desafio de código OTP do login passwordless (RF01).
///
/// Mesmo padrão de hash-só de `enrollment_tokens`: o código em claro existe
/// apenas no momento da geração (enviado por SMS) e nunca é persistido. A
/// tabela guarda o HMAC, para que um dump do banco não entregue códigos
/// válidos de pacientes que estão tentando entrar agora.
abstract class OtpChallenge implements _i1.SerializableModel {
  OtpChallenge._({
    this.id,
    required this.userId,
    required this.codeHash,
    required this.attempts,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
  });

  factory OtpChallenge({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String codeHash,
    required int attempts,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) = _OtpChallengeImpl;

  factory OtpChallenge.fromJson(Map<String, dynamic> jsonSerialization) {
    return OtpChallenge(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      codeHash: jsonSerialization['codeHash'] as String,
      attempts: jsonSerialization['attempts'] as int,
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

  _i1.UuidValue userId;

  /// HMAC-SHA-256 do código, com campo de domínio próprio (ver HmacCpfHasher).
  String codeHash;

  /// Tentativas de verificação já gastas. O código morre ao atingir o limite,
  /// mesmo antes de expirar — 6 dígitos são 10^6 combinações, e sem contador
  /// um atacante com um código enviado teria tentativas ilimitadas.
  int attempts;

  DateTime createdAt;

  DateTime expiresAt;

  /// Marca o consumo. `null` = ainda válido; nunca consumido = o desafio mais
  /// recente do paciente é o que vale.
  DateTime? consumedAt;

  /// Returns a shallow copy of this [OtpChallenge]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  OtpChallenge copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? codeHash,
    int? attempts,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? consumedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'OtpChallenge',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'codeHash': codeHash,
      'attempts': attempts,
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

class _OtpChallengeImpl extends OtpChallenge {
  _OtpChallengeImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String codeHash,
    required int attempts,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) : super._(
         id: id,
         userId: userId,
         codeHash: codeHash,
         attempts: attempts,
         createdAt: createdAt,
         expiresAt: expiresAt,
         consumedAt: consumedAt,
       );

  /// Returns a shallow copy of this [OtpChallenge]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  OtpChallenge copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? codeHash,
    int? attempts,
    DateTime? createdAt,
    DateTime? expiresAt,
    Object? consumedAt = _Undefined,
  }) {
    return OtpChallenge(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      codeHash: codeHash ?? this.codeHash,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt is DateTime? ? consumedAt : this.consumedAt,
    );
  }
}
