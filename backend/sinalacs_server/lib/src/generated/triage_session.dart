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
import 'triage_answer.dart' as _i2;
import 'enums/risk_level.dart' as _i3;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i4;

/// Sessão de triagem estruturada. resultRisk é produzido pelo TriageEngine
/// de forma determinística e não é editável (INV-02).
abstract class TriageSession
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  TriageSession._({
    this.id,
    required this.patientId,
    required this.answers,
    required this.resultRisk,
    required this.resultDisplay,
    required this.createdAt,
    required this.deviceId,
  });

  factory TriageSession({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required List<_i2.TriageAnswer> answers,
    required _i3.RiskLevel resultRisk,
    required String resultDisplay,
    required DateTime createdAt,
    required String deviceId,
  }) = _TriageSessionImpl;

  factory TriageSession.fromJson(Map<String, dynamic> jsonSerialization) {
    return TriageSession(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      answers: _i4.Protocol().deserialize<List<_i2.TriageAnswer>>(
        jsonSerialization['answers'],
      ),
      resultRisk: _i3.RiskLevel.fromJson(
        (jsonSerialization['resultRisk'] as String),
      ),
      resultDisplay: jsonSerialization['resultDisplay'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      deviceId: jsonSerialization['deviceId'] as String,
    );
  }

  static final t = TriageSessionTable();

  static const db = TriageSessionRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue patientId;

  List<_i2.TriageAnswer> answers;

  _i3.RiskLevel resultRisk;

  String resultDisplay;

  DateTime createdAt;

  String deviceId;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [TriageSession]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TriageSession copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    List<_i2.TriageAnswer>? answers,
    _i3.RiskLevel? resultRisk,
    String? resultDisplay,
    DateTime? createdAt,
    String? deviceId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TriageSession',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'answers': answers.toJson(valueToJson: (v) => v.toJson()),
      'resultRisk': resultRisk.toJson(),
      'resultDisplay': resultDisplay,
      'createdAt': createdAt.toJson(),
      'deviceId': deviceId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TriageSession',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'answers': answers.toJson(valueToJson: (v) => v.toJsonForProtocol()),
      'resultRisk': resultRisk.toJson(),
      'resultDisplay': resultDisplay,
      'createdAt': createdAt.toJson(),
      'deviceId': deviceId,
    };
  }

  static TriageSessionInclude include() {
    return TriageSessionInclude._();
  }

  static TriageSessionIncludeList includeList({
    _i1.WhereExpressionBuilder<TriageSessionTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TriageSessionTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TriageSessionTable>? orderByList,
    TriageSessionInclude? include,
  }) {
    return TriageSessionIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(TriageSession.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(TriageSession.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TriageSessionImpl extends TriageSession {
  _TriageSessionImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required List<_i2.TriageAnswer> answers,
    required _i3.RiskLevel resultRisk,
    required String resultDisplay,
    required DateTime createdAt,
    required String deviceId,
  }) : super._(
         id: id,
         patientId: patientId,
         answers: answers,
         resultRisk: resultRisk,
         resultDisplay: resultDisplay,
         createdAt: createdAt,
         deviceId: deviceId,
       );

  /// Returns a shallow copy of this [TriageSession]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TriageSession copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    List<_i2.TriageAnswer>? answers,
    _i3.RiskLevel? resultRisk,
    String? resultDisplay,
    DateTime? createdAt,
    String? deviceId,
  }) {
    return TriageSession(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      answers: answers ?? this.answers.map((e0) => e0.copyWith()).toList(),
      resultRisk: resultRisk ?? this.resultRisk,
      resultDisplay: resultDisplay ?? this.resultDisplay,
      createdAt: createdAt ?? this.createdAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}

class TriageSessionUpdateTable extends _i1.UpdateTable<TriageSessionTable> {
  TriageSessionUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> patientId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.patientId,
    value,
  );

  _i1.ColumnValue<List<_i2.TriageAnswer>, List<_i2.TriageAnswer>> answers(
    List<_i2.TriageAnswer> value,
  ) => _i1.ColumnValue(
    table.answers,
    value,
  );

  _i1.ColumnValue<_i3.RiskLevel, _i3.RiskLevel> resultRisk(
    _i3.RiskLevel value,
  ) => _i1.ColumnValue(
    table.resultRisk,
    value,
  );

  _i1.ColumnValue<String, String> resultDisplay(String value) =>
      _i1.ColumnValue(
        table.resultDisplay,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<String, String> deviceId(String value) => _i1.ColumnValue(
    table.deviceId,
    value,
  );
}

class TriageSessionTable extends _i1.Table<_i1.UuidValue?> {
  TriageSessionTable({super.tableRelation})
    : super(tableName: 'triage_sessions') {
    updateTable = TriageSessionUpdateTable(this);
    patientId = _i1.ColumnUuid(
      'patientId',
      this,
    );
    answers = _i1.ColumnSerializable<List<_i2.TriageAnswer>>(
      'answers',
      this,
    );
    resultRisk = _i1.ColumnEnum(
      'resultRisk',
      this,
      _i1.EnumSerialization.byName,
    );
    resultDisplay = _i1.ColumnString(
      'resultDisplay',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    deviceId = _i1.ColumnString(
      'deviceId',
      this,
    );
  }

  late final TriageSessionUpdateTable updateTable;

  late final _i1.ColumnUuid patientId;

  late final _i1.ColumnSerializable<List<_i2.TriageAnswer>> answers;

  late final _i1.ColumnEnum<_i3.RiskLevel> resultRisk;

  late final _i1.ColumnString resultDisplay;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnString deviceId;

  @override
  List<_i1.Column> get columns => [
    id,
    patientId,
    answers,
    resultRisk,
    resultDisplay,
    createdAt,
    deviceId,
  ];
}

class TriageSessionInclude extends _i1.IncludeObject {
  TriageSessionInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => TriageSession.t;
}

class TriageSessionIncludeList extends _i1.IncludeList {
  TriageSessionIncludeList._({
    _i1.WhereExpressionBuilder<TriageSessionTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(TriageSession.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => TriageSession.t;
}

class TriageSessionRepository {
  const TriageSessionRepository._();

  /// Returns a list of [TriageSession]s matching the given query parameters.
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
  Future<List<TriageSession>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TriageSessionTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TriageSessionTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TriageSessionTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<TriageSession>(
      where: where?.call(TriageSession.t),
      orderBy: orderBy?.call(TriageSession.t),
      orderByList: orderByList?.call(TriageSession.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [TriageSession] matching the given query parameters.
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
  Future<TriageSession?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TriageSessionTable>? where,
    int? offset,
    _i1.OrderByBuilder<TriageSessionTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TriageSessionTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<TriageSession>(
      where: where?.call(TriageSession.t),
      orderBy: orderBy?.call(TriageSession.t),
      orderByList: orderByList?.call(TriageSession.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [TriageSession] by its [id] or null if no such row exists.
  Future<TriageSession?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<TriageSession>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [TriageSession]s in the list and returns the inserted rows.
  ///
  /// The returned [TriageSession]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<TriageSession>> insert(
    _i1.DatabaseSession session,
    List<TriageSession> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<TriageSession>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [TriageSession] and returns the inserted row.
  ///
  /// The returned [TriageSession] will have its `id` field set.
  Future<TriageSession> insertRow(
    _i1.DatabaseSession session,
    TriageSession row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<TriageSession>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [TriageSession]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<TriageSession>> update(
    _i1.DatabaseSession session,
    List<TriageSession> rows, {
    _i1.ColumnSelections<TriageSessionTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<TriageSession>(
      rows,
      columns: columns?.call(TriageSession.t),
      transaction: transaction,
    );
  }

  /// Updates a single [TriageSession]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<TriageSession> updateRow(
    _i1.DatabaseSession session,
    TriageSession row, {
    _i1.ColumnSelections<TriageSessionTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<TriageSession>(
      row,
      columns: columns?.call(TriageSession.t),
      transaction: transaction,
    );
  }

  /// Updates a single [TriageSession] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<TriageSession?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<TriageSessionUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<TriageSession>(
      id,
      columnValues: columnValues(TriageSession.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [TriageSession]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<TriageSession>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<TriageSessionUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<TriageSessionTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TriageSessionTable>? orderBy,
    _i1.OrderByListBuilder<TriageSessionTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<TriageSession>(
      columnValues: columnValues(TriageSession.t.updateTable),
      where: where(TriageSession.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(TriageSession.t),
      orderByList: orderByList?.call(TriageSession.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [TriageSession]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<TriageSession>> delete(
    _i1.DatabaseSession session,
    List<TriageSession> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<TriageSession>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [TriageSession].
  Future<TriageSession> deleteRow(
    _i1.DatabaseSession session,
    TriageSession row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<TriageSession>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<TriageSession>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<TriageSessionTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<TriageSession>(
      where: where(TriageSession.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TriageSessionTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<TriageSession>(
      where: where?.call(TriageSession.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [TriageSession] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<TriageSessionTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<TriageSession>(
      where: where(TriageSession.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
