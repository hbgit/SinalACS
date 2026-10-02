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

/// O servidor exige MFA e este ACS ainda não a ativou: a pessoa precisa
/// ativar (auth.beginTotpEnrollment) antes de entrar.
abstract class MfaEnrollmentRequiredException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  MfaEnrollmentRequiredException._({required this.message});

  factory MfaEnrollmentRequiredException({required String message}) =
      _MfaEnrollmentRequiredExceptionImpl;

  factory MfaEnrollmentRequiredException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return MfaEnrollmentRequiredException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [MfaEnrollmentRequiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  MfaEnrollmentRequiredException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MfaEnrollmentRequiredException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MfaEnrollmentRequiredException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'MfaEnrollmentRequiredException(message: $message)';
  }
}

class _MfaEnrollmentRequiredExceptionImpl
    extends MfaEnrollmentRequiredException {
  _MfaEnrollmentRequiredExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [MfaEnrollmentRequiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  MfaEnrollmentRequiredException copyWith({String? message}) {
    return MfaEnrollmentRequiredException(message: message ?? this.message);
  }
}
