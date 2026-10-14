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

/// Ponto de verificação da cadeia de `audit_logs` (#45): `entryHash` na
/// posição `sequence`, assinado, para detectar truncamento do final da cadeia.
abstract class AuditChainCheckpoint
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AuditChainCheckpoint._({
    this.id,
    required this.sequence,
    required this.entryHash,
    required this.signature,
    required this.createdAt,
  });

  factory AuditChainCheckpoint({
    _i1.UuidValue? id,
    required int sequence,
    required String entryHash,
    required String signature,
    required DateTime createdAt,
  }) = _AuditChainCheckpointImpl;

  factory AuditChainCheckpoint.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AuditChainCheckpoint(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      sequence: jsonSerialization['sequence'] as int,
      entryHash: jsonSerialization['entryHash'] as String,
      signature: jsonSerialization['signature'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = AuditChainCheckpointTable();

  static const db = AuditChainCheckpointRepository._();

  @override
  _i1.UuidValue? id;

  int sequence;

  String entryHash;

  String signature;

  DateTime createdAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AuditChainCheckpoint]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AuditChainCheckpoint copyWith({
    _i1.UuidValue? id,
    int? sequence,
    String? entryHash,
    String? signature,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AuditChainCheckpoint',
      if (id != null) 'id': id?.toJson(),
      'sequence': sequence,
      'entryHash': entryHash,
      'signature': signature,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AuditChainCheckpoint',
      if (id != null) 'id': id?.toJson(),
      'sequence': sequence,
      'entryHash': entryHash,
      'signature': signature,
      'createdAt': createdAt.toJson(),
    };
  }

  static AuditChainCheckpointInclude include() {
    return AuditChainCheckpointInclude._();
  }

  static AuditChainCheckpointIncludeList includeList({
    _i1.WhereExpressionBuilder<AuditChainCheckpointTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AuditChainCheckpointTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AuditChainCheckpointTable>? orderByList,
    AuditChainCheckpointInclude? include,
  }) {
    return AuditChainCheckpointIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AuditChainCheckpoint.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AuditChainCheckpoint.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AuditChainCheckpointImpl extends AuditChainCheckpoint {
  _AuditChainCheckpointImpl({
    _i1.UuidValue? id,
    required int sequence,
    required String entryHash,
    required String signature,
    required DateTime createdAt,
  }) : super._(
         id: id,
         sequence: sequence,
         entryHash: entryHash,
         signature: signature,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [AuditChainCheckpoint]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AuditChainCheckpoint copyWith({
    Object? id = _Undefined,
    int? sequence,
    String? entryHash,
    String? signature,
    DateTime? createdAt,
  }) {
    return AuditChainCheckpoint(
      id: id is _i1.UuidValue? ? id : this.id,
      sequence: sequence ?? this.sequence,
      entryHash: entryHash ?? this.entryHash,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AuditChainCheckpointUpdateTable
    extends _i1.UpdateTable<AuditChainCheckpointTable> {
  AuditChainCheckpointUpdateTable(super.table);

  _i1.ColumnValue<int, int> sequence(int value) => _i1.ColumnValue(
    table.sequence,
    value,
  );

  _i1.ColumnValue<String, String> entryHash(String value) => _i1.ColumnValue(
    table.entryHash,
    value,
  );

  _i1.ColumnValue<String, String> signature(String value) => _i1.ColumnValue(
    table.signature,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );
}

class AuditChainCheckpointTable extends _i1.Table<_i1.UuidValue?> {
  AuditChainCheckpointTable({super.tableRelation})
    : super(tableName: 'audit_chain_checkpoints') {
    updateTable = AuditChainCheckpointUpdateTable(this);
    sequence = _i1.ColumnInt(
      'sequence',
      this,
    );
    entryHash = _i1.ColumnString(
      'entryHash',
      this,
    );
    signature = _i1.ColumnString(
      'signature',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final AuditChainCheckpointUpdateTable updateTable;

  late final _i1.ColumnInt sequence;

  late final _i1.ColumnString entryHash;

  late final _i1.ColumnString signature;

  late final _i1.ColumnDateTime createdAt;

  @override
  List<_i1.Column> get columns => [
    id,
    sequence,
    entryHash,
    signature,
    createdAt,
  ];
}

class AuditChainCheckpointInclude extends _i1.IncludeObject {
  AuditChainCheckpointInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AuditChainCheckpoint.t;
}

class AuditChainCheckpointIncludeList extends _i1.IncludeList {
  AuditChainCheckpointIncludeList._({
    _i1.WhereExpressionBuilder<AuditChainCheckpointTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AuditChainCheckpoint.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AuditChainCheckpoint.t;
}

class AuditChainCheckpointRepository {
  const AuditChainCheckpointRepository._();

  /// Returns a list of [AuditChainCheckpoint]s matching the given query parameters.
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
  Future<List<AuditChainCheckpoint>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AuditChainCheckpointTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AuditChainCheckpointTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AuditChainCheckpointTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AuditChainCheckpoint>(
      where: where?.call(AuditChainCheckpoint.t),
      orderBy: orderBy?.call(AuditChainCheckpoint.t),
      orderByList: orderByList?.call(AuditChainCheckpoint.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AuditChainCheckpoint] matching the given query parameters.
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
  Future<AuditChainCheckpoint?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AuditChainCheckpointTable>? where,
    int? offset,
    _i1.OrderByBuilder<AuditChainCheckpointTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AuditChainCheckpointTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AuditChainCheckpoint>(
      where: where?.call(AuditChainCheckpoint.t),
      orderBy: orderBy?.call(AuditChainCheckpoint.t),
      orderByList: orderByList?.call(AuditChainCheckpoint.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AuditChainCheckpoint] by its [id] or null if no such row exists.
  Future<AuditChainCheckpoint?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AuditChainCheckpoint>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AuditChainCheckpoint]s in the list and returns the inserted rows.
  ///
  /// The returned [AuditChainCheckpoint]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AuditChainCheckpoint>> insert(
    _i1.DatabaseSession session,
    List<AuditChainCheckpoint> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AuditChainCheckpoint>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AuditChainCheckpoint] and returns the inserted row.
  ///
  /// The returned [AuditChainCheckpoint] will have its `id` field set.
  Future<AuditChainCheckpoint> insertRow(
    _i1.DatabaseSession session,
    AuditChainCheckpoint row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AuditChainCheckpoint>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AuditChainCheckpoint]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AuditChainCheckpoint>> update(
    _i1.DatabaseSession session,
    List<AuditChainCheckpoint> rows, {
    _i1.ColumnSelections<AuditChainCheckpointTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AuditChainCheckpoint>(
      rows,
      columns: columns?.call(AuditChainCheckpoint.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AuditChainCheckpoint]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AuditChainCheckpoint> updateRow(
    _i1.DatabaseSession session,
    AuditChainCheckpoint row, {
    _i1.ColumnSelections<AuditChainCheckpointTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AuditChainCheckpoint>(
      row,
      columns: columns?.call(AuditChainCheckpoint.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AuditChainCheckpoint] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AuditChainCheckpoint?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AuditChainCheckpointUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AuditChainCheckpoint>(
      id,
      columnValues: columnValues(AuditChainCheckpoint.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AuditChainCheckpoint]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AuditChainCheckpoint>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AuditChainCheckpointUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<AuditChainCheckpointTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AuditChainCheckpointTable>? orderBy,
    _i1.OrderByListBuilder<AuditChainCheckpointTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AuditChainCheckpoint>(
      columnValues: columnValues(AuditChainCheckpoint.t.updateTable),
      where: where(AuditChainCheckpoint.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AuditChainCheckpoint.t),
      orderByList: orderByList?.call(AuditChainCheckpoint.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AuditChainCheckpoint]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AuditChainCheckpoint>> delete(
    _i1.DatabaseSession session,
    List<AuditChainCheckpoint> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AuditChainCheckpoint>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AuditChainCheckpoint].
  Future<AuditChainCheckpoint> deleteRow(
    _i1.DatabaseSession session,
    AuditChainCheckpoint row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AuditChainCheckpoint>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AuditChainCheckpoint>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AuditChainCheckpointTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AuditChainCheckpoint>(
      where: where(AuditChainCheckpoint.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AuditChainCheckpointTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AuditChainCheckpoint>(
      where: where?.call(AuditChainCheckpoint.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AuditChainCheckpoint] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AuditChainCheckpointTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AuditChainCheckpoint>(
      where: where(AuditChainCheckpoint.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
