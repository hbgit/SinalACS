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

/// Registro de consentimento LGPD. Append-only.
abstract class ConsentLog
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  ConsentLog._({
    this.id,
    required this.userId,
    required this.purpose,
    required this.action,
    required this.version,
    required this.timestamp,
    required this.ipHash,
    required this.userAgent,
    required this.signature,
  });

  factory ConsentLog({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
    required String ipHash,
    required String userAgent,
    required String signature,
  }) = _ConsentLogImpl;

  factory ConsentLog.fromJson(Map<String, dynamic> jsonSerialization) {
    return ConsentLog(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      purpose: jsonSerialization['purpose'] as String,
      action: jsonSerialization['action'] as String,
      version: jsonSerialization['version'] as String,
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      ipHash: jsonSerialization['ipHash'] as String,
      userAgent: jsonSerialization['userAgent'] as String,
      signature: jsonSerialization['signature'] as String,
    );
  }

  static final t = ConsentLogTable();

  static const db = ConsentLogRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  String purpose;

  String action;

  String version;

  DateTime timestamp;

  String ipHash;

  String userAgent;

  String signature;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [ConsentLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ConsentLog copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? purpose,
    String? action,
    String? version,
    DateTime? timestamp,
    String? ipHash,
    String? userAgent,
    String? signature,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ConsentLog',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'purpose': purpose,
      'action': action,
      'version': version,
      'timestamp': timestamp.toJson(),
      'ipHash': ipHash,
      'userAgent': userAgent,
      'signature': signature,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ConsentLog',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'purpose': purpose,
      'action': action,
      'version': version,
      'timestamp': timestamp.toJson(),
      'ipHash': ipHash,
      'userAgent': userAgent,
      'signature': signature,
    };
  }

  static ConsentLogInclude include() {
    return ConsentLogInclude._();
  }

  static ConsentLogIncludeList includeList({
    _i1.WhereExpressionBuilder<ConsentLogTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<ConsentLogTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<ConsentLogTable>? orderByList,
    ConsentLogInclude? include,
  }) {
    return ConsentLogIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ConsentLog.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(ConsentLog.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ConsentLogImpl extends ConsentLog {
  _ConsentLogImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
    required String ipHash,
    required String userAgent,
    required String signature,
  }) : super._(
         id: id,
         userId: userId,
         purpose: purpose,
         action: action,
         version: version,
         timestamp: timestamp,
         ipHash: ipHash,
         userAgent: userAgent,
         signature: signature,
       );

  /// Returns a shallow copy of this [ConsentLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ConsentLog copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? purpose,
    String? action,
    String? version,
    DateTime? timestamp,
    String? ipHash,
    String? userAgent,
    String? signature,
  }) {
    return ConsentLog(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      purpose: purpose ?? this.purpose,
      action: action ?? this.action,
      version: version ?? this.version,
      timestamp: timestamp ?? this.timestamp,
      ipHash: ipHash ?? this.ipHash,
      userAgent: userAgent ?? this.userAgent,
      signature: signature ?? this.signature,
    );
  }
}

class ConsentLogUpdateTable extends _i1.UpdateTable<ConsentLogTable> {
  ConsentLogUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<String, String> purpose(String value) => _i1.ColumnValue(
    table.purpose,
    value,
  );

  _i1.ColumnValue<String, String> action(String value) => _i1.ColumnValue(
    table.action,
    value,
  );

  _i1.ColumnValue<String, String> version(String value) => _i1.ColumnValue(
    table.version,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> timestamp(DateTime value) =>
      _i1.ColumnValue(
        table.timestamp,
        value,
      );

  _i1.ColumnValue<String, String> ipHash(String value) => _i1.ColumnValue(
    table.ipHash,
    value,
  );

  _i1.ColumnValue<String, String> userAgent(String value) => _i1.ColumnValue(
    table.userAgent,
    value,
  );

  _i1.ColumnValue<String, String> signature(String value) => _i1.ColumnValue(
    table.signature,
    value,
  );
}

class ConsentLogTable extends _i1.Table<_i1.UuidValue?> {
  ConsentLogTable({super.tableRelation}) : super(tableName: 'consent_logs') {
    updateTable = ConsentLogUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    purpose = _i1.ColumnString(
      'purpose',
      this,
    );
    action = _i1.ColumnString(
      'action',
      this,
    );
    version = _i1.ColumnString(
      'version',
      this,
    );
    timestamp = _i1.ColumnDateTime(
      'timestamp',
      this,
    );
    ipHash = _i1.ColumnString(
      'ipHash',
      this,
    );
    userAgent = _i1.ColumnString(
      'userAgent',
      this,
    );
    signature = _i1.ColumnString(
      'signature',
      this,
    );
  }

