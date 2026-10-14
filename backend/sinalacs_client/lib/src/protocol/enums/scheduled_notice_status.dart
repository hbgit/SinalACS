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

/// Ciclo de um aviso agendado. `sending` é a reserva atômica anti-duplicidade.
enum ScheduledNoticeStatus implements _i1.SerializableModel {
  pending,
  sending,
  sent,
  unknown,
  failed,
  cancelled;

  static ScheduledNoticeStatus fromJson(String name) {
    switch (name) {
      case 'pending':
        return ScheduledNoticeStatus.pending;
      case 'sending':
        return ScheduledNoticeStatus.sending;
      case 'sent':
        return ScheduledNoticeStatus.sent;
      case 'unknown':
        return ScheduledNoticeStatus.unknown;
      case 'failed':
        return ScheduledNoticeStatus.failed;
      case 'cancelled':
        return ScheduledNoticeStatus.cancelled;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "ScheduledNoticeStatus"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
