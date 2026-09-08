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

/// Microárea: a unidade de territorialização que delimita o acesso do ACS.
abstract class MicroArea
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  MicroArea._({
    this.id,
    required this.name,
    required this.ubsId,
    required this.geoJsonBoundary,
  });

  factory MicroArea({
    _i1.UuidValue? id,
    required String name,
    required _i1.UuidValue ubsId,
    required String geoJsonBoundary,
  }) = _MicroAreaImpl;

  factory MicroArea.fromJson(Map<String, dynamic> jsonSerialization) {
    return MicroArea(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      name: jsonSerialization['name'] as String,
      ubsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['ubsId']),
      geoJsonBoundary: jsonSerialization['geoJsonBoundary'] as String,
    );
  }

  static final t = MicroAreaTable();

  static const db = MicroAreaRepository._();

  @override
  _i1.UuidValue? id;

  String name;

  _i1.UuidValue ubsId;

  String geoJsonBoundary;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [MicroArea]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  MicroArea copyWith({
    _i1.UuidValue? id,
    String? name,
    _i1.UuidValue? ubsId,
    String? geoJsonBoundary,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MicroArea',
      if (id != null) 'id': id?.toJson(),
      'name': name,
      'ubsId': ubsId.toJson(),
      'geoJsonBoundary': geoJsonBoundary,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MicroArea',
      if (id != null) 'id': id?.toJson(),
      'name': name,
      'ubsId': ubsId.toJson(),
      'geoJsonBoundary': geoJsonBoundary,
    };
  }

  static MicroAreaInclude include() {
    return MicroAreaInclude._();
  }

  static MicroAreaIncludeList includeList({
    _i1.WhereExpressionBuilder<MicroAreaTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<MicroAreaTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<MicroAreaTable>? orderByList,
    MicroAreaInclude? include,
  }) {
    return MicroAreaIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MicroArea.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(MicroArea.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MicroAreaImpl extends MicroArea {
  _MicroAreaImpl({
    _i1.UuidValue? id,
    required String name,
    required _i1.UuidValue ubsId,
    required String geoJsonBoundary,
  }) : super._(
         id: id,
         name: name,
         ubsId: ubsId,
         geoJsonBoundary: geoJsonBoundary,
       );

  /// Returns a shallow copy of this [MicroArea]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  MicroArea copyWith({
    Object? id = _Undefined,
    String? name,
    _i1.UuidValue? ubsId,
    String? geoJsonBoundary,
  }) {
    return MicroArea(
      id: id is _i1.UuidValue? ? id : this.id,
      name: name ?? this.name,
      ubsId: ubsId ?? this.ubsId,
      geoJsonBoundary: geoJsonBoundary ?? this.geoJsonBoundary,
    );
  }
}

class MicroAreaUpdateTable extends _i1.UpdateTable<MicroAreaTable> {
  MicroAreaUpdateTable(super.table);

  _i1.ColumnValue<String, String> name(String value) => _i1.ColumnValue(
    table.name,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> ubsId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.ubsId,
        value,
      );

  _i1.ColumnValue<String, String> geoJsonBoundary(String value) =>
      _i1.ColumnValue(
        table.geoJsonBoundary,
        value,
      );
}

class MicroAreaTable extends _i1.Table<_i1.UuidValue?> {
  MicroAreaTable({super.tableRelation}) : super(tableName: 'micro_areas') {
    updateTable = MicroAreaUpdateTable(this);
    name = _i1.ColumnString(
      'name',
      this,
    );
    ubsId = _i1.ColumnUuid(
      'ubsId',
      this,
    );
    geoJsonBoundary = _i1.ColumnString(
      'geoJsonBoundary',
      this,
    );
  }

  late final MicroAreaUpdateTable updateTable;

  late final _i1.ColumnString name;

  late final _i1.ColumnUuid ubsId;

  late final _i1.ColumnString geoJsonBoundary;

  @override
  List<_i1.Column> get columns => [
    id,
    name,
    ubsId,
    geoJsonBoundary,
  ];
}

class MicroAreaInclude extends _i1.IncludeObject {
  MicroAreaInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => MicroArea.t;
}

class MicroAreaIncludeList extends _i1.IncludeList {
  MicroAreaIncludeList._({
    _i1.WhereExpressionBuilder<MicroAreaTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(MicroArea.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => MicroArea.t;
}

class MicroAreaRepository {
  const MicroAreaRepository._();

  /// Returns a list of [MicroArea]s matching the given query parameters.
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
  Future<List<MicroArea>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<MicroAreaTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<MicroAreaTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<MicroAreaTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<MicroArea>(
      where: where?.call(MicroArea.t),
      orderBy: orderBy?.call(MicroArea.t),
      orderByList: orderByList?.call(MicroArea.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [MicroArea] matching the given query parameters.
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
  Future<MicroArea?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<MicroAreaTable>? where,
    int? offset,
    _i1.OrderByBuilder<MicroAreaTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<MicroAreaTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<MicroArea>(
      where: where?.call(MicroArea.t),
      orderBy: orderBy?.call(MicroArea.t),
      orderByList: orderByList?.call(MicroArea.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [MicroArea] by its [id] or null if no such row exists.
  Future<MicroArea?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<MicroArea>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [MicroArea]s in the list and returns the inserted rows.
  ///
  /// The returned [MicroArea]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<MicroArea>> insert(
    _i1.DatabaseSession session,
    List<MicroArea> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<MicroArea>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [MicroArea] and returns the inserted row.
  ///
  /// The returned [MicroArea] will have its `id` field set.
  Future<MicroArea> insertRow(
    _i1.DatabaseSession session,
    MicroArea row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<MicroArea>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [MicroArea]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<MicroArea>> update(
    _i1.DatabaseSession session,
    List<MicroArea> rows, {
    _i1.ColumnSelections<MicroAreaTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<MicroArea>(
      rows,
      columns: columns?.call(MicroArea.t),
      transaction: transaction,
    );
  }

  /// Updates a single [MicroArea]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<MicroArea> updateRow(
    _i1.DatabaseSession session,
    MicroArea row, {
    _i1.ColumnSelections<MicroAreaTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<MicroArea>(
      row,
      columns: columns?.call(MicroArea.t),
      transaction: transaction,
    );
  }

  /// Updates a single [MicroArea] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<MicroArea?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<MicroAreaUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<MicroArea>(
      id,
      columnValues: columnValues(MicroArea.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [MicroArea]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<MicroArea>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<MicroAreaUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<MicroAreaTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<MicroAreaTable>? orderBy,
    _i1.OrderByListBuilder<MicroAreaTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<MicroArea>(
      columnValues: columnValues(MicroArea.t.updateTable),
      where: where(MicroArea.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MicroArea.t),
      orderByList: orderByList?.call(MicroArea.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [MicroArea]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<MicroArea>> delete(
    _i1.DatabaseSession session,
    List<MicroArea> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<MicroArea>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [MicroArea].
  Future<MicroArea> deleteRow(
    _i1.DatabaseSession session,
    MicroArea row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<MicroArea>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<MicroArea>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<MicroAreaTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<MicroArea>(
      where: where(MicroArea.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<MicroAreaTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<MicroArea>(
      where: where?.call(MicroArea.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [MicroArea] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<MicroAreaTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<MicroArea>(
      where: where(MicroArea.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
