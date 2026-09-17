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

/// Resultado da geração de um convite de onboarding pelo ACS.
abstract class EnrollmentTokenResult implements _i1.SerializableModel {
  EnrollmentTokenResult._({
    required this.token,
    required this.expiresAt,
  });

  factory EnrollmentTokenResult({
    required String token,
    required DateTime expiresAt,
  }) = _EnrollmentTokenResultImpl;

  factory EnrollmentTokenResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return EnrollmentTokenResult(
      token: jsonSerialization['token'] as String,
      expiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
    );
  }

  /// Valor em claro, de uso único — só existe nesta resposta. Vira o
  /// conteúdo do QR Code exibido ao paciente.
  String token;

  DateTime expiresAt;

  /// Returns a shallow copy of this [EnrollmentTokenResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  EnrollmentTokenResult copyWith({
    String? token,
    DateTime? expiresAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EnrollmentTokenResult',
      'token': token,
      'expiresAt': expiresAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _EnrollmentTokenResultImpl extends EnrollmentTokenResult {
  _EnrollmentTokenResultImpl({
    required String token,
    required DateTime expiresAt,
  }) : super._(
         token: token,
         expiresAt: expiresAt,
       );

  /// Returns a shallow copy of this [EnrollmentTokenResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  EnrollmentTokenResult copyWith({
    String? token,
    DateTime? expiresAt,
  }) {
    return EnrollmentTokenResult(
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
