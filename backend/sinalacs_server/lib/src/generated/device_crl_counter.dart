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

/// Contador da extensão `CRL Number` da CRL dos aparelhos (#94). Uma única
/// linha (`id = 1`), incrementada a cada publicação; começa em 1000, acima do
/// `01` da CRL inicial do `init.sh`, e sobrevive a reinícios. Sem dado pessoal.
abstract class DeviceCrlCounter
    implements _i1.TableRow<int?>, _i1.ProtocolSerialization {
  DeviceCrlCounter._({
    this.id,
    required this.lastNumber,
  });

  factory DeviceCrlCounter({
    int? id,
    required int lastNumber,
  }) = _DeviceCrlCounterImpl;

  factory DeviceCrlCounter.fromJson(Map<String, dynamic> jsonSerialization) {
    return DeviceCrlCounter(
      id: jsonSerialization['id'] as int?,
      lastNumber: jsonSerialization['lastNumber'] as int,
    );
  }

  static final t = DeviceCrlCounterTable();

  static const db = DeviceCrlCounterRepository._();

  @override
  int? id;

  int lastNumber;

  @override
  _i1.Table<int?> get table => t;

  /// Returns a shallow copy of this [DeviceCrlCounter]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCrlCounter copyWith({
    int? id,
    int? lastNumber,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCrlCounter',
      if (id != null) 'id': id,
      'lastNumber': lastNumber,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceCrlCounter',
      if (id != null) 'id': id,
      'lastNumber': lastNumber,
    };
  }

  static DeviceCrlCounterInclude include() {
    return DeviceCrlCounterInclude._();
  }

  static DeviceCrlCounterIncludeList includeList({
    _i1.WhereExpressionBuilder<DeviceCrlCounterTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceCrlCounterTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceCrlCounterTable>? orderByList,
    DeviceCrlCounterInclude? include,
  }) {
    return DeviceCrlCounterIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DeviceCrlCounter.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(DeviceCrlCounter.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DeviceCrlCounterImpl extends DeviceCrlCounter {
  _DeviceCrlCounterImpl({
    int? id,
    required int lastNumber,
  }) : super._(
         id: id,
         lastNumber: lastNumber,
       );

  /// Returns a shallow copy of this [DeviceCrlCounter]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCrlCounter copyWith({
    Object? id = _Undefined,
    int? lastNumber,
  }) {
    return DeviceCrlCounter(
      id: id is int? ? id : this.id,
      lastNumber: lastNumber ?? this.lastNumber,
    );
  }
}

class DeviceCrlCounterUpdateTable
    extends _i1.UpdateTable<DeviceCrlCounterTable> {
  DeviceCrlCounterUpdateTable(super.table);

  _i1.ColumnValue<int, int> lastNumber(int value) => _i1.ColumnValue(
    table.lastNumber,
    value,
  );
}

class DeviceCrlCounterTable extends _i1.Table<int?> {
  DeviceCrlCounterTable({super.tableRelation})
    : super(tableName: 'device_crl_counters') {
    updateTable = DeviceCrlCounterUpdateTable(this);
    lastNumber = _i1.ColumnInt(
      'lastNumber',
      this,
    );
  }

  late final DeviceCrlCounterUpdateTable updateTable;

  late final _i1.ColumnInt lastNumber;

  @override
  List<_i1.Column> get columns => [
    id,
    lastNumber,
  ];
}

class DeviceCrlCounterInclude extends _i1.IncludeObject {
  DeviceCrlCounterInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<int?> get table => DeviceCrlCounter.t;
}

