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

/// Confirmação de recebimento de um alerta por um ACS.
///
/// O schema original usava PK composta (alert_id, acs_id), que o ORM do
/// Serverpod não suporta: virou id próprio mais um índice UNIQUE no par,
/// preservando a mesma garantia de unicidade.
///
/// Distinto de AlertDelivery, que é o DTO de fio MQTT e continua escrito à mão.
abstract class AlertDeliveryRecord
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AlertDeliveryRecord._({
    this.id,
    required this.alertId,
    required this.acsId,
    required this.acknowledgedAt,
  });

  factory AlertDeliveryRecord({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required _i1.UuidValue acsId,
    required DateTime acknowledgedAt,
  }) = _AlertDeliveryRecordImpl;

  factory AlertDeliveryRecord.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertDeliveryRecord(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      alertId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['alertId'],
      ),
      acsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      acknowledgedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['acknowledgedAt'],
      ),
    );
  }

  static final t = AlertDeliveryRecordTable();

  static const db = AlertDeliveryRecordRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue alertId;

  _i1.UuidValue acsId;

  DateTime acknowledgedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AlertDeliveryRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertDeliveryRecord copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? alertId,
    _i1.UuidValue? acsId,
    DateTime? acknowledgedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertDeliveryRecord',
      if (id != null) 'id': id?.toJson(),
      'alertId': alertId.toJson(),
      'acsId': acsId.toJson(),
      'acknowledgedAt': acknowledgedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AlertDeliveryRecord',
      if (id != null) 'id': id?.toJson(),
      'alertId': alertId.toJson(),
      'acsId': acsId.toJson(),
      'acknowledgedAt': acknowledgedAt.toJson(),
    };
  }

  static AlertDeliveryRecordInclude include() {
    return AlertDeliveryRecordInclude._();
  }

  static AlertDeliveryRecordIncludeList includeList({
    _i1.WhereExpressionBuilder<AlertDeliveryRecordTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertDeliveryRecordTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertDeliveryRecordTable>? orderByList,
    AlertDeliveryRecordInclude? include,
  }) {
    return AlertDeliveryRecordIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertDeliveryRecord.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AlertDeliveryRecord.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertDeliveryRecordImpl extends AlertDeliveryRecord {
  _AlertDeliveryRecordImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required _i1.UuidValue acsId,
    required DateTime acknowledgedAt,
  }) : super._(
         id: id,
         alertId: alertId,
         acsId: acsId,
         acknowledgedAt: acknowledgedAt,
       );

  /// Returns a shallow copy of this [AlertDeliveryRecord]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertDeliveryRecord copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? alertId,
    _i1.UuidValue? acsId,
    DateTime? acknowledgedAt,
  }) {
    return AlertDeliveryRecord(
      id: id is _i1.UuidValue? ? id : this.id,
      alertId: alertId ?? this.alertId,
      acsId: acsId ?? this.acsId,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }
}

class AlertDeliveryRecordUpdateTable
    extends _i1.UpdateTable<AlertDeliveryRecordTable> {
  AlertDeliveryRecordUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> alertId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.alertId,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> acsId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.acsId,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> acknowledgedAt(DateTime value) =>
      _i1.ColumnValue(
        table.acknowledgedAt,
        value,
      );
}

class AlertDeliveryRecordTable extends _i1.Table<_i1.UuidValue?> {
  AlertDeliveryRecordTable({super.tableRelation})
    : super(tableName: 'alert_deliveries') {
    updateTable = AlertDeliveryRecordUpdateTable(this);
    alertId = _i1.ColumnUuid(
      'alertId',
      this,
    );
    acsId = _i1.ColumnUuid(
      'acsId',
      this,
    );
    acknowledgedAt = _i1.ColumnDateTime(
      'acknowledgedAt',
      this,
    );
  }

  late final AlertDeliveryRecordUpdateTable updateTable;

  late final _i1.ColumnUuid alertId;

  late final _i1.ColumnUuid acsId;

  late final _i1.ColumnDateTime acknowledgedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    alertId,
    acsId,
    acknowledgedAt,
  ];
}

class AlertDeliveryRecordInclude extends _i1.IncludeObject {
  AlertDeliveryRecordInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AlertDeliveryRecord.t;
}

