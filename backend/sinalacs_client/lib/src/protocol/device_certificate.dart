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
import 'enums/device_cert_revocation_reason.dart' as _i2;

/// Certificado de cliente MQTT emitido para um aparelho do ACS (#94). Em regra
/// um ativo por aparelho: a emissão nova revoga a anterior (`renewed`); duas
/// emissões concorrentes do mesmo aparelho podem coexistir, e a revogação por
/// aparelho revoga todas.
///
/// Só identificadores técnicos, sem dado pessoal além do `userId` do ACS (o
/// profissional, não o titular): o `deviceId` é o UUID aleatório da
/// instalação, a `serial` são 128 bits com versão/variante de UUID v4 fixos
/// (122 aleatórios) em hex minúsculo com 32 dígitos, e a impressão digital é o SHA-256 do DER da folha. O certificado
/// em si não é guardado: a revogação só precisa da serial.
///
/// Retenção: até `notAfter` + 30 dias (a CRL só lista as não vencidas);
/// o expurgo é pendência (`PROGRESS.md`).
abstract class DeviceCertificate implements _i1.SerializableModel {
  DeviceCertificate._({
    this.id,
    required this.userId,
    required this.deviceId,
    required this.microAreaId,
    required this.serial,
    required this.fingerprintSha256,
    required this.notBefore,
    required this.notAfter,
    required this.issuedAt,
    this.revokedAt,
    this.revocationReason,
  });

  factory DeviceCertificate({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String deviceId,
    required _i1.UuidValue microAreaId,
    required String serial,
    required String fingerprintSha256,
    required DateTime notBefore,
    required DateTime notAfter,
    required DateTime issuedAt,
    DateTime? revokedAt,
    _i2.DeviceCertRevocationReason? revocationReason,
  }) = _DeviceCertificateImpl;

  factory DeviceCertificate.fromJson(Map<String, dynamic> jsonSerialization) {
    return DeviceCertificate(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      deviceId: jsonSerialization['deviceId'] as String,
      microAreaId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['microAreaId'],
      ),
      serial: jsonSerialization['serial'] as String,
      fingerprintSha256: jsonSerialization['fingerprintSha256'] as String,
      notBefore: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['notBefore'],
      ),
      notAfter: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['notAfter'],
      ),
      issuedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['issuedAt'],
      ),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
      revocationReason: jsonSerialization['revocationReason'] == null
          ? null
          : _i2.DeviceCertRevocationReason.fromJson(
              (jsonSerialization['revocationReason'] as String),
            ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  /// O ACS da sessão que pediu a emissão.
  _i1.UuidValue userId;

  /// Instalação que recebeu o certificado (o `deviceId` do token).
  String deviceId;

  /// A microárea da conta relida do banco na emissão (igual à do token, ou a
  /// emissão é recusada); é o CN da folha.
  _i1.UuidValue microAreaId;

  String serial;

  String fingerprintSha256;

  DateTime notBefore;

  DateTime notAfter;

  DateTime issuedAt;

  /// `null` = vigente.
  DateTime? revokedAt;

  _i2.DeviceCertRevocationReason? revocationReason;

  /// Returns a shallow copy of this [DeviceCertificate]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCertificate copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? deviceId,
    _i1.UuidValue? microAreaId,
    String? serial,
    String? fingerprintSha256,
    DateTime? notBefore,
    DateTime? notAfter,
    DateTime? issuedAt,
    DateTime? revokedAt,
    _i2.DeviceCertRevocationReason? revocationReason,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCertificate',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'deviceId': deviceId,
      'microAreaId': microAreaId.toJson(),
      'serial': serial,
      'fingerprintSha256': fingerprintSha256,
      'notBefore': notBefore.toJson(),
      'notAfter': notAfter.toJson(),
      'issuedAt': issuedAt.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
      if (revocationReason != null)
        'revocationReason': revocationReason?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DeviceCertificateImpl extends DeviceCertificate {
  _DeviceCertificateImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String deviceId,
    required _i1.UuidValue microAreaId,
    required String serial,
    required String fingerprintSha256,
    required DateTime notBefore,
    required DateTime notAfter,
    required DateTime issuedAt,
    DateTime? revokedAt,
    _i2.DeviceCertRevocationReason? revocationReason,
  }) : super._(
         id: id,
         userId: userId,
         deviceId: deviceId,
         microAreaId: microAreaId,
         serial: serial,
         fingerprintSha256: fingerprintSha256,
         notBefore: notBefore,
         notAfter: notAfter,
         issuedAt: issuedAt,
         revokedAt: revokedAt,
         revocationReason: revocationReason,
       );

  /// Returns a shallow copy of this [DeviceCertificate]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCertificate copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? deviceId,
    _i1.UuidValue? microAreaId,
    String? serial,
    String? fingerprintSha256,
    DateTime? notBefore,
    DateTime? notAfter,
    DateTime? issuedAt,
    Object? revokedAt = _Undefined,
    Object? revocationReason = _Undefined,
  }) {
    return DeviceCertificate(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      microAreaId: microAreaId ?? this.microAreaId,
      serial: serial ?? this.serial,
      fingerprintSha256: fingerprintSha256 ?? this.fingerprintSha256,
      notBefore: notBefore ?? this.notBefore,
      notAfter: notAfter ?? this.notAfter,
      issuedAt: issuedAt ?? this.issuedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
      revocationReason: revocationReason is _i2.DeviceCertRevocationReason?
          ? revocationReason
          : this.revocationReason,
    );
  }
}
