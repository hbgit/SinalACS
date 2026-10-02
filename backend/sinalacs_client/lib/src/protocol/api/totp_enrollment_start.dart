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

/// Início da ativação da MFA: o segredo para o autenticador (base32) e a URI
/// `otpauth://` que vira o QR. Volta só nesta resposta; nunca é gravado em claro.
abstract class TotpEnrollmentStart implements _i1.SerializableModel {
  TotpEnrollmentStart._({
    required this.secretBase32,
    required this.otpauthUri,
  });

  factory TotpEnrollmentStart({
    required String secretBase32,
    required String otpauthUri,
  }) = _TotpEnrollmentStartImpl;

  factory TotpEnrollmentStart.fromJson(Map<String, dynamic> jsonSerialization) {
    return TotpEnrollmentStart(
      secretBase32: jsonSerialization['secretBase32'] as String,
      otpauthUri: jsonSerialization['otpauthUri'] as String,
    );
  }

  String secretBase32;

  String otpauthUri;

  /// Returns a shallow copy of this [TotpEnrollmentStart]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TotpEnrollmentStart copyWith({
    String? secretBase32,
    String? otpauthUri,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TotpEnrollmentStart',
      'secretBase32': secretBase32,
      'otpauthUri': otpauthUri,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TotpEnrollmentStartImpl extends TotpEnrollmentStart {
  _TotpEnrollmentStartImpl({
    required String secretBase32,
    required String otpauthUri,
  }) : super._(
         secretBase32: secretBase32,
         otpauthUri: otpauthUri,
       );

  /// Returns a shallow copy of this [TotpEnrollmentStart]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TotpEnrollmentStart copyWith({
    String? secretBase32,
    String? otpauthUri,
  }) {
    return TotpEnrollmentStart(
      secretBase32: secretBase32 ?? this.secretBase32,
      otpauthUri: otpauthUri ?? this.otpauthUri,
    );
  }
}