class DeviceCrlCounterIncludeList extends _i1.IncludeList {
  DeviceCrlCounterIncludeList._({
    _i1.WhereExpressionBuilder<DeviceCrlCounterTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(DeviceCrlCounter.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<int?> get table => DeviceCrlCounter.t;
}

class DeviceCrlCounterRepository {
  const DeviceCrlCounterRepository._();

  /// Returns a list of [DeviceCrlCounter]s matching the given query parameters.
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
  Future<List<DeviceCrlCounter>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceCrlCounterTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceCrlCounterTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceCrlCounterTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<DeviceCrlCounter>(
      where: where?.call(DeviceCrlCounter.t),
      orderBy: orderBy?.call(DeviceCrlCounter.t),
      orderByList: orderByList?.call(DeviceCrlCounter.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [DeviceCrlCounter] matching the given query parameters.
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
  Future<DeviceCrlCounter?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceCrlCounterTable>? where,
    int? offset,
    _i1.OrderByBuilder<DeviceCrlCounterTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceCrlCounterTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<DeviceCrlCounter>(
      where: where?.call(DeviceCrlCounter.t),
      orderBy: orderBy?.call(DeviceCrlCounter.t),
      orderByList: orderByList?.call(DeviceCrlCounter.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [DeviceCrlCounter] by its [id] or null if no such row exists.
  Future<DeviceCrlCounter?> findById(
    _i1.DatabaseSession session,
    int id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<DeviceCrlCounter>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [DeviceCrlCounter]s in the list and returns the inserted rows.
  ///
  /// The returned [DeviceCrlCounter]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<DeviceCrlCounter>> insert(
    _i1.DatabaseSession session,
    List<DeviceCrlCounter> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<DeviceCrlCounter>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [DeviceCrlCounter] and returns the inserted row.
  ///
  /// The returned [DeviceCrlCounter] will have its `id` field set.
  Future<DeviceCrlCounter> insertRow(
    _i1.DatabaseSession session,
    DeviceCrlCounter row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<DeviceCrlCounter>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [DeviceCrlCounter]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<DeviceCrlCounter>> update(
    _i1.DatabaseSession session,
    List<DeviceCrlCounter> rows, {
    _i1.ColumnSelections<DeviceCrlCounterTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<DeviceCrlCounter>(
      rows,
      columns: columns?.call(DeviceCrlCounter.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DeviceCrlCounter]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<DeviceCrlCounter> updateRow(
    _i1.DatabaseSession session,
    DeviceCrlCounter row, {
    _i1.ColumnSelections<DeviceCrlCounterTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<DeviceCrlCounter>(
      row,
      columns: columns?.call(DeviceCrlCounter.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DeviceCrlCounter] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<DeviceCrlCounter?> updateById(
    _i1.DatabaseSession session,
    int id, {
    required _i1.ColumnValueListBuilder<DeviceCrlCounterUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<DeviceCrlCounter>(
      id,
      columnValues: columnValues(DeviceCrlCounter.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [DeviceCrlCounter]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<DeviceCrlCounter>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<DeviceCrlCounterUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<DeviceCrlCounterTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceCrlCounterTable>? orderBy,
    _i1.OrderByListBuilder<DeviceCrlCounterTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<DeviceCrlCounter>(
      columnValues: columnValues(DeviceCrlCounter.t.updateTable),
      where: where(DeviceCrlCounter.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DeviceCrlCounter.t),
      orderByList: orderByList?.call(DeviceCrlCounter.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [DeviceCrlCounter]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<DeviceCrlCounter>> delete(
    _i1.DatabaseSession session,
    List<DeviceCrlCounter> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<DeviceCrlCounter>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [DeviceCrlCounter].
  Future<DeviceCrlCounter> deleteRow(
    _i1.DatabaseSession session,
    DeviceCrlCounter row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<DeviceCrlCounter>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<DeviceCrlCounter>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DeviceCrlCounterTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<DeviceCrlCounter>(
      where: where(DeviceCrlCounter.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceCrlCounterTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<DeviceCrlCounter>(
      where: where?.call(DeviceCrlCounter.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [DeviceCrlCounter] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DeviceCrlCounterTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<DeviceCrlCounter>(
      where: where(DeviceCrlCounter.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
