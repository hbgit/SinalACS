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

/// Deduplicação durável de alertas por chave de idempotência.
///
/// Antes a deduplicação era um Map em memória: sumia no restart e não valia
/// entre instâncias, de modo que um reenvio após queda gerava alerta duplicado.
/// Persistir a chave torna a garantia durável e válida em qualquer réplica.
///
/// A linha é gravada na mesma transação do alerta: se a publicação falhar,
/// ambas desaparecem e o cliente pode retentar de verdade.
abstract class AlertIdempotencyKey implements _i1.SerializableModel {
  AlertIdempotencyKey._({
    this.id,
    required this.key,
    required this.alertId,
    required this.locationHash,
    required this.createdAt,
  });

  factory AlertIdempotencyKey({
    _i1.UuidValue? id,
    required String key,
    required _i1.UuidValue alertId,
    required String locationHash,
    required DateTime createdAt,
  }) = _AlertIdempotencyKeyImpl;

  factory AlertIdempotencyKey.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertIdempotencyKey(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      key: jsonSerialization['key'] as String,
      alertId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['alertId'],
      ),
      locationHash: jsonSerialization['locationHash'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  /// Chave fornecida pelo cliente.
  String key;

  /// Alerta que esta chave produziu.
  _i1.UuidValue alertId;

  /// Guardado para rejeitar reuso da mesma chave com outra localização.
  String locationHash;

  DateTime createdAt;

  /// Returns a shallow copy of this [AlertIdempotencyKey]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertIdempotencyKey copyWith({
    _i1.UuidValue? id,
    String? key,
    _i1.UuidValue? alertId,
    String? locationHash,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertIdempotencyKey',
      if (id != null) 'id': id?.toJson(),
      'key': key,
      'alertId': alertId.toJson(),
      'locationHash': locationHash,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertIdempotencyKeyImpl extends AlertIdempotencyKey {
  _AlertIdempotencyKeyImpl({
    _i1.UuidValue? id,
    required String key,
    required _i1.UuidValue alertId,
    required String locationHash,
    required DateTime createdAt,
  }) : super._(
         id: id,
         key: key,
         alertId: alertId,
         locationHash: locationHash,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [AlertIdempotencyKey]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertIdempotencyKey copyWith({
    Object? id = _Undefined,
    String? key,
    _i1.UuidValue? alertId,
    String? locationHash,
    DateTime? createdAt,
  }) {
    return AlertIdempotencyKey(
      id: id is _i1.UuidValue? ? id : this.id,
      key: key ?? this.key,
      alertId: alertId ?? this.alertId,
      locationHash: locationHash ?? this.locationHash,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
