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
import 'package:sinalacs_client/src/protocol/protocol.dart' as _i3;

/// Uma visita registrada offline, enviada pelo app do ACS para sincronização.
///
/// `localId` é gerado no dispositivo e tem índice único em `visits`: é o que
/// permite reenviar o mesmo lote depois de uma falha de rede sem duplicar a
/// visita. `version` é a versão que o dispositivo conhece — divergir da versão
/// do servidor significa que alguém alterou a visita no meio, e o resultado é
/// conflito, não sobrescrita.
abstract class VisitSyncEntry implements _i1.SerializableModel {
  VisitSyncEntry._({
    required this.localId,
    required this.patientId,
    required this.scheduledAt,
    this.completedAt,
    required this.status,
    required this.riskLevelBefore,
    this.riskLevelAfter,
    required this.notes,
    required this.version,
  });

  factory VisitSyncEntry({
    required String localId,
    required String patientId,
    required DateTime scheduledAt,
    DateTime? completedAt,
    required String status,
    required _i2.RiskLevel riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    required Map<String, String> notes,
    required int version,
  }) = _VisitSyncEntryImpl;

  factory VisitSyncEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return VisitSyncEntry(
      localId: jsonSerialization['localId'] as String,
      patientId: jsonSerialization['patientId'] as String,
      scheduledAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['scheduledAt'],
      ),
      completedAt: jsonSerialization['completedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['completedAt'],
            ),
      status: jsonSerialization['status'] as String,
      riskLevelBefore: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevelBefore'] as String),
      ),
      riskLevelAfter: jsonSerialization['riskLevelAfter'] == null
          ? null
          : _i2.RiskLevel.fromJson(
              (jsonSerialization['riskLevelAfter'] as String),
            ),
      notes: _i3.Protocol().deserialize<Map<String, String>>(
        jsonSerialization['notes'],
      ),
      version: jsonSerialization['version'] as int,
    );
  }

  String localId;

  String patientId;

  DateTime scheduledAt;

  DateTime? completedAt;

  String status;

  _i2.RiskLevel riskLevelBefore;

  _i2.RiskLevel? riskLevelAfter;

  Map<String, String> notes;

  int version;

  /// Returns a shallow copy of this [VisitSyncEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  VisitSyncEntry copyWith({
    String? localId,
    String? patientId,
    DateTime? scheduledAt,
    DateTime? completedAt,
    String? status,
    _i2.RiskLevel? riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    Map<String, String>? notes,
    int? version,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'VisitSyncEntry',
      'localId': localId,
      'patientId': patientId,
      'scheduledAt': scheduledAt.toJson(),
      if (completedAt != null) 'completedAt': completedAt?.toJson(),
      'status': status,
      'riskLevelBefore': riskLevelBefore.toJson(),
      if (riskLevelAfter != null) 'riskLevelAfter': riskLevelAfter?.toJson(),
      'notes': notes.toJson(),
      'version': version,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _VisitSyncEntryImpl extends VisitSyncEntry {
  _VisitSyncEntryImpl({
    required String localId,
    required String patientId,
    required DateTime scheduledAt,
    DateTime? completedAt,
    required String status,
    required _i2.RiskLevel riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    required Map<String, String> notes,
    required int version,
  }) : super._(
         localId: localId,
         patientId: patientId,
         scheduledAt: scheduledAt,
         completedAt: completedAt,
         status: status,
         riskLevelBefore: riskLevelBefore,
         riskLevelAfter: riskLevelAfter,
         notes: notes,
         version: version,
       );

  /// Returns a shallow copy of this [VisitSyncEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  VisitSyncEntry copyWith({
    String? localId,
    String? patientId,
    DateTime? scheduledAt,
    Object? completedAt = _Undefined,
    String? status,
    _i2.RiskLevel? riskLevelBefore,
    Object? riskLevelAfter = _Undefined,
    Map<String, String>? notes,
    int? version,
  }) {
    return VisitSyncEntry(
      localId: localId ?? this.localId,
      patientId: patientId ?? this.patientId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      completedAt: completedAt is DateTime? ? completedAt : this.completedAt,
      status: status ?? this.status,
      riskLevelBefore: riskLevelBefore ?? this.riskLevelBefore,
      riskLevelAfter: riskLevelAfter is _i2.RiskLevel?
          ? riskLevelAfter
          : this.riskLevelAfter,
      notes:
          notes ??
          this.notes.map(
            (
              key0,
              value0,
            ) => MapEntry(
              key0,
              value0,
            ),
          ),
      version: version ?? this.version,
    );
  }
}
