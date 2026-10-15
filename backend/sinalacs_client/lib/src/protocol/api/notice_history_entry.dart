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
import '../enums/scheduled_notice_status.dart' as _i2;

/// Linha do histórico de avisos agendados (#46). Deliberadamente SEM o texto
/// da mensagem: o backoffice lista título, alvo e resultado.
///
/// `createdByLabel` é a matrícula de quem agendou ("—" se a conta não tem).
/// `recipients`/`accepted` só existem depois do envio; `failureReason` só em
/// `failed`/`unknown`.
abstract class NoticeHistoryEntry implements _i1.SerializableModel {
  NoticeHistoryEntry._({
    required this.id,
    required this.microAreaId,
    required this.microAreaName,
    required this.audience,
    required this.title,
    required this.status,
    required this.scheduledFor,
    this.sentAt,
    this.recipients,
    this.accepted,
    this.failureReason,
    required this.createdByLabel,
  });

  factory NoticeHistoryEntry({
    required String id,
    required String microAreaId,
    required String microAreaName,
    required String audience,
    required String title,
    required _i2.ScheduledNoticeStatus status,
    required DateTime scheduledFor,
    DateTime? sentAt,
    int? recipients,
    int? accepted,
    String? failureReason,
    required String createdByLabel,
  }) = _NoticeHistoryEntryImpl;

  factory NoticeHistoryEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return NoticeHistoryEntry(
      id: jsonSerialization['id'] as String,
      microAreaId: jsonSerialization['microAreaId'] as String,
      microAreaName: jsonSerialization['microAreaName'] as String,
      audience: jsonSerialization['audience'] as String,
      title: jsonSerialization['title'] as String,
      status: _i2.ScheduledNoticeStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      scheduledFor: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['scheduledFor'],
      ),
      sentAt: jsonSerialization['sentAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['sentAt']),
      recipients: jsonSerialization['recipients'] as int?,
      accepted: jsonSerialization['accepted'] as int?,
      failureReason: jsonSerialization['failureReason'] as String?,
      createdByLabel: jsonSerialization['createdByLabel'] as String,
    );
  }

  String id;

  String microAreaId;

  String microAreaName;

  String audience;

  String title;

  _i2.ScheduledNoticeStatus status;

  DateTime scheduledFor;

  DateTime? sentAt;

  int? recipients;

  int? accepted;

  String? failureReason;

  String createdByLabel;

  /// Returns a shallow copy of this [NoticeHistoryEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  NoticeHistoryEntry copyWith({
    String? id,
    String? microAreaId,
    String? microAreaName,
    String? audience,
    String? title,
    _i2.ScheduledNoticeStatus? status,
    DateTime? scheduledFor,
    DateTime? sentAt,
    int? recipients,
    int? accepted,
    String? failureReason,
    String? createdByLabel,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NoticeHistoryEntry',
      'id': id,
      'microAreaId': microAreaId,
      'microAreaName': microAreaName,
      'audience': audience,
      'title': title,
      'status': status.toJson(),
      'scheduledFor': scheduledFor.toJson(),
      if (sentAt != null) 'sentAt': sentAt?.toJson(),
      if (recipients != null) 'recipients': recipients,
      if (accepted != null) 'accepted': accepted,
      if (failureReason != null) 'failureReason': failureReason,
      'createdByLabel': createdByLabel,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _NoticeHistoryEntryImpl extends NoticeHistoryEntry {
  _NoticeHistoryEntryImpl({
    required String id,
    required String microAreaId,
    required String microAreaName,
    required String audience,
    required String title,
    required _i2.ScheduledNoticeStatus status,
    required DateTime scheduledFor,
    DateTime? sentAt,
    int? recipients,
    int? accepted,
    String? failureReason,
    required String createdByLabel,
  }) : super._(
         id: id,
         microAreaId: microAreaId,
         microAreaName: microAreaName,
         audience: audience,
         title: title,
         status: status,
         scheduledFor: scheduledFor,
         sentAt: sentAt,
         recipients: recipients,
         accepted: accepted,
         failureReason: failureReason,
         createdByLabel: createdByLabel,
       );

  /// Returns a shallow copy of this [NoticeHistoryEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  NoticeHistoryEntry copyWith({
    String? id,
    String? microAreaId,
    String? microAreaName,
    String? audience,
    String? title,
    _i2.ScheduledNoticeStatus? status,
    DateTime? scheduledFor,
    Object? sentAt = _Undefined,
    Object? recipients = _Undefined,
    Object? accepted = _Undefined,
    Object? failureReason = _Undefined,
    String? createdByLabel,
  }) {
    return NoticeHistoryEntry(
      id: id ?? this.id,
      microAreaId: microAreaId ?? this.microAreaId,
      microAreaName: microAreaName ?? this.microAreaName,
      audience: audience ?? this.audience,
      title: title ?? this.title,
      status: status ?? this.status,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      sentAt: sentAt is DateTime? ? sentAt : this.sentAt,
      recipients: recipients is int? ? recipients : this.recipients,
      accepted: accepted is int? ? accepted : this.accepted,
      failureReason: failureReason is String?
          ? failureReason
          : this.failureReason,
      createdByLabel: createdByLabel ?? this.createdByLabel,
    );
  }
}
