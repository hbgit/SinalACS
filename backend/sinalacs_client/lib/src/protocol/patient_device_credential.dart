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

/// Credencial de dispositivo do participante (C-05, RF24).
///
/// O convite QR do agente (enrollment_tokens) vira, ao ser concluído, uma
/// credencial de longa duração amarrada a ESTE aparelho: o app gera um
/// `deviceId` (UUID aleatório de instalação — nunca um identificador de
/// hardware, spec/lgpd_data_audit.md §2.4) e um segredo aleatório de 32
/// bytes; o servidor guarda só o hash do segredo, e o app guarda o segredo
/// protegido pelo PIN local (Argon2id + AES-GCM, no Keystore do aparelho).
/// O PIN nunca sai do aparelho: o login seguinte (`auth.loginDevice`)
/// apresenta deviceId + segredo, e o JWT sai com o device_id da credencial.
///
/// `revokedAt` é a invalidação da credencial: hoje quem a grava é a exclusão
/// atendida da #42 (anonimização do titular, na mesma transação da decisão);
/// a C-12 (#133) vai usá-la na reemissão de convite — ainda não implementada.
/// Um aparelho revogado recebe a mesma recusa de um segredo errado.
abstract class PatientDeviceCredential implements _i1.SerializableModel {
  PatientDeviceCredential._({
    this.id,
    required this.patientId,
    required this.deviceId,
    required this.credentialHash,
    required this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  factory PatientDeviceCredential({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required String deviceId,
    required String credentialHash,
    required DateTime createdAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) = _PatientDeviceCredentialImpl;

  factory PatientDeviceCredential.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return PatientDeviceCredential(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      deviceId: jsonSerialization['deviceId'] as String,
      credentialHash: jsonSerialization['credentialHash'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      lastUsedAt: jsonSerialization['lastUsedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['lastUsedAt']),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  /// Dono da credencial — o identificador pseudônimo do participante
  /// (`users.id`/`patients.id`; sem CPF desde C-05).
  _i1.UuidValue patientId;

  /// UUID minúsculo de instalação, validado em `isDeviceIdFormat`. Único:
  /// um aparelho não pode ter duas credenciais vivas, e a reemissão grava
  /// uma linha nova com outro deviceId (C-12).
  String deviceId;

  /// SHA-256 (hex) de `sinalacs-pdc-v1:<segredo>` — o segredo tem 256 bits
  /// de entropia, então hash rápido basta; nunca em claro.
  String credentialHash;

  DateTime createdAt;

  /// Atualizado a cada `auth.loginDevice` bem-sucedido (LGPD-RT06: retenção
  /// do acesso do titular).
  DateTime? lastUsedAt;

  /// `null` = credencial viva. Preenchido pela C-12 (novo convite revoga a
  /// credencial anterior do mesmo paciente).
  DateTime? revokedAt;

  /// Returns a shallow copy of this [PatientDeviceCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PatientDeviceCredential copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    String? deviceId,
    String? credentialHash,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PatientDeviceCredential',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'deviceId': deviceId,
      'credentialHash': credentialHash,
      'createdAt': createdAt.toJson(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PatientDeviceCredentialImpl extends PatientDeviceCredential {
  _PatientDeviceCredentialImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required String deviceId,
    required String credentialHash,
    required DateTime createdAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         patientId: patientId,
         deviceId: deviceId,
         credentialHash: credentialHash,
         createdAt: createdAt,
         lastUsedAt: lastUsedAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [PatientDeviceCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PatientDeviceCredential copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    String? deviceId,
    String? credentialHash,
    DateTime? createdAt,
    Object? lastUsedAt = _Undefined,
    Object? revokedAt = _Undefined,
  }) {
    return PatientDeviceCredential(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      deviceId: deviceId ?? this.deviceId,
      credentialHash: credentialHash ?? this.credentialHash,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt is DateTime? ? lastUsedAt : this.lastUsedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}
