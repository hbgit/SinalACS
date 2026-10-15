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

/// O ACS tem MFA ativa, a senha conferiu e faltou o código do autenticador.
/// Só é lançada DEPOIS de a senha estar certa: não revela matrícula nem senha.
abstract class MfaRequiredException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  MfaRequiredException._({required this.message});

  factory MfaRequiredException({required String message}) =
      _MfaRequiredExceptionImpl;

  factory MfaRequiredException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return MfaRequiredException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [MfaRequiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  MfaRequiredException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MfaRequiredException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MfaRequiredException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'MfaRequiredException(message: $message)';
  }
}

class _MfaRequiredExceptionImpl extends MfaRequiredException {
  _MfaRequiredExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [MfaRequiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  MfaRequiredException copyWith({String? message}) {
    return MfaRequiredException(message: message ?? this.message);
  }
}
