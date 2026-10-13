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

/// Registro de cada exportação da trilha de auditoria (#45). Append-only:
/// guarda quem exportou, os filtros, o intervalo de `sequence` coberto e o
/// SHA-256 do conteúdo, para que a própria exportação seja auditável.
abstract class AuditExport
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AuditExport._({
    this.id,
    required this.requestedBy,
    required this.requestedAt,
    required this.filtersJson,
    required this.format,
    required this.rowCount,
    this.firstSequence,
    this.lastSequence,
    required this.contentSha256,
    required this.chainState,
  });

  factory AuditExport({
    _i1.UuidValue? id,
    required _i1.UuidValue requestedBy,
    required DateTime requestedAt,
    required String filtersJson,
    required String format,
    required int rowCount,
    int? firstSequence,
    int? lastSequence,
    required String contentSha256,
    required String chainState,
  }) = _AuditExportImpl;

  factory AuditExport.fromJson(Map<String, dynamic> jsonSerialization) {
    return AuditExport(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      requestedBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['requestedBy'],
      ),
      requestedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['requestedAt'],
      ),
      filtersJson: jsonSerialization['filtersJson'] as String,
      format: jsonSerialization['format'] as String,
      rowCount: jsonSerialization['rowCount'] as int,
      firstSequence: jsonSerialization['firstSequence'] as int?,
      lastSequence: jsonSerialization['lastSequence'] as int?,
      contentSha256: jsonSerialization['contentSha256'] as String,
      chainState: jsonSerialization['chainState'] as String,
    );
  }

  static final t = AuditExportTable();

  static const db = AuditExportRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue requestedBy;

  DateTime requestedAt;

  String filtersJson;

  String format;

  int rowCount;

  int? firstSequence;

  int? lastSequence;

  String contentSha256;

  /// Resultado da verificação da cadeia no momento da exportação.
  String chainState;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AuditExport]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AuditExport copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? requestedBy,
    DateTime? requestedAt,
    String? filtersJson,
    String? format,
    int? rowCount,
    int? firstSequence,
    int? lastSequence,
    String? contentSha256,
    String? chainState,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AuditExport',
      if (id != null) 'id': id?.toJson(),
      'requestedBy': requestedBy.toJson(),
      'requestedAt': requestedAt.toJson(),
      'filtersJson': filtersJson,
      'format': format,
      'rowCount': rowCount,
      if (firstSequence != null) 'firstSequence': firstSequence,
      if (lastSequence != null) 'lastSequence': lastSequence,
      'contentSha256': contentSha256,
      'chainState': chainState,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AuditExport',
      if (id != null) 'id': id?.toJson(),
      'requestedBy': requestedBy.toJson(),
      'requestedAt': requestedAt.toJson(),
      'filtersJson': filtersJson,
      'format': format,
      'rowCount': rowCount,
      if (firstSequence != null) 'firstSequence': firstSequence,
      if (lastSequence != null) 'lastSequence': lastSequence,
      'contentSha256': contentSha256,
      'chainState': chainState,
    };
  }

  static AuditExportInclude include() {
    return AuditExportInclude._();
  }

  static AuditExportIncludeList includeList({
    _i1.WhereExpressionBuilder<AuditExportTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AuditExportTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AuditExportTable>? orderByList,
    AuditExportInclude? include,
  }) {
    return AuditExportIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AuditExport.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AuditExport.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AuditExportImpl extends AuditExport {
  _AuditExportImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue requestedBy,
    required DateTime requestedAt,
    required String filtersJson,
    required String format,
    required int rowCount,
    int? firstSequence,
    int? lastSequence,
    required String contentSha256,
    required String chainState,
  }) : super._(
         id: id,
         requestedBy: requestedBy,
         requestedAt: requestedAt,
         filtersJson: filtersJson,
         format: format,
         rowCount: rowCount,
         firstSequence: firstSequence,
         lastSequence: lastSequence,
         contentSha256: contentSha256,
         chainState: chainState,
       );

  /// Returns a shallow copy of this [AuditExport]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AuditExport copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? requestedBy,
    DateTime? requestedAt,
    String? filtersJson,
    String? format,
    int? rowCount,
    Object? firstSequence = _Undefined,
    Object? lastSequence = _Undefined,
    String? contentSha256,
    String? chainState,
  }) {
    return AuditExport(
      id: id is _i1.UuidValue? ? id : this.id,
      requestedBy: requestedBy ?? this.requestedBy,
      requestedAt: requestedAt ?? this.requestedAt,
      filtersJson: filtersJson ?? this.filtersJson,
      format: format ?? this.format,
      rowCount: rowCount ?? this.rowCount,
      firstSequence: firstSequence is int? ? firstSequence : this.firstSequence,
      lastSequence: lastSequence is int? ? lastSequence : this.lastSequence,
      contentSha256: contentSha256 ?? this.contentSha256,
      chainState: chainState ?? this.chainState,
    );
  }
}

