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

/// Endpoint desabilitado por configuração. Preserva a semântica do
/// ENABLE_DEV_LOGIN, que respondia 404 (e não 403) quando desligado, para não
/// revelar a existência da rota.
abstract class EndpointDisabledException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  EndpointDisabledException._({required this.message});

  factory EndpointDisabledException({required String message}) =
      _EndpointDisabledExceptionImpl;

  factory EndpointDisabledException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return EndpointDisabledException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [EndpointDisabledException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  EndpointDisabledException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EndpointDisabledException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'EndpointDisabledException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'EndpointDisabledException(message: $message)';
  }
}

class _EndpointDisabledExceptionImpl extends EndpointDisabledException {
  _EndpointDisabledExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [EndpointDisabledException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  EndpointDisabledException copyWith({String? message}) {
    return EndpointDisabledException(message: message ?? this.message);
  }
}
