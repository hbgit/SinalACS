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
import '../enums/risk_level.dart' as _i2;

/// Um evento de classificação de risco do próprio titular, para o histórico
/// do painel "Meus Dados" (LGPD). Vem de `triage_sessions.resultRisk` ou de
/// `alerts.riskLevel` — as duas tabelas não se unificam num tipo comum, e
/// `source` é o que diferencia. Nunca o conteúdo bruto de uma triagem
/// (`answersEncrypted`) nem a localização de um alerta: só a classificação e
/// quando ela aconteceu.
abstract class PatientRiskEvent
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  PatientRiskEvent._({
    required this.source,
    required this.riskLevel,
    required this.recordedAt,
  });

  factory PatientRiskEvent({
    required String source,
    required _i2.RiskLevel riskLevel,
    required DateTime recordedAt,
  }) = _PatientRiskEventImpl;

  factory PatientRiskEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return PatientRiskEvent(
      source: jsonSerialization['source'] as String,
      riskLevel: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevel'] as String),
      ),
      recordedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['recordedAt'],
      ),
    );
  }

  /// 'triage' ou 'alert'.
  String source;

  _i2.RiskLevel riskLevel;

  DateTime recordedAt;

  /// Returns a shallow copy of this [PatientRiskEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PatientRiskEvent copyWith({
    String? source,
    _i2.RiskLevel? riskLevel,
    DateTime? recordedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PatientRiskEvent',
      'source': source,
      'riskLevel': riskLevel.toJson(),
      'recordedAt': recordedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PatientRiskEvent',
      'source': source,
      'riskLevel': riskLevel.toJson(),
      'recordedAt': recordedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _PatientRiskEventImpl extends PatientRiskEvent {
  _PatientRiskEventImpl({
    required String source,
    required _i2.RiskLevel riskLevel,
    required DateTime recordedAt,
  }) : super._(
         source: source,
         riskLevel: riskLevel,
         recordedAt: recordedAt,
       );

  /// Returns a shallow copy of this [PatientRiskEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PatientRiskEvent copyWith({
    String? source,
    _i2.RiskLevel? riskLevel,
    DateTime? recordedAt,
  }) {
    return PatientRiskEvent(
      source: source ?? this.source,
      riskLevel: riskLevel ?? this.riskLevel,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }
}
