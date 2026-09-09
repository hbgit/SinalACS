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

/// Outbox transacional de entrega de alertas.
///
/// A intenção de publicar é gravada na MESMA transação do alerta; a publicação
/// no broker acontece depois do commit. Isso fecha as duas janelas que existiam
/// quando o publish rodava dentro da transação: publicar e falhar o commit
/// entregava um alerta sem linha no banco, deixando o ACK sem o que atualizar.
///
/// Um alerta vermelho nunca pode ser perdido nem entregue sem registro
/// (INV-03), então a entrada só é marcada como publicada depois da publicação.
abstract class AlertOutboxEntry implements _i1.SerializableModel {
  AlertOutboxEntry._({
    this.id,
    required this.alertId,
    required this.topic,
    required this.payload,
    required this.createdAt,
    this.publishedAt,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
  });

  factory AlertOutboxEntry({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required String topic,
    required String payload,
    required DateTime createdAt,
    DateTime? publishedAt,
    required int attempts,
    required DateTime nextAttemptAt,
    String? lastError,
  }) = _AlertOutboxEntryImpl;

  factory AlertOutboxEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertOutboxEntry(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      alertId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['alertId'],
      ),
      topic: jsonSerialization['topic'] as String,
      payload: jsonSerialization['payload'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      publishedAt: jsonSerialization['publishedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['publishedAt'],
            ),
      attempts: jsonSerialization['attempts'] as int,
      nextAttemptAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['nextAttemptAt'],
      ),
      lastError: jsonSerialization['lastError'] as String?,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue alertId;

  /// Tópico MQTT de destino, resolvido no momento do enfileiramento.
  String topic;

  /// Envelope já serializado por AlertDelivery.toJson().
  String payload;

  DateTime createdAt;

  /// Nulo enquanto pendente; carimbado após a publicação.
  DateTime? publishedAt;

  int attempts;

  /// Quando a próxima tentativa é elegível. Cresce com backoff exponencial.
  DateTime nextAttemptAt;

  String? lastError;

  /// Returns a shallow copy of this [AlertOutboxEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertOutboxEntry copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? alertId,
    String? topic,
    String? payload,
    DateTime? createdAt,
    DateTime? publishedAt,
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertOutboxEntry',
      if (id != null) 'id': id?.toJson(),
      'alertId': alertId.toJson(),
      'topic': topic,
      'payload': payload,
      'createdAt': createdAt.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt.toJson(),
      if (lastError != null) 'lastError': lastError,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertOutboxEntryImpl extends AlertOutboxEntry {
  _AlertOutboxEntryImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required String topic,
    required String payload,
    required DateTime createdAt,
    DateTime? publishedAt,
    required int attempts,
    required DateTime nextAttemptAt,
    String? lastError,
  }) : super._(
         id: id,
         alertId: alertId,
         topic: topic,
         payload: payload,
         createdAt: createdAt,
         publishedAt: publishedAt,
         attempts: attempts,
         nextAttemptAt: nextAttemptAt,
         lastError: lastError,
       );

  /// Returns a shallow copy of this [AlertOutboxEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertOutboxEntry copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? alertId,
    String? topic,
    String? payload,
    DateTime? createdAt,
    Object? publishedAt = _Undefined,
    int? attempts,
    DateTime? nextAttemptAt,
    Object? lastError = _Undefined,
  }) {
    return AlertOutboxEntry(
      id: id is _i1.UuidValue? ? id : this.id,
      alertId: alertId ?? this.alertId,
      topic: topic ?? this.topic,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt is DateTime? ? publishedAt : this.publishedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError is String? ? lastError : this.lastError,
    );
  }
}
