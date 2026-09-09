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
import 'package:sinalacs_client/src/protocol/protocol.dart' as _i2;

/// Dados clínicos do paciente.
///
/// O schema original usava herança por chave compartilhada: user_id era
/// simultaneamente PK e FK para users. O ORM do Serverpod exige PK de coluna
/// única chamada id e só sabe referenciar o id do pai, então o id desta tabela
/// É o UUID do usuário — não há coluna userId separada. Isso preserva a
/// semântica atual de patient_id e os UUIDs fixos do seed, dos quais o
/// dev-login depende. Consequência: o id é fornecido na inserção, não gerado.
abstract class Patient implements _i1.SerializableModel {
  Patient._({
    this.id,
    required this.emergencyContact,
    required this.isChronic,
    required this.chronicConditions,
    this.lastLocationHash,
    this.lastTriageAt,
  });

  factory Patient({
    _i1.UuidValue? id,
    required String emergencyContact,
    required bool isChronic,
    required List<String> chronicConditions,
    String? lastLocationHash,
    DateTime? lastTriageAt,
  }) = _PatientImpl;

  factory Patient.fromJson(Map<String, dynamic> jsonSerialization) {
    return Patient(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      emergencyContact: jsonSerialization['emergencyContact'] as String,
      isChronic: _i1.BoolJsonExtension.fromJson(jsonSerialization['isChronic']),
      chronicConditions: _i2.Protocol().deserialize<List<String>>(
        jsonSerialization['chronicConditions'],
      ),
      lastLocationHash: jsonSerialization['lastLocationHash'] as String?,
      lastTriageAt: jsonSerialization['lastTriageAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['lastTriageAt'],
            ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String emergencyContact;

  bool isChronic;

  List<String> chronicConditions;

  String? lastLocationHash;

  DateTime? lastTriageAt;

  /// Returns a shallow copy of this [Patient]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Patient copyWith({
    _i1.UuidValue? id,
    String? emergencyContact,
    bool? isChronic,
    List<String>? chronicConditions,
    String? lastLocationHash,
    DateTime? lastTriageAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Patient',
      if (id != null) 'id': id?.toJson(),
      'emergencyContact': emergencyContact,
      'isChronic': isChronic,
      'chronicConditions': chronicConditions.toJson(),
      if (lastLocationHash != null) 'lastLocationHash': lastLocationHash,
      if (lastTriageAt != null) 'lastTriageAt': lastTriageAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PatientImpl extends Patient {
  _PatientImpl({
    _i1.UuidValue? id,
    required String emergencyContact,
    required bool isChronic,
    required List<String> chronicConditions,
    String? lastLocationHash,
    DateTime? lastTriageAt,
  }) : super._(
         id: id,
         emergencyContact: emergencyContact,
         isChronic: isChronic,
         chronicConditions: chronicConditions,
         lastLocationHash: lastLocationHash,
         lastTriageAt: lastTriageAt,
       );

  /// Returns a shallow copy of this [Patient]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Patient copyWith({
    Object? id = _Undefined,
    String? emergencyContact,
    bool? isChronic,
    List<String>? chronicConditions,
    Object? lastLocationHash = _Undefined,
    Object? lastTriageAt = _Undefined,
  }) {
    return Patient(
      id: id is _i1.UuidValue? ? id : this.id,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      isChronic: isChronic ?? this.isChronic,
      chronicConditions:
          chronicConditions ?? this.chronicConditions.map((e0) => e0).toList(),
      lastLocationHash: lastLocationHash is String?
          ? lastLocationHash
          : this.lastLocationHash,
      lastTriageAt: lastTriageAt is DateTime?
          ? lastTriageAt
          : this.lastTriageAt,
    );
  }
}
