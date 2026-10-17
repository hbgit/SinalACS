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

/// O aparelho tem um pedido de limpeza remota da coordenação (#81). Login,
/// renovação e envio diferido o recusam com isto, para o app distinguir "limpar
/// o aparelho" de "sessão expirada".
abstract class DeviceWipeRequiredException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  DeviceWipeRequiredException._({
    required this.orderId,
    required this.message,
  });

  factory DeviceWipeRequiredException({
    required String orderId,
    required String message,
  }) = _DeviceWipeRequiredExceptionImpl;

  factory DeviceWipeRequiredException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return DeviceWipeRequiredException(
      orderId: jsonSerialization['orderId'] as String,
      message: jsonSerialization['message'] as String,
    );
  }

  String orderId;

  String message;

  /// Returns a shallow copy of this [DeviceWipeRequiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceWipeRequiredException copyWith({
    String? orderId,
    String? message,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceWipeRequiredException',
      'orderId': orderId,
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceWipeRequiredException',
      'orderId': orderId,
      'message': message,
    };
  }

  @override
  String toString() {
    return 'DeviceWipeRequiredException(orderId: $orderId, message: $message)';
  }
}

class _DeviceWipeRequiredExceptionImpl extends DeviceWipeRequiredException {
  _DeviceWipeRequiredExceptionImpl({
    required String orderId,
    required String message,
  }) : super._(
         orderId: orderId,
         message: message,
       );

  /// Returns a shallow copy of this [DeviceWipeRequiredException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceWipeRequiredException copyWith({
    String? orderId,
    String? message,
  }) {
    return DeviceWipeRequiredException(
      orderId: orderId ?? this.orderId,
      message: message ?? this.message,
    );
  }
}
