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

/// Por que um certificado de aparelho foi revogado (#94). Conjunto fechado: o
/// motivo vai para a trilha de auditoria.
enum DeviceCertRevocationReason implements _i1.SerializableModel {
  /// Limpeza remota do aparelho (#81).
  wipe,

  /// Conta do ACS desativada pela coordenação.
  deactivated,

  /// O ACS mudou de microárea: o CN da folha é a microárea antiga.
  microAreaChanged,

  /// Substituído por uma emissão nova no mesmo aparelho.
  renewed;

  static DeviceCertRevocationReason fromJson(String name) {
    switch (name) {
      case 'wipe':
        return DeviceCertRevocationReason.wipe;
      case 'deactivated':
        return DeviceCertRevocationReason.deactivated;
      case 'microAreaChanged':
        return DeviceCertRevocationReason.microAreaChanged;
      case 'renewed':
        return DeviceCertRevocationReason.renewed;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "DeviceCertRevocationReason"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
