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

/// Indicadores do painel do backoffice (issue #40). Contagens por risco e o
/// TMRAV, no escopo do chamador (sistema inteiro para o administrador, a UBS
/// para o coordenador). `tmravSeconds` é nulo quando não há alerta vermelho
/// reconhecido na janela: sem amostra não há média, e zero seria mentira.
abstract class AdminIndicators implements _i1.SerializableModel {
  AdminIndicators._({
    required this.red,
    required this.yellow,
    required this.green,
    required this.openRedAlerts,
    required this.acknowledgedRedAlerts,
    this.tmravSeconds,
  });

  factory AdminIndicators({
    required int red,
    required int yellow,
    required int green,
    required int openRedAlerts,
    required int acknowledgedRedAlerts,
    int? tmravSeconds,
  }) = _AdminIndicatorsImpl;

  factory AdminIndicators.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminIndicators(
      red: jsonSerialization['red'] as int,
      yellow: jsonSerialization['yellow'] as int,
      green: jsonSerialization['green'] as int,
      openRedAlerts: jsonSerialization['openRedAlerts'] as int,
      acknowledgedRedAlerts: jsonSerialization['acknowledgedRedAlerts'] as int,
      tmravSeconds: jsonSerialization['tmravSeconds'] as int?,
    );
  }

  int red;

  int yellow;

  int green;

  int openRedAlerts;

  int acknowledgedRedAlerts;

  int? tmravSeconds;

  /// Returns a shallow copy of this [AdminIndicators]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminIndicators copyWith({
    int? red,
    int? yellow,
    int? green,
    int? openRedAlerts,
    int? acknowledgedRedAlerts,
    int? tmravSeconds,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminIndicators',
      'red': red,
      'yellow': yellow,
      'green': green,
      'openRedAlerts': openRedAlerts,
      'acknowledgedRedAlerts': acknowledgedRedAlerts,
      if (tmravSeconds != null) 'tmravSeconds': tmravSeconds,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminIndicatorsImpl extends AdminIndicators {
  _AdminIndicatorsImpl({
    required int red,
    required int yellow,
    required int green,
    required int openRedAlerts,
    required int acknowledgedRedAlerts,
    int? tmravSeconds,
  }) : super._(
         red: red,
         yellow: yellow,
         green: green,
         openRedAlerts: openRedAlerts,
         acknowledgedRedAlerts: acknowledgedRedAlerts,
         tmravSeconds: tmravSeconds,
       );

  /// Returns a shallow copy of this [AdminIndicators]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminIndicators copyWith({
    int? red,
    int? yellow,
    int? green,
    int? openRedAlerts,
    int? acknowledgedRedAlerts,
    Object? tmravSeconds = _Undefined,
  }) {
    return AdminIndicators(
      red: red ?? this.red,
      yellow: yellow ?? this.yellow,
      green: green ?? this.green,
      openRedAlerts: openRedAlerts ?? this.openRedAlerts,
      acknowledgedRedAlerts:
          acknowledgedRedAlerts ?? this.acknowledgedRedAlerts,
      tmravSeconds: tmravSeconds is int? ? tmravSeconds : this.tmravSeconds,
    );
  }
}
