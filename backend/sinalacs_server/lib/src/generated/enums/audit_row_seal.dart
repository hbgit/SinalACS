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

/// Selo de integridade de UMA linha de `audit_logs` (#45, D3), calculado no
/// servidor com a mesma `AuditChain` que grava a trilha. Só `verified` é verde:
/// `invalid` = o HMAC da linha ou o elo com a `sequence - 1` não confere;
/// `unverifiable` = a linha `sequence - 1` não existe no banco (o elo não pôde
/// ser conferido). Nunca carrega hash nem segredo.
enum AuditRowSeal implements _i1.SerializableModel {
  verified,
  invalid,
  unverifiable;

  static AuditRowSeal fromJson(String name) {
    switch (name) {
      case 'verified':
        return AuditRowSeal.verified;
      case 'invalid':
        return AuditRowSeal.invalid;
      case 'unverifiable':
        return AuditRowSeal.unverifiable;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "AuditRowSeal"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
