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

/// Motivo da limpeza remota de um aparelho (#81). Conjunto fechado, sem texto
/// livre: o motivo vai para a trilha de auditoria e texto livre ali seria um
/// canal para dado pessoal.
enum DeviceWipeReason implements _i1.SerializableModel {
  lost,
  stolen,
  replaced;

  static DeviceWipeReason fromJson(String name) {
    switch (name) {
      case 'lost':
        return DeviceWipeReason.lost;
      case 'stolen':
        return DeviceWipeReason.stolen;
      case 'replaced':
        return DeviceWipeReason.replaced;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "DeviceWipeReason"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
