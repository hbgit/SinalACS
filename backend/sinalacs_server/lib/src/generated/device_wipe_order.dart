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
import 'enums/device_wipe_reason.dart' as _i2;

/// Pedido de limpeza remota do aparelho de um ACS (#81). Um por aparelho
/// (índice único em `deviceId`): pedir de novo devolve o pedido original.
///
/// O pedido não carrega dado pessoal: só ids, o motivo (conjunto fechado) e os
/// carimbos. `deliveredAt` marca a primeira vez que o aparelho foi mandado
/// limpar; `confirmedAt`, a confirmação do próprio aparelho de que limpou.
abstract class DeviceWipeOrder
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  DeviceWipeOrder._({
    this.id,
    required this.deviceId,
    required this.targetUserId,
    required this.requestedBy,
    required this.reason,
    required this.requestedAt,
    this.deliveredAt,
    this.confirmedAt,
  });

  factory DeviceWipeOrder({
    _i1.UuidValue? id,
    required String deviceId,
    required _i1.UuidValue targetUserId,
    required _i1.UuidValue requestedBy,
    required _i2.DeviceWipeReason reason,
    required DateTime requestedAt,
    DateTime? deliveredAt,
    DateTime? confirmedAt,
  }) = _DeviceWipeOrderImpl;

  factory DeviceWipeOrder.fromJson(Map<String, dynamic> jsonSerialization) {
    return DeviceWipeOrder(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      deviceId: jsonSerialization['deviceId'] as String,
      targetUserId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['targetUserId'],
      ),
      requestedBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['requestedBy'],
      ),
      reason: _i2.DeviceWipeReason.fromJson(
        (jsonSerialization['reason'] as String),
      ),
      requestedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['requestedAt'],
      ),
      deliveredAt: jsonSerialization['deliveredAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['deliveredAt'],
            ),
      confirmedAt: jsonSerialization['confirmedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['confirmedAt'],
            ),
    );
  }

  static final t = DeviceWipeOrderTable();

  static const db = DeviceWipeOrderRepository._();

  @override
  _i1.UuidValue? id;

  /// Instalação alvo (`acs_refresh_tokens.deviceId`).
  String deviceId;

  /// O ACS dono do aparelho no momento do pedido.
  _i1.UuidValue targetUserId;

  /// Quem pediu (coordenador ou administrador).
  _i1.UuidValue requestedBy;

  _i2.DeviceWipeReason reason;

  DateTime requestedAt;

  DateTime? deliveredAt;

  DateTime? confirmedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [DeviceWipeOrder]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceWipeOrder copyWith({
    _i1.UuidValue? id,
    String? deviceId,
    _i1.UuidValue? targetUserId,
    _i1.UuidValue? requestedBy,
    _i2.DeviceWipeReason? reason,
    DateTime? requestedAt,
    DateTime? deliveredAt,
    DateTime? confirmedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceWipeOrder',
      if (id != null) 'id': id?.toJson(),
      'deviceId': deviceId,
      'targetUserId': targetUserId.toJson(),
      'requestedBy': requestedBy.toJson(),
      'reason': reason.toJson(),
      'requestedAt': requestedAt.toJson(),
      if (deliveredAt != null) 'deliveredAt': deliveredAt?.toJson(),
      if (confirmedAt != null) 'confirmedAt': confirmedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceWipeOrder',
      if (id != null) 'id': id?.toJson(),
      'deviceId': deviceId,
      'targetUserId': targetUserId.toJson(),
      'requestedBy': requestedBy.toJson(),
      'reason': reason.toJson(),
      'requestedAt': requestedAt.toJson(),
      if (deliveredAt != null) 'deliveredAt': deliveredAt?.toJson(),
      if (confirmedAt != null) 'confirmedAt': confirmedAt?.toJson(),
    };
  }

  static DeviceWipeOrderInclude include() {
    return DeviceWipeOrderInclude._();
  }

  static DeviceWipeOrderIncludeList includeList({
    _i1.WhereExpressionBuilder<DeviceWipeOrderTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceWipeOrderTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceWipeOrderTable>? orderByList,
    DeviceWipeOrderInclude? include,
  }) {
    return DeviceWipeOrderIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DeviceWipeOrder.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(DeviceWipeOrder.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DeviceWipeOrderImpl extends DeviceWipeOrder {
  _DeviceWipeOrderImpl({
    _i1.UuidValue? id,
    required String deviceId,
    required _i1.UuidValue targetUserId,
    required _i1.UuidValue requestedBy,
    required _i2.DeviceWipeReason reason,
    required DateTime requestedAt,
    DateTime? deliveredAt,
    DateTime? confirmedAt,
  }) : super._(
         id: id,
         deviceId: deviceId,
         targetUserId: targetUserId,
         requestedBy: requestedBy,
         reason: reason,
         requestedAt: requestedAt,
         deliveredAt: deliveredAt,
         confirmedAt: confirmedAt,
       );

  /// Returns a shallow copy of this [DeviceWipeOrder]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceWipeOrder copyWith({
    Object? id = _Undefined,
    String? deviceId,
    _i1.UuidValue? targetUserId,
    _i1.UuidValue? requestedBy,
    _i2.DeviceWipeReason? reason,
    DateTime? requestedAt,
    Object? deliveredAt = _Undefined,
    Object? confirmedAt = _Undefined,
  }) {
    return DeviceWipeOrder(
      id: id is _i1.UuidValue? ? id : this.id,
      deviceId: deviceId ?? this.deviceId,
      targetUserId: targetUserId ?? this.targetUserId,
      requestedBy: requestedBy ?? this.requestedBy,
      reason: reason ?? this.reason,
      requestedAt: requestedAt ?? this.requestedAt,
      deliveredAt: deliveredAt is DateTime? ? deliveredAt : this.deliveredAt,
      confirmedAt: confirmedAt is DateTime? ? confirmedAt : this.confirmedAt,
    );
  }
}

