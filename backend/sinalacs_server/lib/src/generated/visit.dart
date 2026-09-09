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
import 'enums/risk_level.dart' as _i2;
import 'enums/sync_status.dart' as _i3;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i4;

/// Visita domiciliar. Registrada offline e sincronizada depois.
abstract class Visit
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  Visit._({
    this.id,
    required this.patientId,
    required this.acsId,
    required this.scheduledAt,
    this.startedAt,
    this.completedAt,
    required this.status,
    required this.riskLevelBefore,
    this.riskLevelAfter,
    required this.notes,
    required this.syncStatus,
    required this.localId,
    this.syncAt,
    required this.version,
  });

  factory Visit({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required _i1.UuidValue acsId,
    required DateTime scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    required String status,
    required _i2.RiskLevel riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    required Map<String, String> notes,
    required _i3.SyncStatus syncStatus,
    required _i1.UuidValue localId,
    DateTime? syncAt,
    required int version,
  }) = _VisitImpl;

  factory Visit.fromJson(Map<String, dynamic> jsonSerialization) {
    return Visit(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      acsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      scheduledAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['scheduledAt'],
      ),
      startedAt: jsonSerialization['startedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['startedAt']),
      completedAt: jsonSerialization['completedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['completedAt'],
            ),
      status: jsonSerialization['status'] as String,
      riskLevelBefore: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevelBefore'] as String),
      ),
      riskLevelAfter: jsonSerialization['riskLevelAfter'] == null
          ? null
          : _i2.RiskLevel.fromJson(
              (jsonSerialization['riskLevelAfter'] as String),
            ),
      notes: _i4.Protocol().deserialize<Map<String, String>>(
        jsonSerialization['notes'],
      ),
      syncStatus: _i3.SyncStatus.fromJson(
        (jsonSerialization['syncStatus'] as String),
      ),
      localId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['localId'],
      ),
      syncAt: jsonSerialization['syncAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['syncAt']),
      version: jsonSerialization['version'] as int,
    );
  }

  static final t = VisitTable();

  static const db = VisitRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue patientId;

  _i1.UuidValue acsId;

  DateTime scheduledAt;

  DateTime? startedAt;

  DateTime? completedAt;

  String status;

  _i2.RiskLevel riskLevelBefore;

  _i2.RiskLevel? riskLevelAfter;

  Map<String, String> notes;

  _i3.SyncStatus syncStatus;

  /// Identificador gerado no dispositivo, usado para deduplicar na sincronização.
  _i1.UuidValue localId;

  DateTime? syncAt;

  int version;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [Visit]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Visit copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    _i1.UuidValue? acsId,
    DateTime? scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? status,
    _i2.RiskLevel? riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    Map<String, String>? notes,
    _i3.SyncStatus? syncStatus,
    _i1.UuidValue? localId,
    DateTime? syncAt,
    int? version,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Visit',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'acsId': acsId.toJson(),
      'scheduledAt': scheduledAt.toJson(),
      if (startedAt != null) 'startedAt': startedAt?.toJson(),
      if (completedAt != null) 'completedAt': completedAt?.toJson(),
      'status': status,
      'riskLevelBefore': riskLevelBefore.toJson(),
      if (riskLevelAfter != null) 'riskLevelAfter': riskLevelAfter?.toJson(),
      'notes': notes.toJson(),
      'syncStatus': syncStatus.toJson(),
      'localId': localId.toJson(),
      if (syncAt != null) 'syncAt': syncAt?.toJson(),
      'version': version,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Visit',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'acsId': acsId.toJson(),
      'scheduledAt': scheduledAt.toJson(),
      if (startedAt != null) 'startedAt': startedAt?.toJson(),
      if (completedAt != null) 'completedAt': completedAt?.toJson(),
      'status': status,
      'riskLevelBefore': riskLevelBefore.toJson(),
      if (riskLevelAfter != null) 'riskLevelAfter': riskLevelAfter?.toJson(),
      'notes': notes.toJson(),
      'syncStatus': syncStatus.toJson(),
      'localId': localId.toJson(),
      if (syncAt != null) 'syncAt': syncAt?.toJson(),
      'version': version,
    };
  }

  static VisitInclude include() {
    return VisitInclude._();
  }

  static VisitIncludeList includeList({
    _i1.WhereExpressionBuilder<VisitTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<VisitTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<VisitTable>? orderByList,
    VisitInclude? include,
  }) {
    return VisitIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Visit.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(Visit.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _VisitImpl extends Visit {
  _VisitImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required _i1.UuidValue acsId,
    required DateTime scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
    required String status,
    required _i2.RiskLevel riskLevelBefore,
    _i2.RiskLevel? riskLevelAfter,
    required Map<String, String> notes,
    required _i3.SyncStatus syncStatus,
    required _i1.UuidValue localId,
    DateTime? syncAt,
    required int version,
  }) : super._(
         id: id,
         patientId: patientId,
         acsId: acsId,
         scheduledAt: scheduledAt,
         startedAt: startedAt,
         completedAt: completedAt,
         status: status,
         riskLevelBefore: riskLevelBefore,
         riskLevelAfter: riskLevelAfter,
         notes: notes,
         syncStatus: syncStatus,
         localId: localId,
         syncAt: syncAt,
         version: version,
       );

  /// Returns a shallow copy of this [Visit]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Visit copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    _i1.UuidValue? acsId,
    DateTime? scheduledAt,
    Object? startedAt = _Undefined,
    Object? completedAt = _Undefined,
    String? status,
    _i2.RiskLevel? riskLevelBefore,
    Object? riskLevelAfter = _Undefined,
    Map<String, String>? notes,
    _i3.SyncStatus? syncStatus,
    _i1.UuidValue? localId,
    Object? syncAt = _Undefined,
    int? version,
  }) {
    return Visit(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      acsId: acsId ?? this.acsId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      startedAt: startedAt is DateTime? ? startedAt : this.startedAt,
      completedAt: completedAt is DateTime? ? completedAt : this.completedAt,
      status: status ?? this.status,
      riskLevelBefore: riskLevelBefore ?? this.riskLevelBefore,
      riskLevelAfter: riskLevelAfter is _i2.RiskLevel?
          ? riskLevelAfter
          : this.riskLevelAfter,
      notes:
          notes ??
          this.notes.map(
            (
              key0,
              value0,
            ) => MapEntry(
              key0,
              value0,
            ),
          ),
      syncStatus: syncStatus ?? this.syncStatus,
      localId: localId ?? this.localId,
      syncAt: syncAt is DateTime? ? syncAt : this.syncAt,
      version: version ?? this.version,
    );
  }
}