  late final ConsentLogUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  late final _i1.ColumnString purpose;

  late final _i1.ColumnString action;

  late final _i1.ColumnString version;

  late final _i1.ColumnDateTime timestamp;

  late final _i1.ColumnString ipHash;

  late final _i1.ColumnString userAgent;

  late final _i1.ColumnString signature;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    purpose,
    action,
    version,
    timestamp,
    ipHash,
    userAgent,
    signature,
  ];
}

class ConsentLogInclude extends _i1.IncludeObject {
  ConsentLogInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => ConsentLog.t;
}

class ConsentLogIncludeList extends _i1.IncludeList {
  ConsentLogIncludeList._({
    _i1.WhereExpressionBuilder<ConsentLogTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(ConsentLog.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => ConsentLog.t;
}

class ConsentLogRepository {
  const ConsentLogRepository._();

  /// Returns a list of [ConsentLog]s matching the given query parameters.
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
  Future<List<ConsentLog>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<ConsentLogTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<ConsentLogTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<ConsentLogTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<ConsentLog>(
      where: where?.call(ConsentLog.t),
      orderBy: orderBy?.call(ConsentLog.t),
      orderByList: orderByList?.call(ConsentLog.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [ConsentLog] matching the given query parameters.
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
  Future<ConsentLog?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<ConsentLogTable>? where,
    int? offset,
    _i1.OrderByBuilder<ConsentLogTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<ConsentLogTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<ConsentLog>(
      where: where?.call(ConsentLog.t),
      orderBy: orderBy?.call(ConsentLog.t),
      orderByList: orderByList?.call(ConsentLog.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [ConsentLog] by its [id] or null if no such row exists.
  Future<ConsentLog?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<ConsentLog>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [ConsentLog]s in the list and returns the inserted rows.
  ///
  /// The returned [ConsentLog]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<ConsentLog>> insert(
    _i1.DatabaseSession session,
    List<ConsentLog> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<ConsentLog>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [ConsentLog] and returns the inserted row.
  ///
  /// The returned [ConsentLog] will have its `id` field set.
  Future<ConsentLog> insertRow(
    _i1.DatabaseSession session,
    ConsentLog row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<ConsentLog>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [ConsentLog]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<ConsentLog>> update(
    _i1.DatabaseSession session,
    List<ConsentLog> rows, {
    _i1.ColumnSelections<ConsentLogTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<ConsentLog>(
      rows,
      columns: columns?.call(ConsentLog.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ConsentLog]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<ConsentLog> updateRow(
    _i1.DatabaseSession session,
    ConsentLog row, {
    _i1.ColumnSelections<ConsentLogTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<ConsentLog>(
      row,
      columns: columns?.call(ConsentLog.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ConsentLog] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<ConsentLog?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<ConsentLogUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<ConsentLog>(
      id,
      columnValues: columnValues(ConsentLog.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [ConsentLog]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<ConsentLog>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<ConsentLogUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<ConsentLogTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<ConsentLogTable>? orderBy,
    _i1.OrderByListBuilder<ConsentLogTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<ConsentLog>(
      columnValues: columnValues(ConsentLog.t.updateTable),
      where: where(ConsentLog.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ConsentLog.t),
      orderByList: orderByList?.call(ConsentLog.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [ConsentLog]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<ConsentLog>> delete(
    _i1.DatabaseSession session,
    List<ConsentLog> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<ConsentLog>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [ConsentLog].
  Future<ConsentLog> deleteRow(
    _i1.DatabaseSession session,
    ConsentLog row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<ConsentLog>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<ConsentLog>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<ConsentLogTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<ConsentLog>(
      where: where(ConsentLog.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<ConsentLogTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<ConsentLog>(
      where: where?.call(ConsentLog.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [ConsentLog] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<ConsentLogTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<ConsentLog>(
      where: where(ConsentLog.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
