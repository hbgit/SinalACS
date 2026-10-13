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

/// Estado global da cadeia de `audit_logs` (#45, D3), calculado no servidor
/// por `admin.verifyAuditChain`. **Só `verified` é verde.** `broken` = a
/// verificação achou uma quebra (pode ser adulteração ou segredo trocado: o
/// painel diz "falha", nunca "adulteração" por conta própria);
/// `unavailable` = não deu para verificar (banco, tempo de leitura ou segredo
/// ausente); `inconclusive` = nada a atestar (cadeia vazia) ou verificação
/// parcial (orçamento de tempo esgotado).
enum AuditIntegrityState implements _i1.SerializableModel {
  verified,
  broken,
  unavailable,
  inconclusive;

  static AuditIntegrityState fromJson(String name) {
    switch (name) {
      case 'verified':
        return AuditIntegrityState.verified;
      case 'broken':
        return AuditIntegrityState.broken;
      case 'unavailable':
        return AuditIntegrityState.unavailable;
      case 'inconclusive':
        return AuditIntegrityState.inconclusive;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "AuditIntegrityState"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