class DeviceWipeOrderUpdateTable extends _i1.UpdateTable<DeviceWipeOrderTable> {
  DeviceWipeOrderUpdateTable(super.table);

  _i1.ColumnValue<String, String> deviceId(String value) => _i1.ColumnValue(
    table.deviceId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> targetUserId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.targetUserId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> requestedBy(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.requestedBy,
    value,
  );

  _i1.ColumnValue<_i2.DeviceWipeReason, _i2.DeviceWipeReason> reason(
    _i2.DeviceWipeReason value,
  ) => _i1.ColumnValue(
    table.reason,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> requestedAt(DateTime value) =>
      _i1.ColumnValue(
        table.requestedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> deliveredAt(DateTime? value) =>
      _i1.ColumnValue(
        table.deliveredAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> confirmedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.confirmedAt,
        value,
      );
}

class DeviceWipeOrderTable extends _i1.Table<_i1.UuidValue?> {
  DeviceWipeOrderTable({super.tableRelation})
    : super(tableName: 'device_wipe_orders') {
    updateTable = DeviceWipeOrderUpdateTable(this);
    deviceId = _i1.ColumnString(
      'deviceId',
      this,
    );
    targetUserId = _i1.ColumnUuid(
      'targetUserId',
      this,
    );
    requestedBy = _i1.ColumnUuid(
      'requestedBy',
      this,
    );
    reason = _i1.ColumnEnum(
      'reason',
      this,
      _i1.EnumSerialization.byName,
    );
    requestedAt = _i1.ColumnDateTime(
      'requestedAt',
      this,
    );
    deliveredAt = _i1.ColumnDateTime(
      'deliveredAt',
      this,
    );
    confirmedAt = _i1.ColumnDateTime(
      'confirmedAt',
      this,
    );
  }

  late final DeviceWipeOrderUpdateTable updateTable;

  /// Instalação alvo (`acs_refresh_tokens.deviceId`).
  late final _i1.ColumnString deviceId;

  /// O ACS dono do aparelho no momento do pedido.
  late final _i1.ColumnUuid targetUserId;

  /// Quem pediu (coordenador ou administrador).
  late final _i1.ColumnUuid requestedBy;

  late final _i1.ColumnEnum<_i2.DeviceWipeReason> reason;

  late final _i1.ColumnDateTime requestedAt;

  late final _i1.ColumnDateTime deliveredAt;

  late final _i1.ColumnDateTime confirmedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    deviceId,
    targetUserId,
    requestedBy,
    reason,
    requestedAt,
    deliveredAt,
    confirmedAt,
  ];
}

class DeviceWipeOrderInclude extends _i1.IncludeObject {
  DeviceWipeOrderInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => DeviceWipeOrder.t;
}

class DeviceWipeOrderIncludeList extends _i1.IncludeList {
  DeviceWipeOrderIncludeList._({
    _i1.WhereExpressionBuilder<DeviceWipeOrderTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(DeviceWipeOrder.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => DeviceWipeOrder.t;
}

class DeviceWipeOrderRepository {
  const DeviceWipeOrderRepository._();

  /// Returns a list of [DeviceWipeOrder]s matching the given query parameters.
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
  Future<List<DeviceWipeOrder>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceWipeOrderTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceWipeOrderTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceWipeOrderTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<DeviceWipeOrder>(
      where: where?.call(DeviceWipeOrder.t),
      orderBy: orderBy?.call(DeviceWipeOrder.t),
      orderByList: orderByList?.call(DeviceWipeOrder.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [DeviceWipeOrder] matching the given query parameters.
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
  Future<DeviceWipeOrder?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceWipeOrderTable>? where,
    int? offset,
    _i1.OrderByBuilder<DeviceWipeOrderTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceWipeOrderTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<DeviceWipeOrder>(
      where: where?.call(DeviceWipeOrder.t),
      orderBy: orderBy?.call(DeviceWipeOrder.t),
      orderByList: orderByList?.call(DeviceWipeOrder.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [DeviceWipeOrder] by its [id] or null if no such row exists.
  Future<DeviceWipeOrder?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<DeviceWipeOrder>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [DeviceWipeOrder]s in the list and returns the inserted rows.
  ///
  /// The returned [DeviceWipeOrder]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<DeviceWipeOrder>> insert(
    _i1.DatabaseSession session,
    List<DeviceWipeOrder> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<DeviceWipeOrder>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [DeviceWipeOrder] and returns the inserted row.
  ///
  /// The returned [DeviceWipeOrder] will have its `id` field set.
  Future<DeviceWipeOrder> insertRow(
    _i1.DatabaseSession session,
    DeviceWipeOrder row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<DeviceWipeOrder>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [DeviceWipeOrder]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<DeviceWipeOrder>> update(
    _i1.DatabaseSession session,
    List<DeviceWipeOrder> rows, {
    _i1.ColumnSelections<DeviceWipeOrderTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<DeviceWipeOrder>(
      rows,
      columns: columns?.call(DeviceWipeOrder.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DeviceWipeOrder]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<DeviceWipeOrder> updateRow(
    _i1.DatabaseSession session,
    DeviceWipeOrder row, {
    _i1.ColumnSelections<DeviceWipeOrderTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<DeviceWipeOrder>(
      row,
      columns: columns?.call(DeviceWipeOrder.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DeviceWipeOrder] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<DeviceWipeOrder?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<DeviceWipeOrderUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<DeviceWipeOrder>(
      id,
      columnValues: columnValues(DeviceWipeOrder.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [DeviceWipeOrder]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<DeviceWipeOrder>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<DeviceWipeOrderUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<DeviceWipeOrderTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceWipeOrderTable>? orderBy,
    _i1.OrderByListBuilder<DeviceWipeOrderTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<DeviceWipeOrder>(
      columnValues: columnValues(DeviceWipeOrder.t.updateTable),
      where: where(DeviceWipeOrder.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DeviceWipeOrder.t),
      orderByList: orderByList?.call(DeviceWipeOrder.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [DeviceWipeOrder]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<DeviceWipeOrder>> delete(
    _i1.DatabaseSession session,
    List<DeviceWipeOrder> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<DeviceWipeOrder>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [DeviceWipeOrder].
  Future<DeviceWipeOrder> deleteRow(
    _i1.DatabaseSession session,
    DeviceWipeOrder row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<DeviceWipeOrder>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<DeviceWipeOrder>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DeviceWipeOrderTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<DeviceWipeOrder>(
      where: where(DeviceWipeOrder.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceWipeOrderTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<DeviceWipeOrder>(
      where: where?.call(DeviceWipeOrder.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [DeviceWipeOrder] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DeviceWipeOrderTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<DeviceWipeOrder>(
      where: where(DeviceWipeOrder.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
