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
import 'enums/data_subject_request_type.dart' as _i2;
import 'enums/data_subject_request_status.dart' as _i3;

/// Pedido do titular sobre os próprios dados (LGPD-RF08): exclusão ou
/// correção, com prazo de resposta de 15 dias (spec/lgpd_design.md 596-597).
///
/// `details` é texto livre do titular e pode citar condição de saúde — por
/// isso é cifrado na aplicação (AES-256-GCM), pelo mesmo motivo e com o
/// mesmo `HealthDataCipher` de `visits.notes` (RNF03/INV-04). Num pedido de
/// exclusão guarda o JSON `null` cifrado.
abstract class DataSubjectRequest
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  DataSubjectRequest._({
    this.id,
    required this.userId,
    required this.requestType,
    required this.detailsEncrypted,
    required this.detailsKeyVersion,
    required this.status,
    required this.createdAt,
    required this.dueAt,
  });

  factory DataSubjectRequest({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i2.DataSubjectRequestType requestType,
    required String detailsEncrypted,
    required int detailsKeyVersion,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
  }) = _DataSubjectRequestImpl;

  factory DataSubjectRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return DataSubjectRequest(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      requestType: _i2.DataSubjectRequestType.fromJson(
        (jsonSerialization['requestType'] as String),
      ),
      detailsEncrypted: jsonSerialization['detailsEncrypted'] as String,
      detailsKeyVersion: jsonSerialization['detailsKeyVersion'] as int,
      status: _i3.DataSubjectRequestStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      dueAt: _i1.DateTimeJsonExtension.fromJson(jsonSerialization['dueAt']),
    );
  }

  static final t = DataSubjectRequestTable();

  static const db = DataSubjectRequestRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  _i2.DataSubjectRequestType requestType;

  String detailsEncrypted;

  int detailsKeyVersion;

  _i3.DataSubjectRequestStatus status;

  DateTime createdAt;

  /// Prazo de resposta: `createdAt` + 15 dias.
  DateTime dueAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [DataSubjectRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DataSubjectRequest copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    _i2.DataSubjectRequestType? requestType,
    String? detailsEncrypted,
    int? detailsKeyVersion,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DataSubjectRequest',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'requestType': requestType.toJson(),
      'detailsEncrypted': detailsEncrypted,
      'detailsKeyVersion': detailsKeyVersion,
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DataSubjectRequest',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'requestType': requestType.toJson(),
      'detailsEncrypted': detailsEncrypted,
      'detailsKeyVersion': detailsKeyVersion,
      'status': status.toJson(),
      'createdAt': createdAt.toJson(),
      'dueAt': dueAt.toJson(),
    };
  }

  static DataSubjectRequestInclude include() {
    return DataSubjectRequestInclude._();
  }

  static DataSubjectRequestIncludeList includeList({
    _i1.WhereExpressionBuilder<DataSubjectRequestTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DataSubjectRequestTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DataSubjectRequestTable>? orderByList,
    DataSubjectRequestInclude? include,
  }) {
    return DataSubjectRequestIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DataSubjectRequest.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(DataSubjectRequest.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DataSubjectRequestImpl extends DataSubjectRequest {
  _DataSubjectRequestImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i2.DataSubjectRequestType requestType,
    required String detailsEncrypted,
    required int detailsKeyVersion,
    required _i3.DataSubjectRequestStatus status,
    required DateTime createdAt,
    required DateTime dueAt,
  }) : super._(
         id: id,
         userId: userId,
         requestType: requestType,
         detailsEncrypted: detailsEncrypted,
         detailsKeyVersion: detailsKeyVersion,
         status: status,
         createdAt: createdAt,
         dueAt: dueAt,
       );

  /// Returns a shallow copy of this [DataSubjectRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DataSubjectRequest copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    _i2.DataSubjectRequestType? requestType,
    String? detailsEncrypted,
    int? detailsKeyVersion,
    _i3.DataSubjectRequestStatus? status,
    DateTime? createdAt,
    DateTime? dueAt,
  }) {
    return DataSubjectRequest(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      requestType: requestType ?? this.requestType,
      detailsEncrypted: detailsEncrypted ?? this.detailsEncrypted,
      detailsKeyVersion: detailsKeyVersion ?? this.detailsKeyVersion,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      dueAt: dueAt ?? this.dueAt,
    );
  }
}

