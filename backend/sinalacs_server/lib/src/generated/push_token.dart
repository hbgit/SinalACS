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

/// Token de push (FCM/APNs) do aparelho de um paciente que consentiu com
/// `segmentedPush` (RF14, decisão §3.2). Uma linha por token: se o mesmo token
/// aparece para outro titular, a linha muda de dono, nunca duplica.
///
/// O token identifica um aparelho, não uma pessoa, mas junto de `userId` liga
/// aparelho a titular — por isso some na revogação do consentimento.
abstract class PushToken
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  PushToken._({
    this.id,
    required this.userId,
    this.microAreaId,
    required this.token,
    required this.platform,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PushToken({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    _i1.UuidValue? microAreaId,
    required String token,
    required String platform,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _PushTokenImpl;

  factory PushToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return PushToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      microAreaId: jsonSerialization['microAreaId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['microAreaId'],
            ),
      token: jsonSerialization['token'] as String,
      platform: jsonSerialization['platform'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  static final t = PushTokenTable();

  static const db = PushTokenRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  _i1.UuidValue? microAreaId;

  String token;

  String platform;

  DateTime createdAt;

  DateTime updatedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [PushToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PushToken copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    _i1.UuidValue? microAreaId,
    String? token,
    String? platform,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PushToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'token': token,
      'platform': platform,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PushToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'token': token,
      'platform': platform,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  static PushTokenInclude include() {
    return PushTokenInclude._();
  }

  static PushTokenIncludeList includeList({
    _i1.WhereExpressionBuilder<PushTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PushTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PushTokenTable>? orderByList,
    PushTokenInclude? include,
  }) {
    return PushTokenIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PushToken.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(PushToken.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PushTokenImpl extends PushToken {
  _PushTokenImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    _i1.UuidValue? microAreaId,
    required String token,
    required String platform,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         userId: userId,
         microAreaId: microAreaId,
         token: token,
         platform: platform,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [PushToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PushToken copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    Object? microAreaId = _Undefined,
    String? token,
    String? platform,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PushToken(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      microAreaId: microAreaId is _i1.UuidValue?
          ? microAreaId
          : this.microAreaId,
      token: token ?? this.token,
      platform: platform ?? this.platform,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PushTokenUpdateTable extends _i1.UpdateTable<PushTokenTable> {
  PushTokenUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> microAreaId(
    _i1.UuidValue? value,
  ) => _i1.ColumnValue(
    table.microAreaId,
    value,
  );

  _i1.ColumnValue<String, String> token(String value) => _i1.ColumnValue(
    table.token,
    value,
  );

  _i1.ColumnValue<String, String> platform(String value) => _i1.ColumnValue(
    table.platform,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> updatedAt(DateTime value) =>
      _i1.ColumnValue(
        table.updatedAt,
        value,
      );
}

class PushTokenTable extends _i1.Table<_i1.UuidValue?> {
  PushTokenTable({super.tableRelation}) : super(tableName: 'push_tokens') {
    updateTable = PushTokenUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    microAreaId = _i1.ColumnUuid(
      'microAreaId',
      this,
    );
    token = _i1.ColumnString(
      'token',
      this,
    );
    platform = _i1.ColumnString(
      'platform',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    updatedAt = _i1.ColumnDateTime(
      'updatedAt',
      this,
    );
  }

  late final PushTokenUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  late final _i1.ColumnUuid microAreaId;

  late final _i1.ColumnString token;

  late final _i1.ColumnString platform;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnDateTime updatedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    microAreaId,
    token,
    platform,
    createdAt,
    updatedAt,
  ];
}

class PushTokenInclude extends _i1.IncludeObject {
  PushTokenInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => PushToken.t;
}

class PushTokenIncludeList extends _i1.IncludeList {
  PushTokenIncludeList._({
    _i1.WhereExpressionBuilder<PushTokenTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(PushToken.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => PushToken.t;
}

class PushTokenRepository {
  const PushTokenRepository._();

  /// Returns a list of [PushToken]s matching the given query parameters.
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
  Future<List<PushToken>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<PushTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PushTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PushTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<PushToken>(
      where: where?.call(PushToken.t),
      orderBy: orderBy?.call(PushToken.t),
      orderByList: orderByList?.call(PushToken.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [PushToken] matching the given query parameters.
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
  Future<PushToken?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<PushTokenTable>? where,
    int? offset,
    _i1.OrderByBuilder<PushTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PushTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<PushToken>(
      where: where?.call(PushToken.t),
      orderBy: orderBy?.call(PushToken.t),
      orderByList: orderByList?.call(PushToken.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [PushToken] by its [id] or null if no such row exists.
  Future<PushToken?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<PushToken>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [PushToken]s in the list and returns the inserted rows.
  ///
  /// The returned [PushToken]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<PushToken>> insert(
    _i1.DatabaseSession session,
    List<PushToken> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<PushToken>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [PushToken] and returns the inserted row.
  ///
  /// The returned [PushToken] will have its `id` field set.
  Future<PushToken> insertRow(
    _i1.DatabaseSession session,
    PushToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<PushToken>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [PushToken]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<PushToken>> update(
    _i1.DatabaseSession session,
    List<PushToken> rows, {
    _i1.ColumnSelections<PushTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<PushToken>(
      rows,
      columns: columns?.call(PushToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [PushToken]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<PushToken> updateRow(
    _i1.DatabaseSession session,
    PushToken row, {
    _i1.ColumnSelections<PushTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<PushToken>(
      row,
      columns: columns?.call(PushToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [PushToken] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<PushToken?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<PushTokenUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<PushToken>(
      id,
      columnValues: columnValues(PushToken.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [PushToken]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<PushToken>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<PushTokenUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<PushTokenTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PushTokenTable>? orderBy,
    _i1.OrderByListBuilder<PushTokenTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<PushToken>(
      columnValues: columnValues(PushToken.t.updateTable),
      where: where(PushToken.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PushToken.t),
      orderByList: orderByList?.call(PushToken.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [PushToken]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<PushToken>> delete(
    _i1.DatabaseSession session,
    List<PushToken> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<PushToken>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [PushToken].
  Future<PushToken> deleteRow(
    _i1.DatabaseSession session,
    PushToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<PushToken>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<PushToken>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<PushTokenTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<PushToken>(
      where: where(PushToken.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<PushTokenTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<PushToken>(
      where: where?.call(PushToken.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [PushToken] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<PushTokenTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<PushToken>(
      where: where(PushToken.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
