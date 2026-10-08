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

/// Conta de staff do backoffice (coordenador ou administrador).
///
/// Tabela própria, e não uma coluna em `acs`: staff não é ACS, não tem UBS nem
/// sincronização, e misturar os dois faria `acs.enrollmentId` virar um
/// namespace compartilhado. O id é o UUID do usuário (mesma decisão de `Acs`).
/// O papel mora em `users.role` (`coordinator` | `admin`); a credencial, em
/// `user_credentials`.
abstract class StaffAccount
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  StaffAccount._({
    this.id,
    required this.enrollmentId,
    required this.active,
    this.activationCodeHash,
    this.activationCodeExpiresAt,
    this.activationCodeIssuedBy,
    this.activationCodeIssuedAt,
  });

  factory StaffAccount({
    _i1.UuidValue? id,
    required String enrollmentId,
    required bool active,
    String? activationCodeHash,
    DateTime? activationCodeExpiresAt,
    String? activationCodeIssuedBy,
    DateTime? activationCodeIssuedAt,
  }) = _StaffAccountImpl;

  factory StaffAccount.fromJson(Map<String, dynamic> jsonSerialization) {
    return StaffAccount(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
      activationCodeHash: jsonSerialization['activationCodeHash'] as String?,
      activationCodeExpiresAt:
          jsonSerialization['activationCodeExpiresAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['activationCodeExpiresAt'],
            ),
      activationCodeIssuedBy:
          jsonSerialization['activationCodeIssuedBy'] as String?,
      activationCodeIssuedAt:
          jsonSerialization['activationCodeIssuedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['activationCodeIssuedAt'],
            ),
    );
  }

  static final t = StaffAccountTable();

  static const db = StaffAccountRepository._();

  @override
  _i1.UuidValue? id;

  String enrollmentId;

  bool active;

  String? activationCodeHash;

  DateTime? activationCodeExpiresAt;

  String? activationCodeIssuedBy;

  DateTime? activationCodeIssuedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [StaffAccount]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  StaffAccount copyWith({
    _i1.UuidValue? id,
    String? enrollmentId,
    bool? active,
    String? activationCodeHash,
    DateTime? activationCodeExpiresAt,
    String? activationCodeIssuedBy,
    DateTime? activationCodeIssuedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'StaffAccount',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'active': active,
      if (activationCodeHash != null) 'activationCodeHash': activationCodeHash,
      if (activationCodeExpiresAt != null)
        'activationCodeExpiresAt': activationCodeExpiresAt?.toJson(),
      if (activationCodeIssuedBy != null)
        'activationCodeIssuedBy': activationCodeIssuedBy,
      if (activationCodeIssuedAt != null)
        'activationCodeIssuedAt': activationCodeIssuedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'StaffAccount',
      if (id != null) 'id': id?.toJson(),
      'enrollmentId': enrollmentId,
      'active': active,
      if (activationCodeHash != null) 'activationCodeHash': activationCodeHash,
      if (activationCodeExpiresAt != null)
        'activationCodeExpiresAt': activationCodeExpiresAt?.toJson(),
      if (activationCodeIssuedBy != null)
        'activationCodeIssuedBy': activationCodeIssuedBy,
      if (activationCodeIssuedAt != null)
        'activationCodeIssuedAt': activationCodeIssuedAt?.toJson(),
    };
  }

  static StaffAccountInclude include() {
    return StaffAccountInclude._();
  }

  static StaffAccountIncludeList includeList({
    _i1.WhereExpressionBuilder<StaffAccountTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<StaffAccountTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<StaffAccountTable>? orderByList,
    StaffAccountInclude? include,
  }) {
    return StaffAccountIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(StaffAccount.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(StaffAccount.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _StaffAccountImpl extends StaffAccount {
  _StaffAccountImpl({
    _i1.UuidValue? id,
    required String enrollmentId,
    required bool active,
    String? activationCodeHash,
    DateTime? activationCodeExpiresAt,
    String? activationCodeIssuedBy,
    DateTime? activationCodeIssuedAt,
  }) : super._(
         id: id,
         enrollmentId: enrollmentId,
         active: active,
         activationCodeHash: activationCodeHash,
         activationCodeExpiresAt: activationCodeExpiresAt,
         activationCodeIssuedBy: activationCodeIssuedBy,
         activationCodeIssuedAt: activationCodeIssuedAt,
       );

  /// Returns a shallow copy of this [StaffAccount]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  StaffAccount copyWith({
    Object? id = _Undefined,
    String? enrollmentId,
    bool? active,
    Object? activationCodeHash = _Undefined,
    Object? activationCodeExpiresAt = _Undefined,
    Object? activationCodeIssuedBy = _Undefined,
    Object? activationCodeIssuedAt = _Undefined,
  }) {
    return StaffAccount(
      id: id is _i1.UuidValue? ? id : this.id,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      active: active ?? this.active,
      activationCodeHash: activationCodeHash is String?
          ? activationCodeHash
          : this.activationCodeHash,
      activationCodeExpiresAt: activationCodeExpiresAt is DateTime?
          ? activationCodeExpiresAt
          : this.activationCodeExpiresAt,
      activationCodeIssuedBy: activationCodeIssuedBy is String?
          ? activationCodeIssuedBy
          : this.activationCodeIssuedBy,
      activationCodeIssuedAt: activationCodeIssuedAt is DateTime?
          ? activationCodeIssuedAt
          : this.activationCodeIssuedAt,
    );
  }
}

class StaffAccountUpdateTable extends _i1.UpdateTable<StaffAccountTable> {
  StaffAccountUpdateTable(super.table);

  _i1.ColumnValue<String, String> enrollmentId(String value) => _i1.ColumnValue(
    table.enrollmentId,
    value,
  );

  _i1.ColumnValue<bool, bool> active(bool value) => _i1.ColumnValue(
    table.active,
    value,
  );

  _i1.ColumnValue<String, String> activationCodeHash(String? value) =>
      _i1.ColumnValue(
        table.activationCodeHash,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> activationCodeExpiresAt(
    DateTime? value,
  ) => _i1.ColumnValue(
    table.activationCodeExpiresAt,
    value,
  );

  _i1.ColumnValue<String, String> activationCodeIssuedBy(String? value) =>
      _i1.ColumnValue(
        table.activationCodeIssuedBy,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> activationCodeIssuedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.activationCodeIssuedAt,
        value,
      );
}

class StaffAccountTable extends _i1.Table<_i1.UuidValue?> {
  StaffAccountTable({super.tableRelation})
    : super(tableName: 'staff_accounts') {
    updateTable = StaffAccountUpdateTable(this);
    enrollmentId = _i1.ColumnString(
      'enrollmentId',
      this,
    );
    active = _i1.ColumnBool(
      'active',
      this,
    );
    activationCodeHash = _i1.ColumnString(
      'activationCodeHash',
      this,
    );
    activationCodeExpiresAt = _i1.ColumnDateTime(
      'activationCodeExpiresAt',
      this,
    );
    activationCodeIssuedBy = _i1.ColumnString(
      'activationCodeIssuedBy',
      this,
    );
    activationCodeIssuedAt = _i1.ColumnDateTime(
      'activationCodeIssuedAt',
      this,
    );
  }

  late final StaffAccountUpdateTable updateTable;

  late final _i1.ColumnString enrollmentId;

  late final _i1.ColumnBool active;

  late final _i1.ColumnString activationCodeHash;

  late final _i1.ColumnDateTime activationCodeExpiresAt;

  late final _i1.ColumnString activationCodeIssuedBy;

  late final _i1.ColumnDateTime activationCodeIssuedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    enrollmentId,
    active,
    activationCodeHash,
    activationCodeExpiresAt,
    activationCodeIssuedBy,
    activationCodeIssuedAt,
  ];
}

class StaffAccountInclude extends _i1.IncludeObject {
  StaffAccountInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => StaffAccount.t;
}

class StaffAccountIncludeList extends _i1.IncludeList {
  StaffAccountIncludeList._({
    _i1.WhereExpressionBuilder<StaffAccountTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(StaffAccount.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => StaffAccount.t;
}

class StaffAccountRepository {
  const StaffAccountRepository._();

  /// Returns a list of [StaffAccount]s matching the given query parameters.
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
  Future<List<StaffAccount>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<StaffAccountTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<StaffAccountTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<StaffAccountTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<StaffAccount>(
      where: where?.call(StaffAccount.t),
      orderBy: orderBy?.call(StaffAccount.t),
      orderByList: orderByList?.call(StaffAccount.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [StaffAccount] matching the given query parameters.
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
  Future<StaffAccount?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<StaffAccountTable>? where,
    int? offset,
    _i1.OrderByBuilder<StaffAccountTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<StaffAccountTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<StaffAccount>(
      where: where?.call(StaffAccount.t),
      orderBy: orderBy?.call(StaffAccount.t),
      orderByList: orderByList?.call(StaffAccount.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [StaffAccount] by its [id] or null if no such row exists.
  Future<StaffAccount?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<StaffAccount>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [StaffAccount]s in the list and returns the inserted rows.
  ///
  /// The returned [StaffAccount]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<StaffAccount>> insert(
    _i1.DatabaseSession session,
    List<StaffAccount> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<StaffAccount>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [StaffAccount] and returns the inserted row.
  ///
  /// The returned [StaffAccount] will have its `id` field set.
  Future<StaffAccount> insertRow(
    _i1.DatabaseSession session,
    StaffAccount row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<StaffAccount>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [StaffAccount]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<StaffAccount>> update(
    _i1.DatabaseSession session,
    List<StaffAccount> rows, {
    _i1.ColumnSelections<StaffAccountTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<StaffAccount>(
      rows,
      columns: columns?.call(StaffAccount.t),
      transaction: transaction,
    );
  }

  /// Updates a single [StaffAccount]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<StaffAccount> updateRow(
    _i1.DatabaseSession session,
    StaffAccount row, {
    _i1.ColumnSelections<StaffAccountTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<StaffAccount>(
      row,
      columns: columns?.call(StaffAccount.t),
      transaction: transaction,
    );
  }

  /// Updates a single [StaffAccount] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<StaffAccount?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<StaffAccountUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<StaffAccount>(
      id,
      columnValues: columnValues(StaffAccount.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [StaffAccount]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<StaffAccount>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<StaffAccountUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<StaffAccountTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<StaffAccountTable>? orderBy,
    _i1.OrderByListBuilder<StaffAccountTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<StaffAccount>(
      columnValues: columnValues(StaffAccount.t.updateTable),
      where: where(StaffAccount.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(StaffAccount.t),
      orderByList: orderByList?.call(StaffAccount.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [StaffAccount]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<StaffAccount>> delete(
    _i1.DatabaseSession session,
    List<StaffAccount> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<StaffAccount>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [StaffAccount].
  Future<StaffAccount> deleteRow(
    _i1.DatabaseSession session,
    StaffAccount row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<StaffAccount>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<StaffAccount>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<StaffAccountTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<StaffAccount>(
      where: where(StaffAccount.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<StaffAccountTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<StaffAccount>(
      where: where?.call(StaffAccount.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [StaffAccount] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<StaffAccountTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<StaffAccount>(
      where: where(StaffAccount.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
