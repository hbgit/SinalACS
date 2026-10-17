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

import 'package:serverpod_client/serverpod_client.dart' as _i1;

/// Resposta do pedido de limpeza remota (#81). Repetir o pedido é idempotente:
/// `alreadyOrdered` e o `requestedAt` original.
abstract class AdminDeviceWipeResult implements _i1.SerializableModel {
  AdminDeviceWipeResult._({
    required this.orderId,
    required this.requestedAt,
    required this.alreadyOrdered,
  });

  factory AdminDeviceWipeResult({
    required String orderId,
    required DateTime requestedAt,
    required bool alreadyOrdered,
  }) = _AdminDeviceWipeResultImpl;

  factory AdminDeviceWipeResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminDeviceWipeResult(
      orderId: jsonSerialization['orderId'] as String,
      requestedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['requestedAt'],
      ),
      alreadyOrdered: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['alreadyOrdered'],
      ),
    );
  }

  String orderId;

  DateTime requestedAt;

  bool alreadyOrdered;

  /// Returns a shallow copy of this [AdminDeviceWipeResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminDeviceWipeResult copyWith({
    String? orderId,
    DateTime? requestedAt,
    bool? alreadyOrdered,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminDeviceWipeResult',
      'orderId': orderId,
      'requestedAt': requestedAt.toJson(),
      'alreadyOrdered': alreadyOrdered,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminDeviceWipeResultImpl extends AdminDeviceWipeResult {
  _AdminDeviceWipeResultImpl({
    required String orderId,
    required DateTime requestedAt,
    required bool alreadyOrdered,
  }) : super._(
         orderId: orderId,
         requestedAt: requestedAt,
         alreadyOrdered: alreadyOrdered,
       );

  /// Returns a shallow copy of this [AdminDeviceWipeResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminDeviceWipeResult copyWith({
    String? orderId,
    DateTime? requestedAt,
    bool? alreadyOrdered,
  }) {
    return AdminDeviceWipeResult(
      orderId: orderId ?? this.orderId,
      requestedAt: requestedAt ?? this.requestedAt,
      alreadyOrdered: alreadyOrdered ?? this.alreadyOrdered,
    );
  }
}
