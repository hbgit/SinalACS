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
import 'enums/visit_authorship.dart' as _i2;
import 'enums/arrival_method.dart' as _i3;
import 'enums/sync_status.dart' as _i4;

/// Visita domiciliar. Registrada offline e sincronizada depois.
abstract class Visit implements _i1.SerializableModel {
  Visit._({
    this.id,
    required this.patientId,
    this.acsId,
    _i2.VisitAuthorship? authorship,
    this.originDeviceId,
    required this.scheduledAt,
    this.startedAt,
    this.completedAt,
    required this.status,
    String? riskLevelBeforeEncrypted,
    int? riskLevelBeforeKeyVersion,
    String? riskLevelAfterEncrypted,
    int? riskLevelAfterKeyVersion,
    String? notesEncrypted,
    int? notesKeyVersion,
    required this.syncStatus,
    _i3.ArrivalMethod? arrivalMethod,
    required this.localId,
    this.syncAt,
    required this.version,
  }) : authorship = authorship ?? _i2.VisitAuthorship.acs,
       riskLevelBeforeEncrypted = riskLevelBeforeEncrypted ?? '',
       riskLevelBeforeKeyVersion = riskLevelBeforeKeyVersion ?? 1,
       riskLevelAfterEncrypted = riskLevelAfterEncrypted ?? '',
       riskLevelAfterKeyVersion = riskLevelAfterKeyVersion ?? 1,
       notesEncrypted = notesEncrypted ?? '',
       notesKeyVersion = notesKeyVersion ?? 1,
       arrivalMethod = arrivalMethod ?? _i3.ArrivalMethod.manual;

