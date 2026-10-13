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

/// Motivo fechado de uma verificação da cadeia de `audit_logs` que não deu
/// `ok` (#45, D9). Substitui, para o cliente, o texto livre `reason` do
/// verificador: nunca vai hash, segredo nem conteúdo de linha.
/// `hashMismatch` = HMAC da linha não confere; `linkBroken` = `previousHash`
/// não aponta para a anterior; `sequenceGap` = `sequence` descontínua;
/// `tailTruncated` = cadeia termina antes do último checkpoint válido, ou o
/// `entryHash` naquela `sequence` diverge do checkpoint (Task 7);
/// `checkpointInvalid` = cadeia íntegra, mas há checkpoint com assinatura
/// inválida — ignorado e sinalizado, nunca aceito (Task 7; estado inconclusive);
/// `timeBudget` = orçamento de tempo esgotado antes do fim (resultado parcial,
/// nunca íntegro); `databaseError` = falha ao ler; `secretUnavailable` =
/// segredo da cadeia ausente.
enum AuditChainReason implements _i1.SerializableModel {
  hashMismatch,
  linkBroken,
  sequenceGap,
  tailTruncated,
  checkpointInvalid,
  timeBudget,
  databaseError,
  secretUnavailable;

  static AuditChainReason fromJson(String name) {
    switch (name) {
      case 'hashMismatch':
        return AuditChainReason.hashMismatch;
      case 'linkBroken':
        return AuditChainReason.linkBroken;
      case 'sequenceGap':
        return AuditChainReason.sequenceGap;
      case 'tailTruncated':
        return AuditChainReason.tailTruncated;
      case 'checkpointInvalid':
        return AuditChainReason.checkpointInvalid;
      case 'timeBudget':
        return AuditChainReason.timeBudget;
      case 'databaseError':
        return AuditChainReason.databaseError;
      case 'secretUnavailable':
        return AuditChainReason.secretUnavailable;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "AuditChainReason"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