class VisitUpdateTable extends _i1.UpdateTable<VisitTable> {
  VisitUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> patientId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.patientId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> acsId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.acsId,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> scheduledAt(DateTime value) =>
      _i1.ColumnValue(
        table.scheduledAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> startedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.startedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> completedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.completedAt,
        value,
      );

  _i1.ColumnValue<String, String> status(String value) => _i1.ColumnValue(
    table.status,
    value,
  );

  _i1.ColumnValue<_i2.RiskLevel, _i2.RiskLevel> riskLevelBefore(
    _i2.RiskLevel value,
  ) => _i1.ColumnValue(
    table.riskLevelBefore,
    value,
  );

  _i1.ColumnValue<_i2.RiskLevel, _i2.RiskLevel> riskLevelAfter(
    _i2.RiskLevel? value,
  ) => _i1.ColumnValue(
    table.riskLevelAfter,
    value,
  );

  _i1.ColumnValue<Map<String, String>, Map<String, String>> notes(
    Map<String, String> value,
  ) => _i1.ColumnValue(
    table.notes,
    value,
  );

  _i1.ColumnValue<_i3.SyncStatus, _i3.SyncStatus> syncStatus(
    _i3.SyncStatus value,
  ) => _i1.ColumnValue(
    table.syncStatus,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> localId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.localId,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> syncAt(DateTime? value) =>
      _i1.ColumnValue(
        table.syncAt,
        value,
      );

  _i1.ColumnValue<int, int> version(int value) => _i1.ColumnValue(
    table.version,
    value,
  );
}

class VisitTable extends _i1.Table<_i1.UuidValue?> {
  VisitTable({super.tableRelation}) : super(tableName: 'visits') {
    updateTable = VisitUpdateTable(this);
    patientId = _i1.ColumnUuid(
      'patientId',
      this,
    );
    acsId = _i1.ColumnUuid(
      'acsId',
      this,
    );
    scheduledAt = _i1.ColumnDateTime(
      'scheduledAt',
      this,
    );
    startedAt = _i1.ColumnDateTime(
      'startedAt',
      this,
    );
    completedAt = _i1.ColumnDateTime(
      'completedAt',
      this,
    );
    status = _i1.ColumnString(
      'status',
      this,
    );
    riskLevelBefore = _i1.ColumnEnum(
      'riskLevelBefore',
      this,
      _i1.EnumSerialization.byName,
    );
    riskLevelAfter = _i1.ColumnEnum(
      'riskLevelAfter',
      this,
      _i1.EnumSerialization.byName,
    );
    notes = _i1.ColumnSerializable<Map<String, String>>(
      'notes',
      this,
    );
    syncStatus = _i1.ColumnEnum(
      'syncStatus',
      this,
      _i1.EnumSerialization.byName,
    );
    localId = _i1.ColumnUuid(
      'localId',
      this,
    );
    syncAt = _i1.ColumnDateTime(
      'syncAt',
      this,
    );
    version = _i1.ColumnInt(
      'version',
      this,
    );
  }

