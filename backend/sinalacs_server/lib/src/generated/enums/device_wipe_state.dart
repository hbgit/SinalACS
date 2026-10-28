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

/// Estado do pedido de limpeza de um aparelho (#81), derivado dos carimbos do
/// pedido: `pending` (pedido, aparelho ainda não mandado limpar), `delivered`
/// (ordem entregue ao aparelho) e `confirmed` (aparelho confirmou a limpeza).
enum DeviceWipeState implements _i1.SerializableModel {
  pending,
  delivered,
  confirmed;

  static DeviceWipeState fromJson(String name) {
    switch (name) {
      case 'pending':
        return DeviceWipeState.pending;
      case 'delivered':
        return DeviceWipeState.delivered;
      case 'confirmed':
        return DeviceWipeState.confirmed;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "DeviceWipeState"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
