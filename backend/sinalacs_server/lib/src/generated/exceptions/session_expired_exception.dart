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

/// O refresh token não vale mais (expirado, revogado, reusado, de outro
/// aparelho ou de conta desativada). Mensagem única de propósito: o motivo
/// real fica só em audit_logs.
abstract class SessionExpiredException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  SessionExpiredException._({required this.message});

  factory SessionExpiredException({required String message}) =
      _SessionExpiredExceptionImpl;

  factory SessionExpiredException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return SessionExpiredException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [SessionExpiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  SessionExpiredException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SessionExpiredException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'SessionExpiredException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'SessionExpiredException(message: $message)';
  }
}

class _SessionExpiredExceptionImpl extends SessionExpiredException {
  _SessionExpiredExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [SessionExpiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  SessionExpiredException copyWith({String? message}) {
    return SessionExpiredException(message: message ?? this.message);
  }
}
