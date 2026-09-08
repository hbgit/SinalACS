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

/// Papel ou território incompatível com a operação (INV-01, INV-02).
/// Substitui o StateError que o servidor dart:io mapeava para HTTP 403.
abstract class AlertPermissionException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  AlertPermissionException._({required this.message});

  factory AlertPermissionException({required String message}) =
      _AlertPermissionExceptionImpl;

  factory AlertPermissionException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AlertPermissionException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [AlertPermissionException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertPermissionException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertPermissionException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AlertPermissionException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'AlertPermissionException(message: $message)';
  }
}

class _AlertPermissionExceptionImpl extends AlertPermissionException {
  _AlertPermissionExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [AlertPermissionException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertPermissionException copyWith({String? message}) {
    return AlertPermissionException(message: message ?? this.message);
  }
}
