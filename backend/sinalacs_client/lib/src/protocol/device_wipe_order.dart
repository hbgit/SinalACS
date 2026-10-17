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
import 'enums/device_wipe_reason.dart' as _i2;

/// Pedido de limpeza remota do aparelho de um ACS (#81). Um por aparelho
/// (índice único em `deviceId`): pedir de novo devolve o pedido original.
///
/// O pedido não carrega dado pessoal: só ids, o motivo (conjunto fechado) e os
/// carimbos. `deliveredAt` marca a primeira vez que o aparelho foi mandado
/// limpar; `confirmedAt`, a confirmação do próprio aparelho de que limpou.
abstract class DeviceWipeOrder implements _i1.SerializableModel {
  DeviceWipeOrder._({
    this.id,
    required this.deviceId,
    required this.targetUserId,
    required this.requestedBy,
    required this.reason,
    required this.requestedAt,
    this.deliveredAt,
    this.confirmedAt,
  });

  factory DeviceWipeOrder({
    _i1.UuidValue? id,
    required String deviceId,
    required _i1.UuidValue targetUserId,
    required _i1.UuidValue requestedBy,
    required _i2.DeviceWipeReason reason,
    required DateTime requestedAt,
    DateTime? deliveredAt,
    DateTime? confirmedAt,
  }) = _DeviceWipeOrderImpl;

  factory DeviceWipeOrder.fromJson(Map<String, dynamic> jsonSerialization) {
    return DeviceWipeOrder(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      deviceId: jsonSerialization['deviceId'] as String,
      targetUserId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['targetUserId'],
      ),
      requestedBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['requestedBy'],
      ),
      reason: _i2.DeviceWipeReason.fromJson(
        (jsonSerialization['reason'] as String),
      ),
      requestedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['requestedAt'],
      ),
      deliveredAt: jsonSerialization['deliveredAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['deliveredAt'],
            ),
      confirmedAt: jsonSerialization['confirmedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['confirmedAt'],
            ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  /// Instalação alvo (`acs_refresh_tokens.deviceId`).
  String deviceId;

  /// O ACS dono do aparelho no momento do pedido.
  _i1.UuidValue targetUserId;

  /// Quem pediu (coordenador ou administrador).
  _i1.UuidValue requestedBy;

  _i2.DeviceWipeReason reason;

  DateTime requestedAt;

  DateTime? deliveredAt;

  DateTime? confirmedAt;

  /// Returns a shallow copy of this [DeviceWipeOrder]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceWipeOrder copyWith({
    _i1.UuidValue? id,
    String? deviceId,
    _i1.UuidValue? targetUserId,
    _i1.UuidValue? requestedBy,
    _i2.DeviceWipeReason? reason,
    DateTime? requestedAt,
    DateTime? deliveredAt,
    DateTime? confirmedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceWipeOrder',
      if (id != null) 'id': id?.toJson(),
      'deviceId': deviceId,
      'targetUserId': targetUserId.toJson(),
      'requestedBy': requestedBy.toJson(),
      'reason': reason.toJson(),
      'requestedAt': requestedAt.toJson(),
      if (deliveredAt != null) 'deliveredAt': deliveredAt?.toJson(),
      if (confirmedAt != null) 'confirmedAt': confirmedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DeviceWipeOrderImpl extends DeviceWipeOrder {
  _DeviceWipeOrderImpl({
    _i1.UuidValue? id,
    required String deviceId,
    required _i1.UuidValue targetUserId,
    required _i1.UuidValue requestedBy,
    required _i2.DeviceWipeReason reason,
    required DateTime requestedAt,
    DateTime? deliveredAt,
    DateTime? confirmedAt,
  }) : super._(
         id: id,
         deviceId: deviceId,
         targetUserId: targetUserId,
         requestedBy: requestedBy,
         reason: reason,
         requestedAt: requestedAt,
         deliveredAt: deliveredAt,
         confirmedAt: confirmedAt,
       );

  /// Returns a shallow copy of this [DeviceWipeOrder]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceWipeOrder copyWith({
    Object? id = _Undefined,
    String? deviceId,
    _i1.UuidValue? targetUserId,
    _i1.UuidValue? requestedBy,
    _i2.DeviceWipeReason? reason,
    DateTime? requestedAt,
    Object? deliveredAt = _Undefined,
    Object? confirmedAt = _Undefined,
  }) {
    return DeviceWipeOrder(
      id: id is _i1.UuidValue? ? id : this.id,
      deviceId: deviceId ?? this.deviceId,
      targetUserId: targetUserId ?? this.targetUserId,
      requestedBy: requestedBy ?? this.requestedBy,
      reason: reason ?? this.reason,
      requestedAt: requestedAt ?? this.requestedAt,
      deliveredAt: deliveredAt is DateTime? ? deliveredAt : this.deliveredAt,
      confirmedAt: confirmedAt is DateTime? ? confirmedAt : this.confirmedAt,
    );
  }
}
