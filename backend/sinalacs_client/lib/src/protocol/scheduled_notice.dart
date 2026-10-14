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
import 'enums/scheduled_notice_status.dart' as _i2;

/// Aviso comunitário agendado por staff (RF14, #46). O texto fica aqui porque o
/// staff o digitou para ser enviado; ele nunca vai para audit_logs.
abstract class ScheduledNotice implements _i1.SerializableModel {
  ScheduledNotice._({
    this.id,
    required this.createdBy,
    required this.microAreaId,
    required this.audience,
    required this.title,
    required this.message,
    required this.scheduledFor,
    required this.status,
    this.recipients,
    this.accepted,
    this.failureReason,
    required this.createdAt,
    this.sentAt,
  });

  factory ScheduledNotice({
    _i1.UuidValue? id,
    required _i1.UuidValue createdBy,
    required _i1.UuidValue microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
    required _i2.ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime createdAt,
    DateTime? sentAt,
  }) = _ScheduledNoticeImpl;

  factory ScheduledNotice.fromJson(Map<String, dynamic> jsonSerialization) {
    return ScheduledNotice(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      createdBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['createdBy'],
      ),
      microAreaId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['microAreaId'],
      ),
      audience: jsonSerialization['audience'] as String,
      title: jsonSerialization['title'] as String,
      message: jsonSerialization['message'] as String,
      scheduledFor: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['scheduledFor'],
      ),
      status: _i2.ScheduledNoticeStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      recipients: jsonSerialization['recipients'] as int?,
      accepted: jsonSerialization['accepted'] as int?,
      failureReason: jsonSerialization['failureReason'] as String?,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      sentAt: jsonSerialization['sentAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['sentAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue createdBy;

  _i1.UuidValue microAreaId;

  String audience;

  String title;

  String message;

  DateTime scheduledFor;

  _i2.ScheduledNoticeStatus status;

  int? recipients;

  int? accepted;

  String? failureReason;

  DateTime createdAt;

  DateTime? sentAt;

  /// Returns a shallow copy of this [ScheduledNotice]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ScheduledNotice copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? createdBy,
    _i1.UuidValue? microAreaId,
    String? audience,
    String? title,
    String? message,
    DateTime? scheduledFor,
    _i2.ScheduledNoticeStatus? status,
    int? recipients,
    int? accepted,
    String? failureReason,
    DateTime? createdAt,
    DateTime? sentAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ScheduledNotice',
      if (id != null) 'id': id?.toJson(),
      'createdBy': createdBy.toJson(),
      'microAreaId': microAreaId.toJson(),
      'audience': audience,
      'title': title,
      'message': message,
      'scheduledFor': scheduledFor.toJson(),
      'status': status.toJson(),
      if (recipients != null) 'recipients': recipients,
      if (accepted != null) 'accepted': accepted,
      if (failureReason != null) 'failureReason': failureReason,
      'createdAt': createdAt.toJson(),
      if (sentAt != null) 'sentAt': sentAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ScheduledNoticeImpl extends ScheduledNotice {
  _ScheduledNoticeImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue createdBy,
    required _i1.UuidValue microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
    required _i2.ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime createdAt,
    DateTime? sentAt,
  }) : super._(
         id: id,
         createdBy: createdBy,
         microAreaId: microAreaId,
         audience: audience,
         title: title,
         message: message,
         scheduledFor: scheduledFor,
         status: status,
         recipients: recipients,
         accepted: accepted,
         failureReason: failureReason,
         createdAt: createdAt,
         sentAt: sentAt,
       );

  /// Returns a shallow copy of this [ScheduledNotice]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ScheduledNotice copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? createdBy,
    _i1.UuidValue? microAreaId,
    String? audience,
    String? title,
    String? message,
    DateTime? scheduledFor,
    _i2.ScheduledNoticeStatus? status,
    Object? recipients = _Undefined,
    Object? accepted = _Undefined,
    Object? failureReason = _Undefined,
    DateTime? createdAt,
    Object? sentAt = _Undefined,
  }) {
    return ScheduledNotice(
      id: id is _i1.UuidValue? ? id : this.id,
      createdBy: createdBy ?? this.createdBy,
      microAreaId: microAreaId ?? this.microAreaId,
      audience: audience ?? this.audience,
      title: title ?? this.title,
      message: message ?? this.message,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      status: status ?? this.status,
      recipients: recipients is int? ? recipients : this.recipients,
      accepted: accepted is int? ? accepted : this.accepted,
      failureReason: failureReason is String?
          ? failureReason
          : this.failureReason,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt is DateTime? ? sentAt : this.sentAt,
    );
  }
}
