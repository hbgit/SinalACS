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

/// Parâmetro do backoffice fora do intervalo (por exemplo, `limit` de paginação).
/// Não é erro de permissão.
abstract class AdminInvalidRequestException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  AdminInvalidRequestException._({required this.message});

  factory AdminInvalidRequestException({required String message}) =
      _AdminInvalidRequestExceptionImpl;

  factory AdminInvalidRequestException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminInvalidRequestException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [AdminInvalidRequestException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminInvalidRequestException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminInvalidRequestException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminInvalidRequestException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'AdminInvalidRequestException(message: $message)';
  }
}

class _AdminInvalidRequestExceptionImpl extends AdminInvalidRequestException {
  _AdminInvalidRequestExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [AdminInvalidRequestException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminInvalidRequestException copyWith({String? message}) {
    return AdminInvalidRequestException(message: message ?? this.message);
  }
}
