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

/// Confirmação de recebimento de um alerta por um ACS.
///
/// O schema original usava PK composta (alert_id, acs_id), que o ORM do
/// Serverpod não suporta: virou id próprio mais um índice UNIQUE no par,
/// preservando a mesma garantia de unicidade.
///
/// Distinto de AlertDelivery, que é o DTO de fio MQTT e continua escrito à mão.
abstract class AlertDeliveryRecord implements _i1.SerializableModel {
  AlertDeliveryRecord._({
    this.id,
    required this.alertId,
    required this.acsId,
    required this.acknowledgedAt,
  });

  factory AlertDeliveryRecord({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required _i1.UuidValue acsId,
    required DateTime acknowledgedAt,
  }) = _AlertDeliveryRecordImpl;

  factory AlertDeliveryRecord.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertDeliveryRecord(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      alertId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['alertId'],
      ),
      acsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      acknowledgedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['acknowledgedAt'],
      ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue alertId;

  _i1.UuidValue acsId;

  DateTime acknowledgedAt;

  /// Returns a shallow copy of this [AlertDeliveryRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertDeliveryRecord copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? alertId,
    _i1.UuidValue? acsId,
    DateTime? acknowledgedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertDeliveryRecord',
      if (id != null) 'id': id?.toJson(),
      'alertId': alertId.toJson(),
      'acsId': acsId.toJson(),
      'acknowledgedAt': acknowledgedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertDeliveryRecordImpl extends AlertDeliveryRecord {
  _AlertDeliveryRecordImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required _i1.UuidValue acsId,
    required DateTime acknowledgedAt,
  }) : super._(
         id: id,
         alertId: alertId,
         acsId: acsId,
         acknowledgedAt: acknowledgedAt,
       );

  /// Returns a shallow copy of this [AlertDeliveryRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertDeliveryRecord copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? alertId,
    _i1.UuidValue? acsId,
    DateTime? acknowledgedAt,
  }) {
    return AlertDeliveryRecord(
      id: id is _i1.UuidValue? ? id : this.id,
      alertId: alertId ?? this.alertId,
      acsId: acsId ?? this.acsId,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }
}
