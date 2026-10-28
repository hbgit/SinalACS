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

import 'package:serverpod/serverpod.dart' as _i1;

/// Resposta de `devices.issueCertificate` (#94): a folha assinada, a serial e
/// a validade. `serverNow` deixa o app medir o desvio do próprio relógio antes
/// de decidir quando renovar.
abstract class DeviceCertificateIssueResult
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  DeviceCertificateIssueResult._({
    required this.certificatePem,
    required this.serial,
    required this.notAfter,
    required this.serverNow,
  });

  factory DeviceCertificateIssueResult({
    required String certificatePem,
    required String serial,
    required DateTime notAfter,
    required DateTime serverNow,
  }) = _DeviceCertificateIssueResultImpl;

  factory DeviceCertificateIssueResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return DeviceCertificateIssueResult(
      certificatePem: jsonSerialization['certificatePem'] as String,
      serial: jsonSerialization['serial'] as String,
      notAfter: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['notAfter'],
      ),
      serverNow: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['serverNow'],
      ),
    );
  }

  String certificatePem;

  String serial;

  DateTime notAfter;

  DateTime serverNow;

  /// Returns a shallow copy of this [DeviceCertificateIssueResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCertificateIssueResult copyWith({
    String? certificatePem,
    String? serial,
    DateTime? notAfter,
    DateTime? serverNow,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCertificateIssueResult',
      'certificatePem': certificatePem,
      'serial': serial,
      'notAfter': notAfter.toJson(),
      'serverNow': serverNow.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceCertificateIssueResult',
      'certificatePem': certificatePem,
      'serial': serial,
      'notAfter': notAfter.toJson(),
      'serverNow': serverNow.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _DeviceCertificateIssueResultImpl extends DeviceCertificateIssueResult {
  _DeviceCertificateIssueResultImpl({
    required String certificatePem,
    required String serial,
    required DateTime notAfter,
    required DateTime serverNow,
  }) : super._(
         certificatePem: certificatePem,
         serial: serial,
         notAfter: notAfter,
         serverNow: serverNow,
       );

  /// Returns a shallow copy of this [DeviceCertificateIssueResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCertificateIssueResult copyWith({
    String? certificatePem,
    String? serial,
    DateTime? notAfter,
    DateTime? serverNow,
  }) {
    return DeviceCertificateIssueResult(
      certificatePem: certificatePem ?? this.certificatePem,
      serial: serial ?? this.serial,
      notAfter: notAfter ?? this.notAfter,
      serverNow: serverNow ?? this.serverNow,
    );
  }
}
