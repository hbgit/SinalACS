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
import 'enums/risk_level.dart' as _i2;
import 'enums/sync_status.dart' as _i3;
import 'package:sinalacs_client/src/protocol/protocol.dart' as _i4;

/// Visita domiciliar. Registrada offline e sincronizada depois.
abstract class Visit implements _i1.SerializableModel {
  Visit._({
    this.id,
    required this.patientId,
    required this.acsId,
    required this.scheduledAt,
    this.startedAt,
    this.completedAt,
    required this.status,
    required this.riskLevelBefore,
    this.riskLevelAfter,
    required this.notes,
    required this.syncStatus,
    required this.localId,
    this.syncAt,
    required this.version,
  });

  factory Visit({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required _i1.UuidValue acsId,
    required DateTime scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    required String status,
    required _i2.RiskLevel riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    required Map<String, String> notes,
    required _i3.SyncStatus syncStatus,
    required _i1.UuidValue localId,
    DateTime? syncAt,
    required int version,
  }) = _VisitImpl;

  factory Visit.fromJson(Map<String, dynamic> jsonSerialization) {
    return Visit(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      acsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      scheduledAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['scheduledAt'],
      ),
      startedAt: jsonSerialization['startedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['startedAt']),
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
      notes: _i4.Protocol().deserialize<Map<String, String>>(
        jsonSerialization['notes'],
      ),
      syncStatus: _i3.SyncStatus.fromJson(
        (jsonSerialization['syncStatus'] as String),
      ),
      localId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['localId'],
      ),
      syncAt: jsonSerialization['syncAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['syncAt']),
      version: jsonSerialization['version'] as int,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue patientId;

  _i1.UuidValue acsId;

  DateTime scheduledAt;

  DateTime? startedAt;

  DateTime? completedAt;

  String status;

  _i2.RiskLevel riskLevelBefore;

  _i2.RiskLevel? riskLevelAfter;

  Map<String, String> notes;

  _i3.SyncStatus syncStatus;

  /// Identificador gerado no dispositivo, usado para deduplicar na sincronização.
  _i1.UuidValue localId;

  DateTime? syncAt;

  int version;

  /// Returns a shallow copy of this [Visit]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Visit copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    _i1.UuidValue? acsId,
    DateTime? scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? status,
    _i2.RiskLevel? riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    Map<String, String>? notes,
    _i3.SyncStatus? syncStatus,
    _i1.UuidValue? localId,
    DateTime? syncAt,
    int? version,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Visit',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'acsId': acsId.toJson(),
      'scheduledAt': scheduledAt.toJson(),
      if (startedAt != null) 'startedAt': startedAt?.toJson(),
      if (completedAt != null) 'completedAt': completedAt?.toJson(),
      'status': status,
      'riskLevelBefore': riskLevelBefore.toJson(),
      if (riskLevelAfter != null) 'riskLevelAfter': riskLevelAfter?.toJson(),
      'notes': notes.toJson(),
      'syncStatus': syncStatus.toJson(),
      'localId': localId.toJson(),
      if (syncAt != null) 'syncAt': syncAt?.toJson(),
      'version': version,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _VisitImpl extends Visit {
  _VisitImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required _i1.UuidValue acsId,
    required DateTime scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    required String status,
    required _i2.RiskLevel riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    required Map<String, String> notes,
    required _i3.SyncStatus syncStatus,
    required _i1.UuidValue localId,
    DateTime? syncAt,
    required int version,
  }) : super._(
         id: id,
         patientId: patientId,
         acsId: acsId,
         scheduledAt: scheduledAt,
         startedAt: startedAt,
         completedAt: completedAt,
         status: status,
         riskLevelBefore: riskLevelBefore,
         riskLevelAfter: riskLevelAfter,
         notes: notes,
         syncStatus: syncStatus,
         localId: localId,
         syncAt: syncAt,
         version: version,
       );

  /// Returns a shallow copy of this [Visit]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Visit copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    _i1.UuidValue? acsId,
    DateTime? scheduledAt,
    Object? startedAt = _Undefined,
    Object? completedAt = _Undefined,
    String? status,
    _i2.RiskLevel? riskLevelBefore,
    Object? riskLevelAfter = _Undefined,
    Map<String, String>? notes,
    _i3.SyncStatus? syncStatus,
    _i1.UuidValue? localId,
    Object? syncAt = _Undefined,
    int? version,
  }) {
    return Visit(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      acsId: acsId ?? this.acsId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      startedAt: startedAt is DateTime? ? startedAt : this.startedAt,
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
      syncStatus: syncStatus ?? this.syncStatus,
      localId: localId ?? this.localId,
      syncAt: syncAt is DateTime? ? syncAt : this.syncAt,
      version: version ?? this.version,
    );
  }
}
