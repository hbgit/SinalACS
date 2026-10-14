import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/notices/notice_scheduling_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// [ScheduledNoticeStore] sobre o Postgres (#46).
///
/// As transições de estado (`pending -> sending`, cancelamento, varredura) são
/// UMA instrução SQL cada, com parâmetros nomeados, para serem atômicas entre
/// instâncias e entre o laço de disparo e o cancelamento do backoffice.
class OrmScheduledNoticeStore implements ScheduledNoticeStore {
  OrmScheduledNoticeStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  static const _columns =
      '"id", "createdBy", "microAreaId", "audience", "title", "message", '
      '"scheduledFor", "status", "recipients", "accepted", "failureReason", '
      '"createdAt", "sentAt"';

  static const _historyColumns =
      's."id", s."createdBy", s."microAreaId", s."audience", s."title", '
      's."message", s."scheduledFor", s."status", s."recipients", s."accepted", '
      's."failureReason", s."createdAt", s."sentAt", '
      'm."name" AS "microAreaName", sa."enrollmentId" AS "createdByLabel"';

  @override
  Future<String?> ubsOfStaff(String userId) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT "ubsId" FROM staff_accounts WHERE "id" = @id::uuid',
      parameters: QueryParameters.named({'id': userId}),
    );
    if (rows.isEmpty) return null;
    return rows.first.toColumnMap()['ubsId']?.toString();
  }

  @override
  Future<String?> ubsOfMicroArea(String microAreaId) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT "ubsId" FROM micro_areas WHERE "id" = @id::uuid',
      parameters: QueryParameters.named({'id': microAreaId}),
    );
    if (rows.isEmpty) return null;
    return rows.first.toColumnMap()['ubsId']?.toString();
  }

  @override
  Future<String> insert({
    required String createdBy,
    required String microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
    required DateTime createdAt,
  }) async {
    final row = await ScheduledNotice.db.insertRow(
      _session(),
      ScheduledNotice(
        createdBy: UuidValue.fromString(createdBy),
        microAreaId: UuidValue.fromString(microAreaId),
        audience: audience,
        title: title,
        message: message,
        scheduledFor: scheduledFor,
        status: ScheduledNoticeStatus.pending,
        createdAt: createdAt,
      ),
    );
    return row.id!.toString();
  }

  @override
  Future<ScheduledNoticeSnapshot?> findById(String id) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT $_columns FROM scheduled_notices WHERE "id" = @id::uuid',
      parameters: QueryParameters.named({'id': id}),
    );
    return rows.isEmpty ? null : _snapshot(rows.first.toColumnMap());
  }

  @override
  Future<bool> cancelIfPending(String id) async {
    final rows = await _session().db.unsafeQuery(
      '''
      UPDATE scheduled_notices SET "status" = 'cancelled'
      WHERE "id" = @id::uuid AND "status" = 'pending'
      RETURNING "id"
      ''',
      parameters: QueryParameters.named({'id': id}),
    );
    return rows.length == 1;
  }

  @override
  Future<List<ScheduledNoticeSnapshot>> claimDue(DateTime now, {int limit = 20}) async {
    final rows = await _session().db.unsafeQuery(
      '''
      UPDATE scheduled_notices SET "status" = 'sending'
      WHERE "id" IN (
        SELECT "id" FROM scheduled_notices
        WHERE "status" = 'pending' AND "scheduledFor" <= @now
        ORDER BY "scheduledFor"
        LIMIT @lim
        FOR UPDATE SKIP LOCKED
      )
      RETURNING $_columns
      ''',
      parameters: QueryParameters.named({'now': now.toUtc(), 'lim': limit}),
    );
    final claimed = [for (final r in rows) _snapshot(r.toColumnMap())];
    claimed.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return claimed;
  }

  @override
  Future<void> finish(
    String id, {
    required ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime at,
  }) async {
    await _session().db.unsafeExecute(
      '''
      UPDATE scheduled_notices
      SET "status" = @status::text, "recipients" = @recipients::bigint,
          "accepted" = @accepted::bigint, "failureReason" = @reason::text,
          "sentAt" = @sentAt::timestamp
      WHERE "id" = @id::uuid
      ''',
      parameters: QueryParameters.named({
        'id': id,
        'status': status.name,
        'recipients': recipients,
        'accepted': accepted,
        'reason': failureReason,
        'sentAt': status == ScheduledNoticeStatus.sent ? at.toUtc() : null,
      }),
    );
  }

  @override
  Future<int> markStaleSendingUnknown({
    required DateTime before,
    required String reason,
    required DateTime at,
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      UPDATE scheduled_notices
      SET "status" = 'unknown', "failureReason" = @reason
      WHERE "status" = 'sending' AND "scheduledFor" < @before
      RETURNING "id"
      ''',
      parameters: QueryParameters.named({'reason': reason, 'before': before.toUtc()}),
    );
    return rows.length;
  }

  @override
  Future<List<ScheduledNoticeSnapshot>> history({
    String? microAreaId,
    String? ubsId,
    required int limit,
    required int offset,
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT $_historyColumns
      FROM scheduled_notices s
      JOIN micro_areas m ON m."id" = s."microAreaId"
      LEFT JOIN staff_accounts sa ON sa."id" = s."createdBy"
      WHERE (@micro::uuid IS NULL OR s."microAreaId" = @micro::uuid)
        AND (@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)
      ORDER BY s."scheduledFor" DESC, s."id" DESC
      LIMIT @lim OFFSET @off
      ''',
      parameters: QueryParameters.named({
        'micro': microAreaId,
        'ubs': ubsId,
        'lim': limit,
        'off': offset,
      }),
    );
    return [for (final r in rows) _snapshot(r.toColumnMap())];
  }

  ScheduledNoticeSnapshot _snapshot(Map<String, dynamic> c) => ScheduledNoticeSnapshot(
        id: c['id'].toString(),
        createdBy: c['createdBy'].toString(),
        microAreaId: c['microAreaId'].toString(),
        audience: c['audience'] as String,
        title: c['title'] as String,
        message: c['message'] as String,
        scheduledFor: _utc(c['scheduledFor'] as DateTime),
        status: ScheduledNoticeStatus.values.byName(c['status'] as String),
        recipients: c['recipients'] as int?,
        accepted: c['accepted'] as int?,
        failureReason: c['failureReason'] as String?,
        createdAt: _utc(c['createdAt'] as DateTime),
        sentAt: c['sentAt'] == null ? null : _utc(c['sentAt'] as DateTime),
        microAreaName: c['microAreaName'] as String?,
        createdByLabel: c['createdByLabel'] as String?,
      );

  static DateTime _utc(DateTime d) => d.isUtc ? d : DateTime.utc(
        d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
}
