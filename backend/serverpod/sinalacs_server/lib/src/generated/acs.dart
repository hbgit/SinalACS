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

/// Agente Comunitário de Saúde.
///
/// Mesma decisão de chave aplicada em Patient: o id desta tabela é o UUID do
/// usuário, fornecido na inserção.
abstract class Acs
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  Acs._({
    this.id,
    required this.enrollmentId,
    required this.ubsId,
    required this.active,
    this.lastSyncAt,
  });

  factory Acs({
    _i1.UuidValue? id,
    required String enrollmentId,
    required _i1.UuidValue ubsId,
    required bool active,
    DateTime? lastSyncAt,
  }) = _AcsImpl;

  factory Acs.fromJson(Map<String, dynamic> jsonSerialization) {
    return Acs(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      ubsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['ubsId']),
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
      lastSyncAt: jsonSerialization['lastSyncAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['lastSyncAt']),
    );
  }

  static final t = AcsTable();

  static const db = AcsRepository._();

  @override
  _i1.UuidValue? id;

  String enrollmentId;

  _i1.UuidValue ubsId;

  bool active;

  DateTime? lastSyncAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [Acs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Acs copyWith({
    _i1.UuidValue? id,
    String? enrollmentId,
    _i1.UuidValue? ubsId,
    bool? active,
    DateTime? lastSyncAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Acs',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'ubsId': ubsId.toJson(),
      'active': active,
      if (lastSyncAt != null) 'lastSyncAt': lastSyncAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Acs',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'ubsId': ubsId.toJson(),
      'active': active,
      if (lastSyncAt != null) 'lastSyncAt': lastSyncAt?.toJson(),
    };
  }

  static AcsInclude include() {
    return AcsInclude._();
  }

  static AcsIncludeList includeList({
    _i1.WhereExpressionBuilder<AcsTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsTable>? orderByList,
    AcsInclude? include,
  }) {
    return AcsIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Acs.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(Acs.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsImpl extends Acs {
  _AcsImpl({
    _i1.UuidValue? id,
    required String enrollmentId,
    required _i1.UuidValue ubsId,
    required bool active,
    DateTime? lastSyncAt,
  }) : super._(
         id: id,
         enrollmentId: enrollmentId,
         ubsId: ubsId,
         active: active,
         lastSyncAt: lastSyncAt,
       );

  /// Returns a shallow copy of this [Acs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Acs copyWith({
    Object? id = _Undefined,
    String? enrollmentId,
    _i1.UuidValue? ubsId,
    bool? active,
    Object? lastSyncAt = _Undefined,
  }) {
    return Acs(
      id: id is _i1.UuidValue? ? id : this.id,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      ubsId: ubsId ?? this.ubsId,
      active: active ?? this.active,
      lastSyncAt: lastSyncAt is DateTime? ? lastSyncAt : this.lastSyncAt,
    );
  }
}

class AcsUpdateTable extends _i1.UpdateTable<AcsTable> {
  AcsUpdateTable(super.table);

  _i1.ColumnValue<String, String> enrollmentId(String value) => _i1.ColumnValue(
    table.enrollmentId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> ubsId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.ubsId,
        value,
      );

  _i1.ColumnValue<bool, bool> active(bool value) => _i1.ColumnValue(
    table.active,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> lastSyncAt(DateTime? value) =>
      _i1.ColumnValue(
        table.lastSyncAt,
        value,
      );
}

class AcsTable extends _i1.Table<_i1.UuidValue?> {
  AcsTable({super.tableRelation}) : super(tableName: 'acs') {
    updateTable = AcsUpdateTable(this);
    enrollmentId = _i1.ColumnString(
      'enrollmentId',
      this,
    );
    ubsId = _i1.ColumnUuid(
      'ubsId',
      this,
    );
    active = _i1.ColumnBool(
      'active',
      this,
    );
    lastSyncAt = _i1.ColumnDateTime(
      'lastSyncAt',
      this,
    );
  }

  late final AcsUpdateTable updateTable;

  late final _i1.ColumnString enrollmentId;

  late final _i1.ColumnUuid ubsId;

  late final _i1.ColumnBool active;

  late final _i1.ColumnDateTime lastSyncAt;

  @override
  List<_i1.Column> get columns => [
    id,
    enrollmentId,
    ubsId,
    active,
    lastSyncAt,
  ];
}

class AcsInclude extends _i1.IncludeObject {
  AcsInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Acs.t;
}

class AcsIncludeList extends _i1.IncludeList {
  AcsIncludeList._({
    _i1.WhereExpressionBuilder<AcsTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Acs.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Acs.t;
}

class AcsRepository {
  const AcsRepository._();

  /// Returns a list of [Acs]s matching the given query parameters.
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
  Future<List<Acs>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Acs>(
      where: where?.call(Acs.t),
      orderBy: orderBy?.call(Acs.t),
      orderByList: orderByList?.call(Acs.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Acs] matching the given query parameters.
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
  Future<Acs?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsTable>? where,
    int? offset,
    _i1.OrderByBuilder<AcsTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Acs>(
      where: where?.call(Acs.t),
      orderBy: orderBy?.call(Acs.t),
      orderByList: orderByList?.call(Acs.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Acs] by its [id] or null if no such row exists.
  Future<Acs?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Acs>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Acs]s in the list and returns the inserted rows.
  ///
  /// The returned [Acs]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<Acs>> insert(
    _i1.DatabaseSession session,
    List<Acs> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<Acs>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [Acs] and returns the inserted row.
  ///
  /// The returned [Acs] will have its `id` field set.
  Future<Acs> insertRow(
    _i1.DatabaseSession session,
    Acs row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<Acs>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [Acs]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<Acs>> update(
    _i1.DatabaseSession session,
    List<Acs> rows, {
    _i1.ColumnSelections<AcsTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<Acs>(
      rows,
      columns: columns?.call(Acs.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Acs]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Acs> updateRow(
    _i1.DatabaseSession session,
    Acs row, {
    _i1.ColumnSelections<AcsTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<Acs>(
      row,
      columns: columns?.call(Acs.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Acs] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Acs?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AcsUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<Acs>(
      id,
      columnValues: columnValues(Acs.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Acs]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<Acs>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AcsUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<AcsTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsTable>? orderBy,
    _i1.OrderByListBuilder<AcsTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<Acs>(
      columnValues: columnValues(Acs.t.updateTable),
      where: where(Acs.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Acs.t),
      orderByList: orderByList?.call(Acs.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [Acs]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<Acs>> delete(
    _i1.DatabaseSession session,
    List<Acs> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<Acs>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [Acs].
  Future<Acs> deleteRow(
    _i1.DatabaseSession session,
    Acs row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Acs>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<Acs>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AcsTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<Acs>(
      where: where(Acs.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<Acs>(
      where: where?.call(Acs.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Acs] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AcsTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Acs>(
      where: where(Acs.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
