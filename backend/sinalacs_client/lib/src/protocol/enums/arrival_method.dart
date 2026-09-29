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

/// Como o check-in da visita foi registrado. `geofence` é reservado para
/// quando a integração nativa de geofencing existir (RF12, decisão §4) —
/// nenhum código hoje produz esse valor; `manual` é o único caminho real.
///
/// Escopo desta task: só o contrato de dados. Nenhuma API nativa de geofence
/// foi integrada, nenhuma permissão de localização em primeiro/segundo plano
/// foi adicionada a nenhum app, e a escolha de plugin/texto de divulgação
/// seguem bloqueados por revisão de produto/jurídico.
enum ArrivalMethod implements _i1.SerializableModel {
  manual,
  geofence;

  static ArrivalMethod fromJson(String name) {
    switch (name) {
      case 'manual':
        return ArrivalMethod.manual;
      case 'geofence':
        return ArrivalMethod.geofence;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "ArrivalMethod"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
