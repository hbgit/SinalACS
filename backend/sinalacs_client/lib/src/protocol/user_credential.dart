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

/// Credencial de login institucional (RF07). Uma linha por usuário, 1:1 com
/// `users` — o `userId` tem índice único.
///
/// Tabela própria em vez de colunas em `acs` por três motivos: a senha não é
/// dado de domínio do ACS (um coordenador ou administrador passa a ter
/// credencial sem que a tabela `acs` ganhe uma linha que não é dele), os
/// parâmetros do Argon2id precisam viajar com o hash, e o contador de
/// tentativas é estado de autenticação, não de territorialização.
abstract class UserCredential implements _i1.SerializableModel {
  UserCredential._({
    this.id,
    required this.userId,
    required this.passwordHash,
    required this.passwordSalt,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
    required this.failedAttempts,
    this.lockedUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserCredential({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String passwordHash,
    required String passwordSalt,
    required int memoryKb,
    required int iterations,
    required int parallelism,
    required int failedAttempts,
    DateTime? lockedUntil,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _UserCredentialImpl;

  factory UserCredential.fromJson(Map<String, dynamic> jsonSerialization) {
    return UserCredential(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      passwordHash: jsonSerialization['passwordHash'] as String,
      passwordSalt: jsonSerialization['passwordSalt'] as String,
      memoryKb: jsonSerialization['memoryKb'] as int,
      iterations: jsonSerialization['iterations'] as int,
      parallelism: jsonSerialization['parallelism'] as int,
      failedAttempts: jsonSerialization['failedAttempts'] as int,
      lockedUntil: jsonSerialization['lockedUntil'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['lockedUntil'],
            ),
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

  /// Argon2id em base64. **Nunca** a senha.
  String passwordHash;

  /// Salt por credencial, em base64. Guardado junto do hash porque a
  /// verificação precisa dele — e ao lado dos parâmetros, para que subir o
  /// custo não invalide as credenciais já emitidas.
  String passwordSalt;

  int memoryKb;

  int iterations;

  int parallelism;

  /// Estado do bloqueio por tentativas (achado F6). Zera no login bem-sucedido.
  int failedAttempts;

  /// `null` = não bloqueado.
  DateTime? lockedUntil;

  DateTime createdAt;

  DateTime updatedAt;

  /// Returns a shallow copy of this [UserCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  UserCredential copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? passwordHash,
    String? passwordSalt,
    int? memoryKb,
    int? iterations,
    int? parallelism,
    int? failedAttempts,
    DateTime? lockedUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'UserCredential',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'passwordHash': passwordHash,
      'passwordSalt': passwordSalt,
      'memoryKb': memoryKb,
      'iterations': iterations,
      'parallelism': parallelism,
      'failedAttempts': failedAttempts,
      if (lockedUntil != null) 'lockedUntil': lockedUntil?.toJson(),
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

class _UserCredentialImpl extends UserCredential {
  _UserCredentialImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String passwordHash,
    required String passwordSalt,
    required int memoryKb,
    required int iterations,
    required int parallelism,
    required int failedAttempts,
    DateTime? lockedUntil,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         userId: userId,
         passwordHash: passwordHash,
         passwordSalt: passwordSalt,
         memoryKb: memoryKb,
         iterations: iterations,
         parallelism: parallelism,
         failedAttempts: failedAttempts,
         lockedUntil: lockedUntil,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [UserCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  UserCredential copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? passwordHash,
    String? passwordSalt,
    int? memoryKb,
    int? iterations,
    int? parallelism,
    int? failedAttempts,
    Object? lockedUntil = _Undefined,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserCredential(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      memoryKb: memoryKb ?? this.memoryKb,
      iterations: iterations ?? this.iterations,
      parallelism: parallelism ?? this.parallelism,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: lockedUntil is DateTime? ? lockedUntil : this.lockedUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
