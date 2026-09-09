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

/// Deduplicação durável de alertas por chave de idempotência.
///
/// Antes a deduplicação era um Map em memória: sumia no restart e não valia
/// entre instâncias, de modo que um reenvio após queda gerava alerta duplicado.
/// Persistir a chave torna a garantia durável e válida em qualquer réplica.
///
/// A linha é gravada na mesma transação do alerta: se a publicação falhar,
/// ambas desaparecem e o cliente pode retentar de verdade.
abstract class AlertIdempotencyKey
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AlertIdempotencyKey._({
    this.id,
    required this.key,
    required this.alertId,
    required this.locationHash,
    required this.createdAt,
  });

  factory AlertIdempotencyKey({
    _i1.UuidValue? id,
    required String key,
    required _i1.UuidValue alertId,
    required String locationHash,
    required DateTime createdAt,
  }) = _AlertIdempotencyKeyImpl;

  factory AlertIdempotencyKey.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertIdempotencyKey(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      key: jsonSerialization['key'] as String,
      alertId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['alertId'],
      ),
      locationHash: jsonSerialization['locationHash'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = AlertIdempotencyKeyTable();

  static const db = AlertIdempotencyKeyRepository._();

  @override
  _i1.UuidValue? id;

  /// Chave fornecida pelo cliente.
  String key;

  /// Alerta que esta chave produziu.
  _i1.UuidValue alertId;

  /// Guardado para rejeitar reuso da mesma chave com outra localização.
  String locationHash;

  DateTime createdAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AlertIdempotencyKey]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertIdempotencyKey copyWith({
    _i1.UuidValue? id,
    String? key,
    _i1.UuidValue? alertId,
    String? locationHash,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertIdempotencyKey',
      if (id != null) 'id': id?.toJson(),
      'key': key,
      'alertId': alertId.toJson(),
      'locationHash': locationHash,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AlertIdempotencyKey',
      if (id != null) 'id': id?.toJson(),
      'key': key,
      'alertId': alertId.toJson(),
      'locationHash': locationHash,
      'createdAt': createdAt.toJson(),
    };
  }

  static AlertIdempotencyKeyInclude include() {
    return AlertIdempotencyKeyInclude._();
  }

  static AlertIdempotencyKeyIncludeList includeList({
    _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertIdempotencyKeyTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertIdempotencyKeyTable>? orderByList,
    AlertIdempotencyKeyInclude? include,
  }) {
    return AlertIdempotencyKeyIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertIdempotencyKey.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AlertIdempotencyKey.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertIdempotencyKeyImpl extends AlertIdempotencyKey {
  _AlertIdempotencyKeyImpl({
    _i1.UuidValue? id,
    required String key,
    required _i1.UuidValue alertId,
    required String locationHash,
    required DateTime createdAt,
  }) : super._(
         id: id,
         key: key,
         alertId: alertId,
         locationHash: locationHash,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [AlertIdempotencyKey]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertIdempotencyKey copyWith({
    Object? id = _Undefined,
    String? key,
    _i1.UuidValue? alertId,
    String? locationHash,
    DateTime? createdAt,
  }) {
    return AlertIdempotencyKey(
      id: id is _i1.UuidValue? ? id : this.id,
      key: key ?? this.key,
      alertId: alertId ?? this.alertId,
      locationHash: locationHash ?? this.locationHash,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AlertIdempotencyKeyUpdateTable
    extends _i1.UpdateTable<AlertIdempotencyKeyTable> {
  AlertIdempotencyKeyUpdateTable(super.table);

  _i1.ColumnValue<String, String> key(String value) => _i1.ColumnValue(
    table.key,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> alertId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.alertId,
        value,
      );

  _i1.ColumnValue<String, String> locationHash(String value) => _i1.ColumnValue(
    table.locationHash,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );
}

class AlertIdempotencyKeyTable extends _i1.Table<_i1.UuidValue?> {
  AlertIdempotencyKeyTable({super.tableRelation})
    : super(tableName: 'alert_idempotency_keys') {
    updateTable = AlertIdempotencyKeyUpdateTable(this);
    key = _i1.ColumnString(
      'key',
      this,
    );
    alertId = _i1.ColumnUuid(
      'alertId',
      this,
    );
    locationHash = _i1.ColumnString(
      'locationHash',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final AlertIdempotencyKeyUpdateTable updateTable;

  /// Chave fornecida pelo cliente.
  late final _i1.ColumnString key;

  /// Alerta que esta chave produziu.
  late final _i1.ColumnUuid alertId;

  /// Guardado para rejeitar reuso da mesma chave com outra localização.
  late final _i1.ColumnString locationHash;

  late final _i1.ColumnDateTime createdAt;

  @override
  List<_i1.Column> get columns => [
    id,
    key,
    alertId,
    locationHash,
    createdAt,
  ];
}

class AlertIdempotencyKeyInclude extends _i1.IncludeObject {
  AlertIdempotencyKeyInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AlertIdempotencyKey.t;
}

class AlertIdempotencyKeyIncludeList extends _i1.IncludeList {
  AlertIdempotencyKeyIncludeList._({
    _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AlertIdempotencyKey.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AlertIdempotencyKey.t;
}

class AlertIdempotencyKeyRepository {
  const AlertIdempotencyKeyRepository._();

  /// Returns a list of [AlertIdempotencyKey]s matching the given query parameters.
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
  Future<List<AlertIdempotencyKey>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertIdempotencyKeyTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertIdempotencyKeyTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AlertIdempotencyKey>(
      where: where?.call(AlertIdempotencyKey.t),
      orderBy: orderBy?.call(AlertIdempotencyKey.t),
      orderByList: orderByList?.call(AlertIdempotencyKey.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AlertIdempotencyKey] matching the given query parameters.
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
  Future<AlertIdempotencyKey?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable>? where,
    int? offset,
    _i1.OrderByBuilder<AlertIdempotencyKeyTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertIdempotencyKeyTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AlertIdempotencyKey>(
      where: where?.call(AlertIdempotencyKey.t),
      orderBy: orderBy?.call(AlertIdempotencyKey.t),
      orderByList: orderByList?.call(AlertIdempotencyKey.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AlertIdempotencyKey] by its [id] or null if no such row exists.
  Future<AlertIdempotencyKey?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AlertIdempotencyKey>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AlertIdempotencyKey]s in the list and returns the inserted rows.
  ///
  /// The returned [AlertIdempotencyKey]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AlertIdempotencyKey>> insert(
    _i1.DatabaseSession session,
    List<AlertIdempotencyKey> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AlertIdempotencyKey>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AlertIdempotencyKey] and returns the inserted row.
  ///
  /// The returned [AlertIdempotencyKey] will have its `id` field set.
  Future<AlertIdempotencyKey> insertRow(
    _i1.DatabaseSession session,
    AlertIdempotencyKey row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AlertIdempotencyKey>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AlertIdempotencyKey]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AlertIdempotencyKey>> update(
    _i1.DatabaseSession session,
    List<AlertIdempotencyKey> rows, {
    _i1.ColumnSelections<AlertIdempotencyKeyTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AlertIdempotencyKey>(
      rows,
      columns: columns?.call(AlertIdempotencyKey.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertIdempotencyKey]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AlertIdempotencyKey> updateRow(
    _i1.DatabaseSession session,
    AlertIdempotencyKey row, {
    _i1.ColumnSelections<AlertIdempotencyKeyTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AlertIdempotencyKey>(
      row,
      columns: columns?.call(AlertIdempotencyKey.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertIdempotencyKey] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AlertIdempotencyKey?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AlertIdempotencyKeyUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AlertIdempotencyKey>(
      id,
      columnValues: columnValues(AlertIdempotencyKey.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AlertIdempotencyKey]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AlertIdempotencyKey>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AlertIdempotencyKeyUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertIdempotencyKeyTable>? orderBy,
    _i1.OrderByListBuilder<AlertIdempotencyKeyTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AlertIdempotencyKey>(
      columnValues: columnValues(AlertIdempotencyKey.t.updateTable),
      where: where(AlertIdempotencyKey.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertIdempotencyKey.t),
      orderByList: orderByList?.call(AlertIdempotencyKey.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AlertIdempotencyKey]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AlertIdempotencyKey>> delete(
    _i1.DatabaseSession session,
    List<AlertIdempotencyKey> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AlertIdempotencyKey>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AlertIdempotencyKey].
  Future<AlertIdempotencyKey> deleteRow(
    _i1.DatabaseSession session,
    AlertIdempotencyKey row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AlertIdempotencyKey>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AlertIdempotencyKey>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AlertIdempotencyKey>(
      where: where(AlertIdempotencyKey.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AlertIdempotencyKey>(
      where: where?.call(AlertIdempotencyKey.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AlertIdempotencyKey] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertIdempotencyKeyTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AlertIdempotencyKey>(
      where: where(AlertIdempotencyKey.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
