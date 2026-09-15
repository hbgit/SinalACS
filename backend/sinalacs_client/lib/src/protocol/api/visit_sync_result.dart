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
import '../enums/sync_status.dart' as _i2;

/// Resultado da sincronização de UMA visita.
///
/// O app casa pelo `localId`, não pela posição na lista: um resultado ausente
/// deixa a visita pendente para a próxima tentativa, em vez de dá-la por
/// sincronizada.
abstract class VisitSyncResult implements _i1.SerializableModel {
  VisitSyncResult._({
    required this.localId,
    required this.syncStatus,
    this.serverVersion,
    this.message,
  });

  factory VisitSyncResult({
    required String localId,
    required _i2.SyncStatus syncStatus,
    int? serverVersion,
    String? message,
  }) = _VisitSyncResultImpl;

  factory VisitSyncResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return VisitSyncResult(
      localId: jsonSerialization['localId'] as String,
      syncStatus: _i2.SyncStatus.fromJson(
        (jsonSerialization['syncStatus'] as String),
      ),
      serverVersion: jsonSerialization['serverVersion'] as int?,
      message: jsonSerialization['message'] as String?,
    );
  }

  String localId;

  _i2.SyncStatus syncStatus;

  /// Versão gravada no servidor. Em conflito, é a versão que o dispositivo
  /// precisa reconciliar antes de reenviar.
  int? serverVersion;

  /// Preenchido apenas quando syncStatus é error.
  String? message;

  /// Returns a shallow copy of this [VisitSyncResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  VisitSyncResult copyWith({
    String? localId,
    _i2.SyncStatus? syncStatus,
    int? serverVersion,
    String? message,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'VisitSyncResult',
      'localId': localId,
      'syncStatus': syncStatus.toJson(),
      if (serverVersion != null) 'serverVersion': serverVersion,
      if (message != null) 'message': message,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _VisitSyncResultImpl extends VisitSyncResult {
  _VisitSyncResultImpl({
    required String localId,
    required _i2.SyncStatus syncStatus,
    int? serverVersion,
    String? message,
  }) : super._(
         localId: localId,
         syncStatus: syncStatus,
         serverVersion: serverVersion,
         message: message,
       );

  /// Returns a shallow copy of this [VisitSyncResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  VisitSyncResult copyWith({
    String? localId,
    _i2.SyncStatus? syncStatus,
    Object? serverVersion = _Undefined,
    Object? message = _Undefined,
  }) {
    return VisitSyncResult(
      localId: localId ?? this.localId,
      syncStatus: syncStatus ?? this.syncStatus,
      serverVersion: serverVersion is int? ? serverVersion : this.serverVersion,
      message: message is String? ? message : this.message,
    );
  }
}