class DataSubjectRequestUpdateTable
    extends _i1.UpdateTable<DataSubjectRequestTable> {
  DataSubjectRequestUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<_i2.DataSubjectRequestType, _i2.DataSubjectRequestType>
  requestType(_i2.DataSubjectRequestType value) => _i1.ColumnValue(
    table.requestType,
    value,
  );

  _i1.ColumnValue<String, String> detailsEncrypted(String value) =>
      _i1.ColumnValue(
        table.detailsEncrypted,
        value,
      );

  _i1.ColumnValue<int, int> detailsKeyVersion(int value) => _i1.ColumnValue(
    table.detailsKeyVersion,
    value,
  );

  _i1.ColumnValue<_i3.DataSubjectRequestStatus, _i3.DataSubjectRequestStatus>
  status(_i3.DataSubjectRequestStatus value) => _i1.ColumnValue(
    table.status,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> dueAt(DateTime value) => _i1.ColumnValue(
    table.dueAt,
    value,
  );
}

class DataSubjectRequestTable extends _i1.Table<_i1.UuidValue?> {
  DataSubjectRequestTable({super.tableRelation})
    : super(tableName: 'data_subject_requests') {
    updateTable = DataSubjectRequestUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    requestType = _i1.ColumnEnum(
      'requestType',
      this,
      _i1.EnumSerialization.byName,
    );
    detailsEncrypted = _i1.ColumnString(
      'detailsEncrypted',
      this,
    );
    detailsKeyVersion = _i1.ColumnInt(
      'detailsKeyVersion',
      this,
    );
    status = _i1.ColumnEnum(
      'status',
      this,
      _i1.EnumSerialization.byName,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    dueAt = _i1.ColumnDateTime(
      'dueAt',
      this,
    );
  }

  late final DataSubjectRequestUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  late final _i1.ColumnEnum<_i2.DataSubjectRequestType> requestType;

  late final _i1.ColumnString detailsEncrypted;

  late final _i1.ColumnInt detailsKeyVersion;

  late final _i1.ColumnEnum<_i3.DataSubjectRequestStatus> status;

  late final _i1.ColumnDateTime createdAt;

  /// Prazo de resposta: `createdAt` + 15 dias.
  late final _i1.ColumnDateTime dueAt;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    requestType,
    detailsEncrypted,
    detailsKeyVersion,
    status,
    createdAt,
    dueAt,
  ];
}

class DataSubjectRequestInclude extends _i1.IncludeObject {
  DataSubjectRequestInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => DataSubjectRequest.t;
}

class DataSubjectRequestIncludeList extends _i1.IncludeList {
  DataSubjectRequestIncludeList._({
    _i1.WhereExpressionBuilder<DataSubjectRequestTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(DataSubjectRequest.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => DataSubjectRequest.t;
}

class DataSubjectRequestRepository {
  const DataSubjectRequestRepository._();

  /// Returns a list of [DataSubjectRequest]s matching the given query parameters.
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
  Future<List<DataSubjectRequest>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DataSubjectRequestTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DataSubjectRequestTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DataSubjectRequestTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<DataSubjectRequest>(
      where: where?.call(DataSubjectRequest.t),
      orderBy: orderBy?.call(DataSubjectRequest.t),
      orderByList: orderByList?.call(DataSubjectRequest.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [DataSubjectRequest] matching the given query parameters.
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
  Future<DataSubjectRequest?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DataSubjectRequestTable>? where,
    int? offset,
    _i1.OrderByBuilder<DataSubjectRequestTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DataSubjectRequestTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<DataSubjectRequest>(
      where: where?.call(DataSubjectRequest.t),
      orderBy: orderBy?.call(DataSubjectRequest.t),
      orderByList: orderByList?.call(DataSubjectRequest.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [DataSubjectRequest] by its [id] or null if no such row exists.
  Future<DataSubjectRequest?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<DataSubjectRequest>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [DataSubjectRequest]s in the list and returns the inserted rows.
  ///
  /// The returned [DataSubjectRequest]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<DataSubjectRequest>> insert(
    _i1.DatabaseSession session,
    List<DataSubjectRequest> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<DataSubjectRequest>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [DataSubjectRequest] and returns the inserted row.
  ///
  /// The returned [DataSubjectRequest] will have its `id` field set.
  Future<DataSubjectRequest> insertRow(
    _i1.DatabaseSession session,
    DataSubjectRequest row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<DataSubjectRequest>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [DataSubjectRequest]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<DataSubjectRequest>> update(
    _i1.DatabaseSession session,
    List<DataSubjectRequest> rows, {
    _i1.ColumnSelections<DataSubjectRequestTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<DataSubjectRequest>(
      rows,
      columns: columns?.call(DataSubjectRequest.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DataSubjectRequest]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<DataSubjectRequest> updateRow(
    _i1.DatabaseSession session,
    DataSubjectRequest row, {
    _i1.ColumnSelections<DataSubjectRequestTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<DataSubjectRequest>(
      row,
      columns: columns?.call(DataSubjectRequest.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DataSubjectRequest] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<DataSubjectRequest?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<DataSubjectRequestUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<DataSubjectRequest>(
      id,
      columnValues: columnValues(DataSubjectRequest.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [DataSubjectRequest]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<DataSubjectRequest>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<DataSubjectRequestUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<DataSubjectRequestTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DataSubjectRequestTable>? orderBy,
    _i1.OrderByListBuilder<DataSubjectRequestTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<DataSubjectRequest>(
      columnValues: columnValues(DataSubjectRequest.t.updateTable),
      where: where(DataSubjectRequest.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DataSubjectRequest.t),
      orderByList: orderByList?.call(DataSubjectRequest.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [DataSubjectRequest]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<DataSubjectRequest>> delete(
    _i1.DatabaseSession session,
    List<DataSubjectRequest> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<DataSubjectRequest>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [DataSubjectRequest].
  Future<DataSubjectRequest> deleteRow(
    _i1.DatabaseSession session,
    DataSubjectRequest row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<DataSubjectRequest>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<DataSubjectRequest>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DataSubjectRequestTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<DataSubjectRequest>(
      where: where(DataSubjectRequest.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DataSubjectRequestTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<DataSubjectRequest>(
      where: where?.call(DataSubjectRequest.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [DataSubjectRequest] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DataSubjectRequestTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<DataSubjectRequest>(
      where: where(DataSubjectRequest.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