class AlertDeliveryRecordIncludeList extends _i1.IncludeList {
  AlertDeliveryRecordIncludeList._({
    _i1.WhereExpressionBuilder<AlertDeliveryRecordTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AlertDeliveryRecord.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AlertDeliveryRecord.t;
}

class AlertDeliveryRecordRepository {
  const AlertDeliveryRecordRepository._();

  /// Returns a list of [AlertDeliveryRecord]s matching the given query parameters.
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
  Future<List<AlertDeliveryRecord>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertDeliveryRecordTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertDeliveryRecordTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertDeliveryRecordTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AlertDeliveryRecord>(
      where: where?.call(AlertDeliveryRecord.t),
      orderBy: orderBy?.call(AlertDeliveryRecord.t),
      orderByList: orderByList?.call(AlertDeliveryRecord.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AlertDeliveryRecord] matching the given query parameters.
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
  Future<AlertDeliveryRecord?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertDeliveryRecordTable>? where,
    int? offset,
    _i1.OrderByBuilder<AlertDeliveryRecordTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertDeliveryRecordTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AlertDeliveryRecord>(
      where: where?.call(AlertDeliveryRecord.t),
      orderBy: orderBy?.call(AlertDeliveryRecord.t),
      orderByList: orderByList?.call(AlertDeliveryRecord.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AlertDeliveryRecord] by its [id] or null if no such row exists.
  Future<AlertDeliveryRecord?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AlertDeliveryRecord>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AlertDeliveryRecord]s in the list and returns the inserted rows.
  ///
  /// The returned [AlertDeliveryRecord]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AlertDeliveryRecord>> insert(
    _i1.DatabaseSession session,
    List<AlertDeliveryRecord> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AlertDeliveryRecord>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AlertDeliveryRecord] and returns the inserted row.
  ///
  /// The returned [AlertDeliveryRecord] will have its `id` field set.
  Future<AlertDeliveryRecord> insertRow(
    _i1.DatabaseSession session,
    AlertDeliveryRecord row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AlertDeliveryRecord>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AlertDeliveryRecord]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AlertDeliveryRecord>> update(
    _i1.DatabaseSession session,
    List<AlertDeliveryRecord> rows, {
    _i1.ColumnSelections<AlertDeliveryRecordTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AlertDeliveryRecord>(
      rows,
      columns: columns?.call(AlertDeliveryRecord.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertDeliveryRecord]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AlertDeliveryRecord> updateRow(
    _i1.DatabaseSession session,
    AlertDeliveryRecord row, {
    _i1.ColumnSelections<AlertDeliveryRecordTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AlertDeliveryRecord>(
      row,
      columns: columns?.call(AlertDeliveryRecord.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertDeliveryRecord] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AlertDeliveryRecord?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AlertDeliveryRecordUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AlertDeliveryRecord>(
      id,
      columnValues: columnValues(AlertDeliveryRecord.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AlertDeliveryRecord]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AlertDeliveryRecord>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AlertDeliveryRecordUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<AlertDeliveryRecordTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertDeliveryRecordTable>? orderBy,
    _i1.OrderByListBuilder<AlertDeliveryRecordTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AlertDeliveryRecord>(
      columnValues: columnValues(AlertDeliveryRecord.t.updateTable),
      where: where(AlertDeliveryRecord.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertDeliveryRecord.t),
      orderByList: orderByList?.call(AlertDeliveryRecord.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AlertDeliveryRecord]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AlertDeliveryRecord>> delete(
    _i1.DatabaseSession session,
    List<AlertDeliveryRecord> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AlertDeliveryRecord>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AlertDeliveryRecord].
  Future<AlertDeliveryRecord> deleteRow(
    _i1.DatabaseSession session,
    AlertDeliveryRecord row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AlertDeliveryRecord>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AlertDeliveryRecord>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertDeliveryRecordTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AlertDeliveryRecord>(
      where: where(AlertDeliveryRecord.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertDeliveryRecordTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AlertDeliveryRecord>(
      where: where?.call(AlertDeliveryRecord.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AlertDeliveryRecord] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertDeliveryRecordTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AlertDeliveryRecord>(
      where: where(AlertDeliveryRecord.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
