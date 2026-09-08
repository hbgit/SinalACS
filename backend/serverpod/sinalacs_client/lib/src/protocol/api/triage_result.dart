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
import '../enums/risk_level.dart' as _i2;

/// Classificação determinística produzida pelo TriageEngine.
/// Nunca é editável pela pessoa usuária nem pelo ACS (INV-02).
abstract class TriageResult implements _i1.SerializableModel {
  TriageResult._({required this.risk});

  factory TriageResult({required _i2.RiskLevel risk}) = _TriageResultImpl;

  factory TriageResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return TriageResult(
      risk: _i2.RiskLevel.fromJson((jsonSerialization['risk'] as String)),
    );
  }

  _i2.RiskLevel risk;

  /// Returns a shallow copy of this [TriageResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TriageResult copyWith({_i2.RiskLevel? risk});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TriageResult',
      'risk': risk.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TriageResultImpl extends TriageResult {
  _TriageResultImpl({required _i2.RiskLevel risk}) : super._(risk: risk);

  /// Returns a shallow copy of this [TriageResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TriageResult copyWith({_i2.RiskLevel? risk}) {
    return TriageResult(risk: risk ?? this.risk);
  }
}
