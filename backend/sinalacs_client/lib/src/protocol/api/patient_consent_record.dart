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

/// Um registro de consentimento do próprio titular, para o painel "Meus
/// Dados" (LGPD, spec/lgpd_design.md linhas 417/581-595). Espelha `ConsentLog`
/// sem os campos técnicos de auditoria (`ipHash`, `userAgent`, `signature`)
/// — esses provam integridade da trilha, não servem ao titular lendo o
/// próprio histórico.
abstract class PatientConsentRecord implements _i1.SerializableModel {
  PatientConsentRecord._({
    required this.purpose,
    required this.action,
    required this.version,
    required this.timestamp,
  });

  factory PatientConsentRecord({
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
  }) = _PatientConsentRecordImpl;

  factory PatientConsentRecord.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return PatientConsentRecord(
      purpose: jsonSerialization['purpose'] as String,
      action: jsonSerialization['action'] as String,
      version: jsonSerialization['version'] as String,
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
    );
  }

  String purpose;

  String action;

  String version;

  DateTime timestamp;

  /// Returns a shallow copy of this [PatientConsentRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PatientConsentRecord copyWith({
    String? purpose,
    String? action,
    String? version,
    DateTime? timestamp,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PatientConsentRecord',
      'purpose': purpose,
      'action': action,
      'version': version,
      'timestamp': timestamp.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _PatientConsentRecordImpl extends PatientConsentRecord {
  _PatientConsentRecordImpl({
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
  }) : super._(
         purpose: purpose,
         action: action,
         version: version,
         timestamp: timestamp,
       );

  /// Returns a shallow copy of this [PatientConsentRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PatientConsentRecord copyWith({
    String? purpose,
    String? action,
    String? version,
    DateTime? timestamp,
  }) {
    return PatientConsentRecord(
      purpose: purpose ?? this.purpose,
      action: action ?? this.action,
      version: version ?? this.version,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
