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

/// Quem é o autor de uma visita (D4 do plano 2026-10-03).
///
/// `acs`: o ACS da sessão que a enviou por `visits.sync` — `visits.acsId` é
/// ele. `legacyUnclaimed`: visita gravada no aparelho antes de existir dono por
/// visita (migração v7 do banco local do app); a autoria é DESCONHECIDA e
/// `visits.acsId` fica nulo. Só `visits.syncLegacy` grava este valor.
enum VisitAuthorship implements _i1.SerializableModel {
  acs,
  legacyUnclaimed;

  static VisitAuthorship fromJson(String name) {
    switch (name) {
      case 'acs':
        return VisitAuthorship.acs;
      case 'legacyUnclaimed':
        return VisitAuthorship.legacyUnclaimed;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "VisitAuthorship"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
