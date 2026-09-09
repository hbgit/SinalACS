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

/// Dados obrigatórios ausentes ou inválidos.
/// Substitui o ArgumentError que o servidor dart:io mapeava para HTTP 400.
abstract class AlertValidationException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  AlertValidationException._({required this.message});

  factory AlertValidationException({required String message}) =
      _AlertValidationExceptionImpl;

  factory AlertValidationException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AlertValidationException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [AlertValidationException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertValidationException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertValidationException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AlertValidationException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'AlertValidationException(message: $message)';
  }
}

class _AlertValidationExceptionImpl extends AlertValidationException {
  _AlertValidationExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [AlertValidationException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertValidationException copyWith({String? message}) {
    return AlertValidationException(message: message ?? this.message);
  }
}