  factory Visit({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    _i1.UuidValue? acsId,
    _i2.VisitAuthorship? authorship,
    String? originDeviceId,
    required DateTime scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    required String status,
    String? riskLevelBeforeEncrypted,
    int? riskLevelBeforeKeyVersion,
    String? riskLevelAfterEncrypted,
    int? riskLevelAfterKeyVersion,
    String? notesEncrypted,
    int? notesKeyVersion,
    required _i4.SyncStatus syncStatus,
    _i3.ArrivalMethod? arrivalMethod,
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
      acsId: jsonSerialization['acsId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      authorship: jsonSerialization['authorship'] == null
          ? null
          : _i2.VisitAuthorship.fromJson(
              (jsonSerialization['authorship'] as String),
            ),
      originDeviceId: jsonSerialization['originDeviceId'] as String?,
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
      riskLevelBeforeEncrypted:
          jsonSerialization['riskLevelBeforeEncrypted'] as String?,
      riskLevelBeforeKeyVersion:
          jsonSerialization['riskLevelBeforeKeyVersion'] as int?,
      riskLevelAfterEncrypted:
          jsonSerialization['riskLevelAfterEncrypted'] as String?,
      riskLevelAfterKeyVersion:
          jsonSerialization['riskLevelAfterKeyVersion'] as int?,
      notesEncrypted: jsonSerialization['notesEncrypted'] as String?,
      notesKeyVersion: jsonSerialization['notesKeyVersion'] as int?,
      syncStatus: _i4.SyncStatus.fromJson(
        (jsonSerialization['syncStatus'] as String),
      ),
      arrivalMethod: jsonSerialization['arrivalMethod'] == null
          ? null
          : _i3.ArrivalMethod.fromJson(
              (jsonSerialization['arrivalMethod'] as String),
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

  /// Autor da visita. Nulo SÓ quando `authorship == legacyUnclaimed`.
  _i1.UuidValue? acsId;

  /// `legacyUnclaimed` = visita gravada no aparelho antes de existir dono (migração v7):
  /// a autoria é desconhecida e `acsId` é nulo. NUNCA preencher `acsId` com quem transportou.
  _i2.VisitAuthorship authorship;

  /// Instalação do app de onde veio uma visita legada (`visits.syncLegacy`).
  /// Nulo nas visitas com autor ACS.
  String? originDeviceId;

  DateTime scheduledAt;

  DateTime? startedAt;

  DateTime? completedAt;

  String status;

  /// Risco antes e depois da visita, cifrados (INV-04, #75): nome do
  /// RiskLevel com largura fixa, ver `encrypted_risk_level.dart`. O "depois"
  /// ausente (visita não concluída) é cifrado também, com o mesmo tamanho.
  String riskLevelBeforeEncrypted;

  int riskLevelBeforeKeyVersion;

  String riskLevelAfterEncrypted;

  int riskLevelAfterKeyVersion;

  /// JSON de Map<String, String>, cifrado. Ver patient.spy.yaml para o padrão.
  String notesEncrypted;

  int notesKeyVersion;

  _i4.SyncStatus syncStatus;

  /// Como o check-in desta visita foi registrado (RF12, decisão §4). Default
  /// `manual` até a integração nativa de geofencing existir — hoje nenhum
  /// código produz `geofence`.
  _i3.ArrivalMethod arrivalMethod;

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
    _i2.VisitAuthorship? authorship,
    String? originDeviceId,
    DateTime? scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? status,
    String? riskLevelBeforeEncrypted,
    int? riskLevelBeforeKeyVersion,
    String? riskLevelAfterEncrypted,
    int? riskLevelAfterKeyVersion,
    String? notesEncrypted,
    int? notesKeyVersion,
    _i4.SyncStatus? syncStatus,
    _i3.ArrivalMethod? arrivalMethod,
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
      if (acsId != null) 'acsId': acsId?.toJson(),
      'authorship': authorship.toJson(),
      if (originDeviceId != null) 'originDeviceId': originDeviceId,
      'scheduledAt': scheduledAt.toJson(),
      if (startedAt != null) 'startedAt': startedAt?.toJson(),
      if (completedAt != null) 'completedAt': completedAt?.toJson(),
      'status': status,
      'riskLevelBeforeEncrypted': riskLevelBeforeEncrypted,
      'riskLevelBeforeKeyVersion': riskLevelBeforeKeyVersion,
      'riskLevelAfterEncrypted': riskLevelAfterEncrypted,
      'riskLevelAfterKeyVersion': riskLevelAfterKeyVersion,
      'notesEncrypted': notesEncrypted,
      'notesKeyVersion': notesKeyVersion,
      'syncStatus': syncStatus.toJson(),
      'arrivalMethod': arrivalMethod.toJson(),
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
    _i1.UuidValue? acsId,
    _i2.VisitAuthorship? authorship,
    String? originDeviceId,
    required DateTime scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    required String status,
    String? riskLevelBeforeEncrypted,
    int? riskLevelBeforeKeyVersion,
    String? riskLevelAfterEncrypted,
    int? riskLevelAfterKeyVersion,
    String? notesEncrypted,
    int? notesKeyVersion,
    required _i4.SyncStatus syncStatus,
    _i3.ArrivalMethod? arrivalMethod,
    required _i1.UuidValue localId,
    DateTime? syncAt,
    required int version,
  }) : super._(
         id: id,
         patientId: patientId,
         acsId: acsId,
         authorship: authorship,
         originDeviceId: originDeviceId,
         scheduledAt: scheduledAt,
         startedAt: startedAt,
         completedAt: completedAt,
         status: status,
         riskLevelBeforeEncrypted: riskLevelBeforeEncrypted,
         riskLevelBeforeKeyVersion: riskLevelBeforeKeyVersion,
         riskLevelAfterEncrypted: riskLevelAfterEncrypted,
         riskLevelAfterKeyVersion: riskLevelAfterKeyVersion,
         notesEncrypted: notesEncrypted,
         notesKeyVersion: notesKeyVersion,
         syncStatus: syncStatus,
         arrivalMethod: arrivalMethod,
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
    Object? acsId = _Undefined,
    _i2.VisitAuthorship? authorship,
    Object? originDeviceId = _Undefined,
    DateTime? scheduledAt,
    Object? startedAt = _Undefined,
    Object? completedAt = _Undefined,
    String? status,
    String? riskLevelBeforeEncrypted,
    int? riskLevelBeforeKeyVersion,
    String? riskLevelAfterEncrypted,
    int? riskLevelAfterKeyVersion,
    String? notesEncrypted,
    int? notesKeyVersion,
    _i4.SyncStatus? syncStatus,
    _i3.ArrivalMethod? arrivalMethod,
    _i1.UuidValue? localId,
    Object? syncAt = _Undefined,
    int? version,
  }) {
    return Visit(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      acsId: acsId is _i1.UuidValue? ? acsId : this.acsId,
      authorship: authorship ?? this.authorship,
      originDeviceId: originDeviceId is String?
          ? originDeviceId
          : this.originDeviceId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      startedAt: startedAt is DateTime? ? startedAt : this.startedAt,
      completedAt: completedAt is DateTime? ? completedAt : this.completedAt,
      status: status ?? this.status,
      riskLevelBeforeEncrypted:
          riskLevelBeforeEncrypted ?? this.riskLevelBeforeEncrypted,
      riskLevelBeforeKeyVersion:
          riskLevelBeforeKeyVersion ?? this.riskLevelBeforeKeyVersion,
      riskLevelAfterEncrypted:
          riskLevelAfterEncrypted ?? this.riskLevelAfterEncrypted,
      riskLevelAfterKeyVersion:
          riskLevelAfterKeyVersion ?? this.riskLevelAfterKeyVersion,
      notesEncrypted: notesEncrypted ?? this.notesEncrypted,
      notesKeyVersion: notesKeyVersion ?? this.notesKeyVersion,
      syncStatus: syncStatus ?? this.syncStatus,
      arrivalMethod: arrivalMethod ?? this.arrivalMethod,
      localId: localId ?? this.localId,
      syncAt: syncAt is DateTime? ? syncAt : this.syncAt,
      version: version ?? this.version,
    );
  }
}
