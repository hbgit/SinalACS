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

import 'package:serverpod/serverpod.dart' as _i1;
import 'enums/scheduled_notice_status.dart' as _i2;

/// Aviso comunitário agendado por staff (RF14, #46). O texto fica aqui porque o
/// staff o digitou para ser enviado; ele nunca vai para audit_logs.
abstract class ScheduledNotice
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
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

  static final t = ScheduledNoticeTable();

  static const db = ScheduledNoticeRepository._();

  @override
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

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

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
  Map<String, dynamic> toJsonForProtocol() {
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

  static ScheduledNoticeInclude include() {
    return ScheduledNoticeInclude._();
  }

  static ScheduledNoticeIncludeList includeList({
    _i1.WhereExpressionBuilder<ScheduledNoticeTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<ScheduledNoticeTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<ScheduledNoticeTable>? orderByList,
    ScheduledNoticeInclude? include,
  }) {
    return ScheduledNoticeIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ScheduledNotice.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(ScheduledNotice.t),
      include: include,
    );
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

class ScheduledNoticeUpdateTable extends _i1.UpdateTable<ScheduledNoticeTable> {
  ScheduledNoticeUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> createdBy(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.createdBy,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> microAreaId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.microAreaId,
    value,
  );

  _i1.ColumnValue<String, String> audience(String value) => _i1.ColumnValue(
    table.audience,
    value,
  );

  _i1.ColumnValue<String, String> title(String value) => _i1.ColumnValue(
    table.title,
    value,
  );

  _i1.ColumnValue<String, String> message(String value) => _i1.ColumnValue(
    table.message,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> scheduledFor(DateTime value) =>
      _i1.ColumnValue(
        table.scheduledFor,
        value,
      );

  _i1.ColumnValue<_i2.ScheduledNoticeStatus, _i2.ScheduledNoticeStatus> status(
    _i2.ScheduledNoticeStatus value,
  ) => _i1.ColumnValue(
    table.status,
    value,
  );

  _i1.ColumnValue<int, int> recipients(int? value) => _i1.ColumnValue(
    table.recipients,
    value,
  );

  _i1.ColumnValue<int, int> accepted(int? value) => _i1.ColumnValue(
    table.accepted,
    value,
  );

  _i1.ColumnValue<String, String> failureReason(String? value) =>
      _i1.ColumnValue(
        table.failureReason,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> sentAt(DateTime? value) =>
      _i1.ColumnValue(
        table.sentAt,
        value,
      );
}

class ScheduledNoticeTable extends _i1.Table<_i1.UuidValue?> {
  ScheduledNoticeTable({super.tableRelation})
    : super(tableName: 'scheduled_notices') {
    updateTable = ScheduledNoticeUpdateTable(this);
    createdBy = _i1.ColumnUuid(
      'createdBy',
      this,
    );
    microAreaId = _i1.ColumnUuid(
      'microAreaId',
      this,
    );
    audience = _i1.ColumnString(
      'audience',
      this,
    );
    title = _i1.ColumnString(
      'title',
      this,
    );
    message = _i1.ColumnString(
      'message',
      this,
    );
    scheduledFor = _i1.ColumnDateTime(
      'scheduledFor',
      this,
    );
    status = _i1.ColumnEnum(
      'status',
      this,
      _i1.EnumSerialization.byName,
    );
    recipients = _i1.ColumnInt(
      'recipients',
      this,
    );
    accepted = _i1.ColumnInt(
      'accepted',
      this,
    );
    failureReason = _i1.ColumnString(
      'failureReason',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    sentAt = _i1.ColumnDateTime(
      'sentAt',
      this,
    );
  }

  late final ScheduledNoticeUpdateTable updateTable;

  late final _i1.ColumnUuid createdBy;

  late final _i1.ColumnUuid microAreaId;

  late final _i1.ColumnString audience;

  late final _i1.ColumnString title;

  late final _i1.ColumnString message;

  late final _i1.ColumnDateTime scheduledFor;

  late final _i1.ColumnEnum<_i2.ScheduledNoticeStatus> status;

  late final _i1.ColumnInt recipients;

  late final _i1.ColumnInt accepted;

  late final _i1.ColumnString failureReason;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnDateTime sentAt;

  @override
  List<_i1.Column> get columns => [
    id,
    createdBy,
    microAreaId,
    audience,
    title,
    message,
    scheduledFor,
    status,
    recipients,
    accepted,
    failureReason,
    createdAt,
    sentAt,
  ];
}

class ScheduledNoticeInclude extends _i1.IncludeObject {
  ScheduledNoticeInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => ScheduledNotice.t;
}

class ScheduledNoticeIncludeList extends _i1.IncludeList {
  ScheduledNoticeIncludeList._({
    _i1.WhereExpressionBuilder<ScheduledNoticeTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(ScheduledNotice.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => ScheduledNotice.t;
}

class ScheduledNoticeRepository {
  const ScheduledNoticeRepository._();

  /// Returns a list of [ScheduledNotice]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<ScheduledNotice>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<ScheduledNoticeTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<ScheduledNoticeTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<ScheduledNoticeTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<ScheduledNotice>(
      where: where?.call(ScheduledNotice.t),
      orderBy: orderBy?.call(ScheduledNotice.t),
      orderByList: orderByList?.call(ScheduledNotice.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [ScheduledNotice] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<ScheduledNotice?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<ScheduledNoticeTable>? where,
    int? offset,
    _i1.OrderByBuilder<ScheduledNoticeTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<ScheduledNoticeTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<ScheduledNotice>(
      where: where?.call(ScheduledNotice.t),
      orderBy: orderBy?.call(ScheduledNotice.t),
      orderByList: orderByList?.call(ScheduledNotice.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [ScheduledNotice] by its [id] or null if no such row exists.
  Future<ScheduledNotice?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<ScheduledNotice>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [ScheduledNotice]s in the list and returns the inserted rows.
  ///
  /// The returned [ScheduledNotice]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<ScheduledNotice>> insert(
    _i1.DatabaseSession session,
    List<ScheduledNotice> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<ScheduledNotice>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [ScheduledNotice] and returns the inserted row.
  ///
  /// The returned [ScheduledNotice] will have its `id` field set.
  Future<ScheduledNotice> insertRow(
    _i1.DatabaseSession session,
    ScheduledNotice row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<ScheduledNotice>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [ScheduledNotice]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<ScheduledNotice>> update(
    _i1.DatabaseSession session,
    List<ScheduledNotice> rows, {
    _i1.ColumnSelections<ScheduledNoticeTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<ScheduledNotice>(
      rows,
      columns: columns?.call(ScheduledNotice.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ScheduledNotice]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<ScheduledNotice> updateRow(
    _i1.DatabaseSession session,
    ScheduledNotice row, {
    _i1.ColumnSelections<ScheduledNoticeTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<ScheduledNotice>(
      row,
      columns: columns?.call(ScheduledNotice.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ScheduledNotice] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<ScheduledNotice?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<ScheduledNoticeUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<ScheduledNotice>(
      id,
      columnValues: columnValues(ScheduledNotice.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [ScheduledNotice]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<ScheduledNotice>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<ScheduledNoticeUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<ScheduledNoticeTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<ScheduledNoticeTable>? orderBy,
    _i1.OrderByListBuilder<ScheduledNoticeTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<ScheduledNotice>(
      columnValues: columnValues(ScheduledNotice.t.updateTable),
      where: where(ScheduledNotice.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ScheduledNotice.t),
      orderByList: orderByList?.call(ScheduledNotice.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [ScheduledNotice]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<ScheduledNotice>> delete(
    _i1.DatabaseSession session,
    List<ScheduledNotice> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<ScheduledNotice>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [ScheduledNotice].
  Future<ScheduledNotice> deleteRow(
    _i1.DatabaseSession session,
    ScheduledNotice row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<ScheduledNotice>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<ScheduledNotice>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<ScheduledNoticeTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<ScheduledNotice>(
      where: where(ScheduledNotice.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<ScheduledNoticeTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<ScheduledNotice>(
      where: where?.call(ScheduledNotice.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [ScheduledNotice] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<ScheduledNoticeTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<ScheduledNotice>(
      where: where(ScheduledNotice.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
