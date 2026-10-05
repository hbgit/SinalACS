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
    int? lockStreak,
    required this.createdAt,
    required this.updatedAt,
    this.totpSecretEncrypted,
    this.totpKeyVersion,
    this.totpEnabledAt,
    this.totpLastStep,
  }) : lockStreak = lockStreak ?? 0;

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
    int? lockStreak,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? totpSecretEncrypted,
    int? totpKeyVersion,
    DateTime? totpEnabledAt,
    int? totpLastStep,
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
      lockStreak: jsonSerialization['lockStreak'] as int?,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
      totpSecretEncrypted: jsonSerialization['totpSecretEncrypted'] as String?,
      totpKeyVersion: jsonSerialization['totpKeyVersion'] as int?,
      totpEnabledAt: jsonSerialization['totpEnabledAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['totpEnabledAt'],
            ),
      totpLastStep: jsonSerialization['totpLastStep'] as int?,
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

  /// Rodadas de bloqueio seguidas, sem um login válido no meio. Alimenta o
  /// bloqueio progressivo (15 min x 2^lockStreak, teto 24 h). Zera no login válido.
  int lockStreak;

  DateTime createdAt;

  DateTime updatedAt;

  /// MFA por TOTP (RFC 6238). `null` = sem segredo gravado. O segredo é cifrado
  /// (AES-256-GCM, a mesma chave dos dados clínicos); **nunca** em claro.
  String? totpSecretEncrypted;

  int? totpKeyVersion;

  /// `null` = enrollment começou e não foi confirmado: a MFA ainda NÃO vale.
  DateTime? totpEnabledAt;

  /// Último passo de 30 s aceito. O mesmo código não entra duas vezes (replay).
  int? totpLastStep;

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
    int? lockStreak,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? totpSecretEncrypted,
    int? totpKeyVersion,
    DateTime? totpEnabledAt,
    int? totpLastStep,
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
      'lockStreak': lockStreak,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
      if (totpSecretEncrypted != null)
        'totpSecretEncrypted': totpSecretEncrypted,
      if (totpKeyVersion != null) 'totpKeyVersion': totpKeyVersion,
      if (totpEnabledAt != null) 'totpEnabledAt': totpEnabledAt?.toJson(),
      if (totpLastStep != null) 'totpLastStep': totpLastStep,
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
    int? lockStreak,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? totpSecretEncrypted,
    int? totpKeyVersion,
    DateTime? totpEnabledAt,
    int? totpLastStep,
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
         lockStreak: lockStreak,
         createdAt: createdAt,
         updatedAt: updatedAt,
         totpSecretEncrypted: totpSecretEncrypted,
         totpKeyVersion: totpKeyVersion,
         totpEnabledAt: totpEnabledAt,
         totpLastStep: totpLastStep,
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
    int? lockStreak,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? totpSecretEncrypted = _Undefined,
    Object? totpKeyVersion = _Undefined,
    Object? totpEnabledAt = _Undefined,
    Object? totpLastStep = _Undefined,
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
      lockStreak: lockStreak ?? this.lockStreak,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totpSecretEncrypted: totpSecretEncrypted is String?
          ? totpSecretEncrypted
          : this.totpSecretEncrypted,
      totpKeyVersion: totpKeyVersion is int?
          ? totpKeyVersion
          : this.totpKeyVersion,
      totpEnabledAt: totpEnabledAt is DateTime?
          ? totpEnabledAt
          : this.totpEnabledAt,
      totpLastStep: totpLastStep is int? ? totpLastStep : this.totpLastStep,
    );
  }
}