class AuditExportUpdateTable extends _i1.UpdateTable<AuditExportTable> {
  AuditExportUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> requestedBy(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.requestedBy,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> requestedAt(DateTime value) =>
      _i1.ColumnValue(
        table.requestedAt,
        value,
      );

  _i1.ColumnValue<String, String> filtersJson(String value) => _i1.ColumnValue(
    table.filtersJson,
    value,
  );

  _i1.ColumnValue<String, String> format(String value) => _i1.ColumnValue(
    table.format,
    value,
  );

  _i1.ColumnValue<int, int> rowCount(int value) => _i1.ColumnValue(
    table.rowCount,
    value,
  );

  _i1.ColumnValue<int, int> firstSequence(int? value) => _i1.ColumnValue(
    table.firstSequence,
    value,
  );

  _i1.ColumnValue<int, int> lastSequence(int? value) => _i1.ColumnValue(
    table.lastSequence,
    value,
  );

  _i1.ColumnValue<String, String> contentSha256(String value) =>
      _i1.ColumnValue(
        table.contentSha256,
        value,
      );

  _i1.ColumnValue<String, String> chainState(String value) => _i1.ColumnValue(
    table.chainState,
    value,
  );
}

class AuditExportTable extends _i1.Table<_i1.UuidValue?> {
  AuditExportTable({super.tableRelation}) : super(tableName: 'audit_exports') {
    updateTable = AuditExportUpdateTable(this);
    requestedBy = _i1.ColumnUuid(
      'requestedBy',
      this,
    );
    requestedAt = _i1.ColumnDateTime(
      'requestedAt',
      this,
    );
    filtersJson = _i1.ColumnString(
      'filtersJson',
      this,
    );
    format = _i1.ColumnString(
      'format',
      this,
    );
    rowCount = _i1.ColumnInt(
      'rowCount',
      this,
    );
    firstSequence = _i1.ColumnInt(
      'firstSequence',
      this,
    );
    lastSequence = _i1.ColumnInt(
      'lastSequence',
      this,
    );
    contentSha256 = _i1.ColumnString(
      'contentSha256',
      this,
    );
    chainState = _i1.ColumnString(
      'chainState',
      this,
    );
  }

  late final AuditExportUpdateTable updateTable;

  late final _i1.ColumnUuid requestedBy;

  late final _i1.ColumnDateTime requestedAt;

  late final _i1.ColumnString filtersJson;

  late final _i1.ColumnString format;

  late final _i1.ColumnInt rowCount;

  late final _i1.ColumnInt firstSequence;

  late final _i1.ColumnInt lastSequence;

  late final _i1.ColumnString contentSha256;

  /// Resultado da verificação da cadeia no momento da exportação.
  late final _i1.ColumnString chainState;

  @override
  List<_i1.Column> get columns => [
    id,
    requestedBy,
    requestedAt,
    filtersJson,
    format,
    rowCount,
    firstSequence,
    lastSequence,
    contentSha256,
    chainState,
  ];
}

class AuditExportInclude extends _i1.IncludeObject {
  AuditExportInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AuditExport.t;
}

class AuditExportIncludeList extends _i1.IncludeList {
  AuditExportIncludeList._({
    _i1.WhereExpressionBuilder<AuditExportTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AuditExport.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AuditExport.t;
}

class AuditExportRepository {
  const AuditExportRepository._();

  /// Returns a list of [AuditExport]s matching the given query parameters.
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
  Future<List<AuditExport>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AuditExportTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AuditExportTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AuditExportTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AuditExport>(
      where: where?.call(AuditExport.t),
      orderBy: orderBy?.call(AuditExport.t),
      orderByList: orderByList?.call(AuditExport.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AuditExport] matching the given query parameters.
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
  Future<AuditExport?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AuditExportTable>? where,
    int? offset,
    _i1.OrderByBuilder<AuditExportTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AuditExportTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AuditExport>(
      where: where?.call(AuditExport.t),
      orderBy: orderBy?.call(AuditExport.t),
      orderByList: orderByList?.call(AuditExport.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AuditExport] by its [id] or null if no such row exists.
  Future<AuditExport?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AuditExport>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AuditExport]s in the list and returns the inserted rows.
  ///
  /// The returned [AuditExport]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AuditExport>> insert(
    _i1.DatabaseSession session,
    List<AuditExport> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AuditExport>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AuditExport] and returns the inserted row.
  ///
  /// The returned [AuditExport] will have its `id` field set.
  Future<AuditExport> insertRow(
    _i1.DatabaseSession session,
    AuditExport row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AuditExport>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AuditExport]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AuditExport>> update(
    _i1.DatabaseSession session,
    List<AuditExport> rows, {
    _i1.ColumnSelections<AuditExportTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AuditExport>(
      rows,
      columns: columns?.call(AuditExport.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AuditExport]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AuditExport> updateRow(
    _i1.DatabaseSession session,
    AuditExport row, {
    _i1.ColumnSelections<AuditExportTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AuditExport>(
      row,
      columns: columns?.call(AuditExport.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AuditExport] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AuditExport?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AuditExportUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AuditExport>(
      id,
      columnValues: columnValues(AuditExport.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AuditExport]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AuditExport>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AuditExportUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<AuditExportTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AuditExportTable>? orderBy,
    _i1.OrderByListBuilder<AuditExportTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AuditExport>(
      columnValues: columnValues(AuditExport.t.updateTable),
      where: where(AuditExport.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AuditExport.t),
      orderByList: orderByList?.call(AuditExport.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AuditExport]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AuditExport>> delete(
    _i1.DatabaseSession session,
    List<AuditExport> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AuditExport>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AuditExport].
  Future<AuditExport> deleteRow(
    _i1.DatabaseSession session,
    AuditExport row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AuditExport>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AuditExport>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AuditExportTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AuditExport>(
      where: where(AuditExport.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AuditExportTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AuditExport>(
      where: where?.call(AuditExport.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AuditExport] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AuditExportTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AuditExport>(
      where: where(AuditExport.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
