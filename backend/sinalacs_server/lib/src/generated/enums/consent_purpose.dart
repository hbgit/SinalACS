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

/// As finalidades de consentimento do onboarding (decisão §2.2 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md).
/// `healthDataProcessing` e `termsOfUse` são obrigatórias para usar o app;
/// as outras duas podem ser recusadas sem impedir o restante do fluxo.
/// `termsOfUse` registra o aceite do Termo de Uso e da Política de
/// Privacidade na versão `consentPolicyVersion` (LGPD-RF18/RF19) — não é
/// consentimento revogável pelo painel, é a condição de uso do app.
enum ConsentPurpose implements _i1.SerializableModel {
  healthDataProcessing,
  localReminders,
  segmentedPush,
  termsOfUse;

  static ConsentPurpose fromJson(String name) {
    switch (name) {
      case 'healthDataProcessing':
        return ConsentPurpose.healthDataProcessing;
      case 'localReminders':
        return ConsentPurpose.localReminders;
      case 'segmentedPush':
        return ConsentPurpose.segmentedPush;
      case 'termsOfUse':
        return ConsentPurpose.termsOfUse;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "ConsentPurpose"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
