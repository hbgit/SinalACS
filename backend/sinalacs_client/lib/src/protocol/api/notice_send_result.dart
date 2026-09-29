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

/// Resultado de `notices.sendSegmented` (RF14): quantos pacientes da microárea
/// consentiram em receber o aviso e quantas notificações o relé aceitou.
/// Só contagens — nunca a lista de destinatários.
abstract class NoticeSendResult implements _i1.SerializableModel {
  NoticeSendResult._({
    required this.recipients,
    required this.accepted,
  });

  factory NoticeSendResult({
    required int recipients,
    required int accepted,
  }) = _NoticeSendResultImpl;

  factory NoticeSendResult.fromJson(Map<String, dynamic> jsonSerialization) {
    return NoticeSendResult(
      recipients: jsonSerialization['recipients'] as int,
      accepted: jsonSerialization['accepted'] as int,
    );
  }

  int recipients;

  int accepted;

  /// Returns a shallow copy of this [NoticeSendResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  NoticeSendResult copyWith({
    int? recipients,
    int? accepted,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NoticeSendResult',
      'recipients': recipients,
      'accepted': accepted,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _NoticeSendResultImpl extends NoticeSendResult {
  _NoticeSendResultImpl({
    required int recipients,
    required int accepted,
  }) : super._(
         recipients: recipients,
         accepted: accepted,
       );

  /// Returns a shallow copy of this [NoticeSendResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  NoticeSendResult copyWith({
    int? recipients,
    int? accepted,
  }) {
    return NoticeSendResult(
      recipients: recipients ?? this.recipients,
      accepted: accepted ?? this.accepted,
    );
  }
}
