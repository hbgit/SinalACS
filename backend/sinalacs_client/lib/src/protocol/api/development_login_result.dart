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

/// Token de desenvolvimento. Não é autenticação institucional.
abstract class DevelopmentLoginResult implements _i1.SerializableModel {
  DevelopmentLoginResult._({
    required this.accessToken,
    required this.tokenType,
    this.refreshToken,
    this.uploadToken,
  });

  factory DevelopmentLoginResult({
    required String accessToken,
    required String tokenType,
    String? refreshToken,
    String? uploadToken,
  }) = _DevelopmentLoginResultImpl;

  factory DevelopmentLoginResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return DevelopmentLoginResult(
      accessToken: jsonSerialization['accessToken'] as String,
      tokenType: jsonSerialization['tokenType'] as String,
      refreshToken: jsonSerialization['refreshToken'] as String?,
      uploadToken: jsonSerialization['uploadToken'] as String?,
    );
  }

  String accessToken;

  String tokenType;

  /// Só no `loginInstitutional` e no `refreshSession`. `null` nos demais
  /// emissores (paciente, `developmentLogin`).
  String? refreshToken;

  /// Token de envio diferido (D7): só no `loginInstitutional` com `deviceId`
  /// real. Serve apenas a `visits.syncDeferred`/`visits.revokeUploadToken`.
  /// `null` em todos os outros emissores (paciente, `developmentLogin`,
  /// `refreshSession`).
  String? uploadToken;

  /// Returns a shallow copy of this [DevelopmentLoginResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DevelopmentLoginResult copyWith({
    String? accessToken,
    String? tokenType,
    String? refreshToken,
    String? uploadToken,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DevelopmentLoginResult',
      'accessToken': accessToken,
      'tokenType': tokenType,
      if (refreshToken != null) 'refreshToken': refreshToken,
      if (uploadToken != null) 'uploadToken': uploadToken,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DevelopmentLoginResultImpl extends DevelopmentLoginResult {
  _DevelopmentLoginResultImpl({
    required String accessToken,
    required String tokenType,
    String? refreshToken,
    String? uploadToken,
  }) : super._(
         accessToken: accessToken,
         tokenType: tokenType,
         refreshToken: refreshToken,
         uploadToken: uploadToken,
       );

  /// Returns a shallow copy of this [DevelopmentLoginResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DevelopmentLoginResult copyWith({
    String? accessToken,
    String? tokenType,
    Object? refreshToken = _Undefined,
    Object? uploadToken = _Undefined,
  }) {
    return DevelopmentLoginResult(
      accessToken: accessToken ?? this.accessToken,
      tokenType: tokenType ?? this.tokenType,
      refreshToken: refreshToken is String? ? refreshToken : this.refreshToken,
      uploadToken: uploadToken is String? ? uploadToken : this.uploadToken,
    );
  }
}
