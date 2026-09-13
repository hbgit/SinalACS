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
import 'package:sinalacs_server/src/generated/protocol.dart' as _i2;

/// Um paciente da microárea do ACS, para escolher em quem registrar uma visita
/// de rotina.
///
/// Minimização (LGPD §5.6, spec/lgpd_design.md:364): só o que uma visita de
/// rotina precisa para escolher o paciente certo — nome e condições crônicas.
/// `emergencyContact` fica de fora de propósito: não ajuda a escolher quem
/// visitar. Não existe campo de endereço porque `Patient` não tem essa coluna.
abstract class MicroAreaPatient
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  MicroAreaPatient._({
    required this.patientId,
    required this.name,
    required this.isChronic,
    required this.chronicConditions,
  });

  factory MicroAreaPatient({
    required String patientId,
    required String name,
    required bool isChronic,
    required List<String> chronicConditions,
  }) = _MicroAreaPatientImpl;

  factory MicroAreaPatient.fromJson(Map<String, dynamic> jsonSerialization) {
    return MicroAreaPatient(
      patientId: jsonSerialization['patientId'] as String,
      name: jsonSerialization['name'] as String,
      isChronic: _i1.BoolJsonExtension.fromJson(jsonSerialization['isChronic']),
      chronicConditions: _i2.Protocol().deserialize<List<String>>(
        jsonSerialization['chronicConditions'],
      ),
    );
  }

  String patientId;

  String name;

  bool isChronic;

  List<String> chronicConditions;

  /// Returns a shallow copy of this [MicroAreaPatient]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  MicroAreaPatient copyWith({
    String? patientId,
    String? name,
    bool? isChronic,
    List<String>? chronicConditions,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MicroAreaPatient',
      'patientId': patientId,
      'name': name,
      'isChronic': isChronic,
      'chronicConditions': chronicConditions.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MicroAreaPatient',
      'patientId': patientId,
      'name': name,
      'isChronic': isChronic,
      'chronicConditions': chronicConditions.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _MicroAreaPatientImpl extends MicroAreaPatient {
  _MicroAreaPatientImpl({
    required String patientId,
    required String name,
    required bool isChronic,
    required List<String> chronicConditions,
  }) : super._(
         patientId: patientId,
         name: name,
         isChronic: isChronic,
         chronicConditions: chronicConditions,
       );

  /// Returns a shallow copy of this [MicroAreaPatient]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  MicroAreaPatient copyWith({
    String? patientId,
    String? name,
    bool? isChronic,
    List<String>? chronicConditions,
  }) {
    return MicroAreaPatient(
      patientId: patientId ?? this.patientId,
      name: name ?? this.name,
      isChronic: isChronic ?? this.isChronic,
      chronicConditions:
          chronicConditions ?? this.chronicConditions.map((e0) => e0).toList(),
    );
  }
}
