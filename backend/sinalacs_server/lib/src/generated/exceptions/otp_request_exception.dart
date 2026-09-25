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

/// Recusa do fluxo OTP (RF01): entrada inválida, limite de tentativas, código
/// expirado ou nenhum código pendente. Uma exceção só, pelo mesmo motivo de
/// `AuthenticationFailedException` — a resposta não pode revelar se aquele CPF
/// está cadastrado.
abstract class OtpRequestException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  OtpRequestException._({required this.message});

  factory OtpRequestException({required String message}) =
      _OtpRequestExceptionImpl;

  factory OtpRequestException.fromJson(Map<String, dynamic> jsonSerialization) {
    return OtpRequestException(message: jsonSerialization['message'] as String);
  }

  String message;

  /// Returns a shallow copy of this [OtpRequestException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  OtpRequestException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'OtpRequestException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'OtpRequestException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'OtpRequestException(message: $message)';
  }
}

class _OtpRequestExceptionImpl extends OtpRequestException {
  _OtpRequestExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [OtpRequestException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  OtpRequestException copyWith({String? message}) {
    return OtpRequestException(message: message ?? this.message);
  }
}
