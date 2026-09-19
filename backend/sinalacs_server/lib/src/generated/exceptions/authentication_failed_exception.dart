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

/// Credencial institucional recusada (RF07). Uma exceção única para matrícula
/// inexistente, senha errada, conta bloqueada e acesso inativo — de propósito:
/// distinguir "esta matrícula não existe" de "a senha está errada" entrega a
/// quem sonda a lista de matrículas da unidade. O bloqueio e o inativo são
/// distinguidos na MENSAGEM porque só chegam a quem já acertou a senha (o
/// teste de inatividade acontece depois da verificação) ou já estourou o
/// limite com a matrícula certa.
abstract class AuthenticationFailedException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  AuthenticationFailedException._({required this.message});

  factory AuthenticationFailedException({required String message}) =
      _AuthenticationFailedExceptionImpl;

  factory AuthenticationFailedException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AuthenticationFailedException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [AuthenticationFailedException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AuthenticationFailedException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AuthenticationFailedException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AuthenticationFailedException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'AuthenticationFailedException(message: $message)';
  }
}

class _AuthenticationFailedExceptionImpl extends AuthenticationFailedException {
  _AuthenticationFailedExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [AuthenticationFailedException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AuthenticationFailedException copyWith({String? message}) {
    return AuthenticationFailedException(message: message ?? this.message);
  }
}
