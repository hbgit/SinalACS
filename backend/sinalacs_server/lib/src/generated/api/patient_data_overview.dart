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
import '../api/patient_consent_record.dart' as _i2;
import '../api/patient_risk_event.dart' as _i3;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i4;

/// Painel "Meus Dados" do próprio paciente autenticado — confirmação de
/// existência de tratamento e acesso aos dados pessoais, critério de aceite
/// formal de spec/lgpd_design.md (linhas 417, 581-595). Minimização: nunca o
/// conteúdo bruto de uma triagem nem a localização de um alerta — só o que o
/// titular precisa para conferir/corrigir o que está cadastrado e ver o
/// próprio histórico de classificação de risco.
abstract class PatientDataOverview
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  PatientDataOverview._({
    required this.name,
    required this.birthDate,
    required this.emergencyContact,
    required this.isChronic,
    required this.chronicConditions,
    required this.consents,
    required this.riskHistory,
  });

  factory PatientDataOverview({
    required String name,
    required DateTime birthDate,
    required String emergencyContact,
    required bool isChronic,
    required List<String> chronicConditions,
    required List<_i2.PatientConsentRecord> consents,
    required List<_i3.PatientRiskEvent> riskHistory,
  }) = _PatientDataOverviewImpl;

  factory PatientDataOverview.fromJson(Map<String, dynamic> jsonSerialization) {
    return PatientDataOverview(
      name: jsonSerialization['name'] as String,
      birthDate: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['birthDate'],
      ),
      emergencyContact: jsonSerialization['emergencyContact'] as String,
      isChronic: _i1.BoolJsonExtension.fromJson(jsonSerialization['isChronic']),
      chronicConditions: _i4.Protocol().deserialize<List<String>>(
        jsonSerialization['chronicConditions'],
      ),
      consents: _i4.Protocol().deserialize<List<_i2.PatientConsentRecord>>(
        jsonSerialization['consents'],
      ),
      riskHistory: _i4.Protocol().deserialize<List<_i3.PatientRiskEvent>>(
        jsonSerialization['riskHistory'],
      ),
    );
  }

  String name;

  DateTime birthDate;

  String emergencyContact;

  bool isChronic;

  List<String> chronicConditions;

  List<_i2.PatientConsentRecord> consents;

  List<_i3.PatientRiskEvent> riskHistory;

  /// Returns a shallow copy of this [PatientDataOverview]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PatientDataOverview copyWith({
    String? name,
    DateTime? birthDate,
    String? emergencyContact,
    bool? isChronic,
    List<String>? chronicConditions,
    List<_i2.PatientConsentRecord>? consents,
    List<_i3.PatientRiskEvent>? riskHistory,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PatientDataOverview',
      'name': name,
      'birthDate': birthDate.toJson(),
      'emergencyContact': emergencyContact,
      'isChronic': isChronic,
      'chronicConditions': chronicConditions.toJson(),
      'consents': consents.toJson(valueToJson: (v) => v.toJson()),
      'riskHistory': riskHistory.toJson(valueToJson: (v) => v.toJson()),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PatientDataOverview',
      'name': name,
      'birthDate': birthDate.toJson(),
      'emergencyContact': emergencyContact,
      'isChronic': isChronic,
      'chronicConditions': chronicConditions.toJson(),
      'consents': consents.toJson(valueToJson: (v) => v.toJsonForProtocol()),
      'riskHistory': riskHistory.toJson(
        valueToJson: (v) => v.toJsonForProtocol(),
      ),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _PatientDataOverviewImpl extends PatientDataOverview {
  _PatientDataOverviewImpl({
    required String name,
    required DateTime birthDate,
    required String emergencyContact,
    required bool isChronic,
    required List<String> chronicConditions,
    required List<_i2.PatientConsentRecord> consents,
    required List<_i3.PatientRiskEvent> riskHistory,
  }) : super._(
         name: name,
         birthDate: birthDate,
         emergencyContact: emergencyContact,
         isChronic: isChronic,
         chronicConditions: chronicConditions,
         consents: consents,
         riskHistory: riskHistory,
       );

  /// Returns a shallow copy of this [PatientDataOverview]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PatientDataOverview copyWith({
    String? name,
    DateTime? birthDate,
    String? emergencyContact,
    bool? isChronic,
    List<String>? chronicConditions,
    List<_i2.PatientConsentRecord>? consents,
    List<_i3.PatientRiskEvent>? riskHistory,
  }) {
    return PatientDataOverview(
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      isChronic: isChronic ?? this.isChronic,
      chronicConditions:
          chronicConditions ?? this.chronicConditions.map((e0) => e0).toList(),
      consents: consents ?? this.consents.map((e0) => e0.copyWith()).toList(),
      riskHistory:
          riskHistory ?? this.riskHistory.map((e0) => e0.copyWith()).toList(),
    );
  }
}
