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
import '../enums/device_wipe_state.dart' as _i2;

/// Aparelho de um ACS na listagem do backoffice (#81). O rótulo é derivado do
/// `deviceId` (`Aparelho ` + 8 primeiros caracteres): o app não envia modelo
/// nem nome do aparelho, e o id completo não precisa chegar à tela.
abstract class AdminAcsDevice implements _i1.SerializableModel {
  AdminAcsDevice._({
    required this.deviceId,
    required this.label,
    required this.lastSeenAt,
    this.wipeState,
    this.wipeRequestedAt,
    this.wipeConfirmedAt,
  });

  factory AdminAcsDevice({
    required String deviceId,
    required String label,
    required DateTime lastSeenAt,
    _i2.DeviceWipeState? wipeState,
    DateTime? wipeRequestedAt,
    DateTime? wipeConfirmedAt,
  }) = _AdminAcsDeviceImpl;

  factory AdminAcsDevice.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAcsDevice(
      deviceId: jsonSerialization['deviceId'] as String,
      label: jsonSerialization['label'] as String,
      lastSeenAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['lastSeenAt'],
      ),
      wipeState: jsonSerialization['wipeState'] == null
          ? null
          : _i2.DeviceWipeState.fromJson(
              (jsonSerialization['wipeState'] as String),
            ),
      wipeRequestedAt: jsonSerialization['wipeRequestedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['wipeRequestedAt'],
            ),
      wipeConfirmedAt: jsonSerialization['wipeConfirmedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['wipeConfirmedAt'],
            ),
    );
  }

  String deviceId;

  String label;

  /// Maior `issuedAt` entre os tokens do aparelho.
  DateTime lastSeenAt;

  /// `null` = sem pedido de limpeza.
  _i2.DeviceWipeState? wipeState;

  DateTime? wipeRequestedAt;

  DateTime? wipeConfirmedAt;

  /// Returns a shallow copy of this [AdminAcsDevice]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAcsDevice copyWith({
    String? deviceId,
    String? label,
    DateTime? lastSeenAt,
    _i2.DeviceWipeState? wipeState,
    DateTime? wipeRequestedAt,
    DateTime? wipeConfirmedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAcsDevice',
      'deviceId': deviceId,
      'label': label,
      'lastSeenAt': lastSeenAt.toJson(),
      if (wipeState != null) 'wipeState': wipeState?.toJson(),
      if (wipeRequestedAt != null) 'wipeRequestedAt': wipeRequestedAt?.toJson(),
      if (wipeConfirmedAt != null) 'wipeConfirmedAt': wipeConfirmedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAcsDeviceImpl extends AdminAcsDevice {
  _AdminAcsDeviceImpl({
    required String deviceId,
    required String label,
    required DateTime lastSeenAt,
    _i2.DeviceWipeState? wipeState,
    DateTime? wipeRequestedAt,
    DateTime? wipeConfirmedAt,
  }) : super._(
         deviceId: deviceId,
         label: label,
         lastSeenAt: lastSeenAt,
         wipeState: wipeState,
         wipeRequestedAt: wipeRequestedAt,
         wipeConfirmedAt: wipeConfirmedAt,
       );

  /// Returns a shallow copy of this [AdminAcsDevice]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAcsDevice copyWith({
    String? deviceId,
    String? label,
    DateTime? lastSeenAt,
    Object? wipeState = _Undefined,
    Object? wipeRequestedAt = _Undefined,
    Object? wipeConfirmedAt = _Undefined,
  }) {
    return AdminAcsDevice(
      deviceId: deviceId ?? this.deviceId,
      label: label ?? this.label,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      wipeState: wipeState is _i2.DeviceWipeState? ? wipeState : this.wipeState,
      wipeRequestedAt: wipeRequestedAt is DateTime?
          ? wipeRequestedAt
          : this.wipeRequestedAt,
      wipeConfirmedAt: wipeConfirmedAt is DateTime?
          ? wipeConfirmedAt
          : this.wipeConfirmedAt,
    );
  }
}
