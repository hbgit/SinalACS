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

/// Motivo do escalonamento de um alerta (#44). Conjunto fechado, sem texto
/// livre: texto livre num alerta de saúde é dado pessoal sensível (LGPD).
enum EscalationReason implements _i1.SerializableModel {
  noAckTimeout,
  acsUnreachable,
  patientRecontact;

  static EscalationReason fromJson(String name) {
    switch (name) {
      case 'noAckTimeout':
        return EscalationReason.noAckTimeout;
      case 'acsUnreachable':
        return EscalationReason.acsUnreachable;
      case 'patientRecontact':
        return EscalationReason.patientRecontact;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "EscalationReason"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
