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

/// Forma exata do antigo GET /health. O HEALTHCHECK do Dockerfile e o runbook
/// de free-tier dependem destes três campos, então a forma é preservada.
/// Sempre responde ok assim que o servidor sobe, independente do estado do
/// broker e do banco — hosts free-tier hibernam e precisam responder mesmo com
/// dependências fora do ar.
abstract class ServiceHealth implements _i1.SerializableModel {
  ServiceHealth._({
    required this.status,
    required this.mqttConnected,
    required this.dbConnected,
  });

  factory ServiceHealth({
    required String status,
    required bool mqttConnected,
    required bool dbConnected,
  }) = _ServiceHealthImpl;

  factory ServiceHealth.fromJson(Map<String, dynamic> jsonSerialization) {
    return ServiceHealth(
      status: jsonSerialization['status'] as String,
      mqttConnected: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['mqttConnected'],
      ),
      dbConnected: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['dbConnected'],
      ),
    );
  }

  String status;

  bool mqttConnected;

  bool dbConnected;

  /// Returns a shallow copy of this [ServiceHealth]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ServiceHealth copyWith({
    String? status,
    bool? mqttConnected,
    bool? dbConnected,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ServiceHealth',
      'status': status,
      'mqttConnected': mqttConnected,
      'dbConnected': dbConnected,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _ServiceHealthImpl extends ServiceHealth {
  _ServiceHealthImpl({
    required String status,
    required bool mqttConnected,
    required bool dbConnected,
  }) : super._(
         status: status,
         mqttConnected: mqttConnected,
         dbConnected: dbConnected,
       );

  /// Returns a shallow copy of this [ServiceHealth]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ServiceHealth copyWith({
    String? status,
    bool? mqttConnected,
    bool? dbConnected,
  }) {
    return ServiceHealth(
      status: status ?? this.status,
      mqttConnected: mqttConnected ?? this.mqttConnected,
      dbConnected: dbConnected ?? this.dbConnected,
    );
  }
}