  late final VisitUpdateTable updateTable;

  late final _i1.ColumnUuid patientId;

  late final _i1.ColumnUuid acsId;

  late final _i1.ColumnDateTime scheduledAt;

  late final _i1.ColumnDateTime startedAt;

  late final _i1.ColumnDateTime completedAt;

  late final _i1.ColumnString status;

  late final _i1.ColumnEnum<_i2.RiskLevel> riskLevelBefore;

  late final _i1.ColumnEnum<_i2.RiskLevel> riskLevelAfter;

  late final _i1.ColumnSerializable<Map<String, String>> notes;

  late final _i1.ColumnEnum<_i3.SyncStatus> syncStatus;

  /// Identificador gerado no dispositivo, usado para deduplicar na sincronização.
  late final _i1.ColumnUuid localId;

  late final _i1.ColumnDateTime syncAt;

  late final _i1.ColumnInt version;

  @override
  List<_i1.Column> get columns => [
    id,
    patientId,
    acsId,
    scheduledAt,
    startedAt,
    completedAt,
    status,
    riskLevelBefore,
    riskLevelAfter,
    notes,
    syncStatus,
    localId,
    syncAt,
    version,
  ];
}

class VisitInclude extends _i1.IncludeObject {
  VisitInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Visit.t;
}

class VisitIncludeList extends _i1.IncludeList {
  VisitIncludeList._({
    _i1.WhereExpressionBuilder<VisitTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Visit.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Visit.t;
}

class VisitRepository {
  const VisitRepository._();

  /// Returns a list of [Visit]s matching the given query parameters.
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
  Future<List<Visit>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<VisitTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<VisitTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<VisitTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Visit>(
      where: where?.call(Visit.t),
      orderBy: orderBy?.call(Visit.t),
      orderByList: orderByList?.call(Visit.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Visit] matching the given query parameters.
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
  Future<Visit?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<VisitTable>? where,
    int? offset,
    _i1.OrderByBuilder<VisitTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<VisitTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Visit>(
      where: where?.call(Visit.t),
      orderBy: orderBy?.call(Visit.t),
      orderByList: orderByList?.call(Visit.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Visit] by its [id] or null if no such row exists.
  Future<Visit?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Visit>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Visit]s in the list and returns the inserted rows.
  ///
  /// The returned [Visit]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<Visit>> insert(
    _i1.DatabaseSession session,
    List<Visit> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<Visit>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [Visit] and returns the inserted row.
  ///
  /// The returned [Visit] will have its `id` field set.
  Future<Visit> insertRow(
    _i1.DatabaseSession session,
    Visit row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<Visit>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [Visit]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<Visit>> update(
    _i1.DatabaseSession session,
    List<Visit> rows, {
    _i1.ColumnSelections<VisitTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<Visit>(
      rows,
      columns: columns?.call(Visit.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Visit]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Visit> updateRow(
    _i1.DatabaseSession session,
    Visit row, {
    _i1.ColumnSelections<VisitTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<Visit>(
      row,
      columns: columns?.call(Visit.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Visit] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Visit?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<VisitUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<Visit>(
      id,
      columnValues: columnValues(Visit.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Visit]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<Visit>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<VisitUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<VisitTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<VisitTable>? orderBy,
    _i1.OrderByListBuilder<VisitTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<Visit>(
      columnValues: columnValues(Visit.t.updateTable),
      where: where(Visit.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Visit.t),
      orderByList: orderByList?.call(Visit.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [Visit]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<Visit>> delete(
    _i1.DatabaseSession session,
    List<Visit> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<Visit>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [Visit].
  Future<Visit> deleteRow(
    _i1.DatabaseSession session,
    Visit row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Visit>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<Visit>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<VisitTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<Visit>(
      where: where(Visit.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<VisitTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<Visit>(
      where: where?.call(Visit.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Visit] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<VisitTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Visit>(
      where: where(Visit.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
