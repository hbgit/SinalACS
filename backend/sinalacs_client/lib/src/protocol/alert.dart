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
import 'enums/alert_status.dart' as _i3;

/// Alerta de urgência disparado pelo paciente.
///
/// Campos microAreaId, acknowledgedAt e version vêm da migração v1.2.0 e
/// estavam ausentes da AlertEntity antiga — o modelo segue o SQL, não a
/// entidade Dart que havia divergido.
abstract class Alert implements _i1.SerializableModel {
  Alert._({
    this.id,
    required this.patientId,
    this.acsId,
    this.microAreaId,
    required this.triggeredAt,
    this.receivedAt,
    this.respondedAt,
    this.acknowledgedAt,
    required this.riskLevel,
    required this.locationHash,
    required this.status,
    required this.mqttTopic,
    required this.deviceId,
    required this.retryCount,
    required this.version,
  });

  factory Alert({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    _i1.UuidValue? acsId,
    _i1.UuidValue? microAreaId,
    required DateTime triggeredAt,
    DateTime? receivedAt,
    DateTime? respondedAt,
    DateTime? acknowledgedAt,
    required _i2.RiskLevel riskLevel,
    required String locationHash,
    required _i3.AlertStatus status,
    required String mqttTopic,
    required String deviceId,
    required int retryCount,
    required int version,
  }) = _AlertImpl;

  factory Alert.fromJson(Map<String, dynamic> jsonSerialization) {
    return Alert(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      acsId: jsonSerialization['acsId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      microAreaId: jsonSerialization['microAreaId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['microAreaId'],
            ),
      triggeredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['triggeredAt'],
      ),
      receivedAt: jsonSerialization['receivedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['receivedAt']),
      respondedAt: jsonSerialization['respondedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['respondedAt'],
            ),
      acknowledgedAt: jsonSerialization['acknowledgedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['acknowledgedAt'],
            ),
      riskLevel: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevel'] as String),
      ),
      locationHash: jsonSerialization['locationHash'] as String,
      status: _i3.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      mqttTopic: jsonSerialization['mqttTopic'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      retryCount: jsonSerialization['retryCount'] as int,
      version: jsonSerialization['version'] as int,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue patientId;

  _i1.UuidValue? acsId;

  _i1.UuidValue? microAreaId;

  DateTime triggeredAt;

  DateTime? receivedAt;

  DateTime? respondedAt;

  DateTime? acknowledgedAt;

  _i2.RiskLevel riskLevel;

  String locationHash;

  _i3.AlertStatus status;

  String mqttTopic;

  String deviceId;

  int retryCount;

  int version;

  /// Returns a shallow copy of this [Alert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Alert copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    _i1.UuidValue? acsId,
    _i1.UuidValue? microAreaId,
    DateTime? triggeredAt,
    DateTime? receivedAt,
    DateTime? respondedAt,
    DateTime? acknowledgedAt,
    _i2.RiskLevel? riskLevel,
    String? locationHash,
    _i3.AlertStatus? status,
    String? mqttTopic,
    String? deviceId,
    int? retryCount,
    int? version,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Alert',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      if (acsId != null) 'acsId': acsId?.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'triggeredAt': triggeredAt.toJson(),
      if (receivedAt != null) 'receivedAt': receivedAt?.toJson(),
      if (respondedAt != null) 'respondedAt': respondedAt?.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
      'riskLevel': riskLevel.toJson(),
      'locationHash': locationHash,
      'status': status.toJson(),
      'mqttTopic': mqttTopic,
      'deviceId': deviceId,
      'retryCount': retryCount,
      'version': version,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertImpl extends Alert {
  _AlertImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    _i1.UuidValue? acsId,
    _i1.UuidValue? microAreaId,
    required DateTime triggeredAt,
    DateTime? receivedAt,
    DateTime? respondedAt,
    DateTime? acknowledgedAt,
    required _i2.RiskLevel riskLevel,
    required String locationHash,
    required _i3.AlertStatus status,
    required String mqttTopic,
    required String deviceId,
    required int retryCount,
    required int version,
  }) : super._(
         id: id,
         patientId: patientId,
         acsId: acsId,
         microAreaId: microAreaId,
         triggeredAt: triggeredAt,
         receivedAt: receivedAt,
         respondedAt: respondedAt,
         acknowledgedAt: acknowledgedAt,
         riskLevel: riskLevel,
         locationHash: locationHash,
         status: status,
         mqttTopic: mqttTopic,
         deviceId: deviceId,
         retryCount: retryCount,
         version: version,
       );

  /// Returns a shallow copy of this [Alert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Alert copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    Object? acsId = _Undefined,
    Object? microAreaId = _Undefined,
    DateTime? triggeredAt,
    Object? receivedAt = _Undefined,
    Object? respondedAt = _Undefined,
    Object? acknowledgedAt = _Undefined,
    _i2.RiskLevel? riskLevel,
    String? locationHash,
    _i3.AlertStatus? status,
    String? mqttTopic,
    String? deviceId,
    int? retryCount,
    int? version,
  }) {
    return Alert(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      acsId: acsId is _i1.UuidValue? ? acsId : this.acsId,
      microAreaId: microAreaId is _i1.UuidValue?
          ? microAreaId
          : this.microAreaId,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      receivedAt: receivedAt is DateTime? ? receivedAt : this.receivedAt,
      respondedAt: respondedAt is DateTime? ? respondedAt : this.respondedAt,
      acknowledgedAt: acknowledgedAt is DateTime?
          ? acknowledgedAt
          : this.acknowledgedAt,
      riskLevel: riskLevel ?? this.riskLevel,
      locationHash: locationHash ?? this.locationHash,
      status: status ?? this.status,
      mqttTopic: mqttTopic ?? this.mqttTopic,
      deviceId: deviceId ?? this.deviceId,
      retryCount: retryCount ?? this.retryCount,
      version: version ?? this.version,
    );
  }
}
