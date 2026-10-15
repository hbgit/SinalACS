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

/// Situação de um pedido do titular. `open` é escrito pelo titular; `inReview`,
/// `completed` e `rejected` pelo backoffice (coordenador/admin, #42).
/// `completed` e `rejected` são finais.
enum DataSubjectRequestStatus implements _i1.SerializableModel {
  open,
  inReview,
  completed,
  rejected;

  static DataSubjectRequestStatus fromJson(String name) {
    switch (name) {
      case 'open':
        return DataSubjectRequestStatus.open;
      case 'inReview':
        return DataSubjectRequestStatus.inReview;
      case 'completed':
        return DataSubjectRequestStatus.completed;
      case 'rejected':
        return DataSubjectRequestStatus.rejected;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "DataSubjectRequestStatus"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
