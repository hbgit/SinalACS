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

/// Ciclo de vida de um alerta. Um alerta vermelho nunca pode ser
/// descartado silenciosamente (INV-03 do PRD).
enum AlertStatus implements _i1.SerializableModel {
  pending,
  acknowledged,
  resolved,
  escalated;

  static AlertStatus fromJson(String name) {
    switch (name) {
      case 'pending':
        return AlertStatus.pending;
      case 'acknowledged':
        return AlertStatus.acknowledged;
      case 'resolved':
        return AlertStatus.resolved;
      case 'escalated':
        return AlertStatus.escalated;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "AlertStatus"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
