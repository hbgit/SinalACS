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

/// Sessão de triagem estruturada. O risco é produzido pelo TriageEngine
/// de forma determinística e não é editável (INV-02).
abstract class TriageSession implements _i1.SerializableModel {
  TriageSession._({
    this.id,
    required this.patientId,
    String? answersEncrypted,
    int? answersKeyVersion,
    String? resultRiskEncrypted,
    int? resultRiskKeyVersion,
    required this.createdAt,
    required this.deviceId,
  }) : answersEncrypted = answersEncrypted ?? '',
       answersKeyVersion = answersKeyVersion ?? 1,
       resultRiskEncrypted = resultRiskEncrypted ?? '',
       resultRiskKeyVersion = resultRiskKeyVersion ?? 1;

  factory TriageSession({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    String? answersEncrypted,
    int? answersKeyVersion,
    String? resultRiskEncrypted,
    int? resultRiskKeyVersion,
    required DateTime createdAt,
    required String deviceId,
  }) = _TriageSessionImpl;

  factory TriageSession.fromJson(Map<String, dynamic> jsonSerialization) {
    return TriageSession(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      answersEncrypted: jsonSerialization['answersEncrypted'] as String?,
      answersKeyVersion: jsonSerialization['answersKeyVersion'] as int?,
      resultRiskEncrypted: jsonSerialization['resultRiskEncrypted'] as String?,
      resultRiskKeyVersion: jsonSerialization['resultRiskKeyVersion'] as int?,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      deviceId: jsonSerialization['deviceId'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue patientId;

  /// JSON de List<TriageAnswer>, cifrado. Ver patient.spy.yaml para o padrão.
  String answersEncrypted;

  int answersKeyVersion;

  /// Classificação do TriageEngine, cifrada (INV-04, #75): nome do RiskLevel
  /// com largura fixa, ver `encrypted_risk_level.dart`. O rótulo de tela
  /// (`resultDisplay`) deixou de ser persistido: era derivado do risco.
  String resultRiskEncrypted;

  int resultRiskKeyVersion;

  DateTime createdAt;

  String deviceId;

  /// Returns a shallow copy of this [TriageSession]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TriageSession copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    String? answersEncrypted,
    int? answersKeyVersion,
    String? resultRiskEncrypted,
    int? resultRiskKeyVersion,
    DateTime? createdAt,
    String? deviceId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TriageSession',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'answersEncrypted': answersEncrypted,
      'answersKeyVersion': answersKeyVersion,
      'resultRiskEncrypted': resultRiskEncrypted,
      'resultRiskKeyVersion': resultRiskKeyVersion,
      'createdAt': createdAt.toJson(),
      'deviceId': deviceId,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TriageSessionImpl extends TriageSession {
  _TriageSessionImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    String? answersEncrypted,
    int? answersKeyVersion,
    String? resultRiskEncrypted,
    int? resultRiskKeyVersion,
    required DateTime createdAt,
    required String deviceId,
  }) : super._(
         id: id,
         patientId: patientId,
         answersEncrypted: answersEncrypted,
         answersKeyVersion: answersKeyVersion,
         resultRiskEncrypted: resultRiskEncrypted,
         resultRiskKeyVersion: resultRiskKeyVersion,
         createdAt: createdAt,
         deviceId: deviceId,
       );

  /// Returns a shallow copy of this [TriageSession]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TriageSession copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    String? answersEncrypted,
    int? answersKeyVersion,
    String? resultRiskEncrypted,
    int? resultRiskKeyVersion,
    DateTime? createdAt,
    String? deviceId,
  }) {
    return TriageSession(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      answersEncrypted: answersEncrypted ?? this.answersEncrypted,
      answersKeyVersion: answersKeyVersion ?? this.answersKeyVersion,
      resultRiskEncrypted: resultRiskEncrypted ?? this.resultRiskEncrypted,
      resultRiskKeyVersion: resultRiskKeyVersion ?? this.resultRiskKeyVersion,
      createdAt: createdAt ?? this.createdAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
