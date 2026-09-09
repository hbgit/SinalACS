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

/// Outbox transacional de entrega de alertas.
///
/// A intenção de publicar é gravada na MESMA transação do alerta; a publicação
/// no broker acontece depois do commit. Isso fecha as duas janelas que existiam
/// quando o publish rodava dentro da transação: publicar e falhar o commit
/// entregava um alerta sem linha no banco, deixando o ACK sem o que atualizar.
///
/// Um alerta vermelho nunca pode ser perdido nem entregue sem registro
/// (INV-03), então a entrada só é marcada como publicada depois da publicação.
abstract class AlertOutboxEntry
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AlertOutboxEntry._({
    this.id,
    required this.alertId,
    required this.topic,
    required this.payload,
    required this.createdAt,
    this.publishedAt,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
  });

  factory AlertOutboxEntry({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required String topic,
    required String payload,
    required DateTime createdAt,
    DateTime? publishedAt,
    required int attempts,
    required DateTime nextAttemptAt,
    String? lastError,
  }) = _AlertOutboxEntryImpl;

  factory AlertOutboxEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertOutboxEntry(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      alertId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['alertId'],
      ),
      topic: jsonSerialization['topic'] as String,
      payload: jsonSerialization['payload'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      publishedAt: jsonSerialization['publishedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['publishedAt'],
            ),
      attempts: jsonSerialization['attempts'] as int,
      nextAttemptAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['nextAttemptAt'],
      ),
      lastError: jsonSerialization['lastError'] as String?,
    );
  }

  static final t = AlertOutboxEntryTable();

  static const db = AlertOutboxEntryRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue alertId;

  /// Tópico MQTT de destino, resolvido no momento do enfileiramento.
  String topic;

  /// Envelope já serializado por AlertDelivery.toJson().
  String payload;

  DateTime createdAt;

  /// Nulo enquanto pendente; carimbado após a publicação.
  DateTime? publishedAt;

  int attempts;

  /// Quando a próxima tentativa é elegível. Cresce com backoff exponencial.
  DateTime nextAttemptAt;

  String? lastError;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AlertOutboxEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertOutboxEntry copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? alertId,
    String? topic,
    String? payload,
    DateTime? createdAt,
    DateTime? publishedAt,
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertOutboxEntry',
      if (id != null) 'id': id?.toJson(),
      'alertId': alertId.toJson(),
      'topic': topic,
      'payload': payload,
      'createdAt': createdAt.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt.toJson(),
      if (lastError != null) 'lastError': lastError,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AlertOutboxEntry',
      if (id != null) 'id': id?.toJson(),
      'alertId': alertId.toJson(),
      'topic': topic,
      'payload': payload,
      'createdAt': createdAt.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt.toJson(),
      if (lastError != null) 'lastError': lastError,
    };
  }

  static AlertOutboxEntryInclude include() {
    return AlertOutboxEntryInclude._();
  }

  static AlertOutboxEntryIncludeList includeList({
    _i1.WhereExpressionBuilder<AlertOutboxEntryTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertOutboxEntryTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertOutboxEntryTable>? orderByList,
    AlertOutboxEntryInclude? include,
  }) {
    return AlertOutboxEntryIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertOutboxEntry.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AlertOutboxEntry.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertOutboxEntryImpl extends AlertOutboxEntry {
  _AlertOutboxEntryImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue alertId,
    required String topic,
    required String payload,
    required DateTime createdAt,
    DateTime? publishedAt,
    required int attempts,
    required DateTime nextAttemptAt,
    String? lastError,
  }) : super._(
         id: id,
         alertId: alertId,
         topic: topic,
         payload: payload,
         createdAt: createdAt,
         publishedAt: publishedAt,
         attempts: attempts,
         nextAttemptAt: nextAttemptAt,
         lastError: lastError,
       );

  /// Returns a shallow copy of this [AlertOutboxEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertOutboxEntry copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? alertId,
    String? topic,
    String? payload,
    DateTime? createdAt,
    Object? publishedAt = _Undefined,
    int? attempts,
    DateTime? nextAttemptAt,
    Object? lastError = _Undefined,
  }) {
    return AlertOutboxEntry(
      id: id is _i1.UuidValue? ? id : this.id,
      alertId: alertId ?? this.alertId,
      topic: topic ?? this.topic,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt is DateTime? ? publishedAt : this.publishedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError is String? ? lastError : this.lastError,
    );
  }
}

class AlertOutboxEntryUpdateTable
    extends _i1.UpdateTable<AlertOutboxEntryTable> {
  AlertOutboxEntryUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> alertId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.alertId,
        value,
      );

  _i1.ColumnValue<String, String> topic(String value) => _i1.ColumnValue(
    table.topic,
    value,
  );

  _i1.ColumnValue<String, String> payload(String value) => _i1.ColumnValue(
    table.payload,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> publishedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.publishedAt,
        value,
      );

  _i1.ColumnValue<int, int> attempts(int value) => _i1.ColumnValue(
    table.attempts,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> nextAttemptAt(DateTime value) =>
      _i1.ColumnValue(
        table.nextAttemptAt,
        value,
      );

  _i1.ColumnValue<String, String> lastError(String? value) => _i1.ColumnValue(
    table.lastError,
    value,
  );
}

class AlertOutboxEntryTable extends _i1.Table<_i1.UuidValue?> {
  AlertOutboxEntryTable({super.tableRelation})
    : super(tableName: 'alert_outbox') {
    updateTable = AlertOutboxEntryUpdateTable(this);
    alertId = _i1.ColumnUuid(
      'alertId',
      this,
    );
    topic = _i1.ColumnString(
      'topic',
      this,
    );
    payload = _i1.ColumnString(
      'payload',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    publishedAt = _i1.ColumnDateTime(
      'publishedAt',
      this,
    );
    attempts = _i1.ColumnInt(
      'attempts',
      this,
    );
    nextAttemptAt = _i1.ColumnDateTime(
      'nextAttemptAt',
      this,
    );
    lastError = _i1.ColumnString(
      'lastError',
      this,
    );
  }

  late final AlertOutboxEntryUpdateTable updateTable;

  late final _i1.ColumnUuid alertId;

  /// Tópico MQTT de destino, resolvido no momento do enfileiramento.
  late final _i1.ColumnString topic;

  /// Envelope já serializado por AlertDelivery.toJson().
  late final _i1.ColumnString payload;

  late final _i1.ColumnDateTime createdAt;

  /// Nulo enquanto pendente; carimbado após a publicação.
  late final _i1.ColumnDateTime publishedAt;

  late final _i1.ColumnInt attempts;

  /// Quando a próxima tentativa é elegível. Cresce com backoff exponencial.
  late final _i1.ColumnDateTime nextAttemptAt;

  late final _i1.ColumnString lastError;

  @override
  List<_i1.Column> get columns => [
    id,
    alertId,
    topic,
    payload,
    createdAt,
    publishedAt,
    attempts,
    nextAttemptAt,
    lastError,
  ];
}

class AlertOutboxEntryInclude extends _i1.IncludeObject {
  AlertOutboxEntryInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AlertOutboxEntry.t;
}

class AlertOutboxEntryIncludeList extends _i1.IncludeList {
  AlertOutboxEntryIncludeList._({
    _i1.WhereExpressionBuilder<AlertOutboxEntryTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AlertOutboxEntry.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AlertOutboxEntry.t;
}

class AlertOutboxEntryRepository {
  const AlertOutboxEntryRepository._();

  /// Returns a list of [AlertOutboxEntry]s matching the given query parameters.
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
  Future<List<AlertOutboxEntry>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertOutboxEntryTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertOutboxEntryTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertOutboxEntryTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AlertOutboxEntry>(
      where: where?.call(AlertOutboxEntry.t),
      orderBy: orderBy?.call(AlertOutboxEntry.t),
      orderByList: orderByList?.call(AlertOutboxEntry.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AlertOutboxEntry] matching the given query parameters.
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
  Future<AlertOutboxEntry?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertOutboxEntryTable>? where,
    int? offset,
    _i1.OrderByBuilder<AlertOutboxEntryTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertOutboxEntryTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AlertOutboxEntry>(
      where: where?.call(AlertOutboxEntry.t),
      orderBy: orderBy?.call(AlertOutboxEntry.t),
      orderByList: orderByList?.call(AlertOutboxEntry.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AlertOutboxEntry] by its [id] or null if no such row exists.
  Future<AlertOutboxEntry?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AlertOutboxEntry>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AlertOutboxEntry]s in the list and returns the inserted rows.
  ///
  /// The returned [AlertOutboxEntry]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AlertOutboxEntry>> insert(
    _i1.DatabaseSession session,
    List<AlertOutboxEntry> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AlertOutboxEntry>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AlertOutboxEntry] and returns the inserted row.
  ///
  /// The returned [AlertOutboxEntry] will have its `id` field set.
  Future<AlertOutboxEntry> insertRow(
    _i1.DatabaseSession session,
    AlertOutboxEntry row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AlertOutboxEntry>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AlertOutboxEntry]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AlertOutboxEntry>> update(
    _i1.DatabaseSession session,
    List<AlertOutboxEntry> rows, {
    _i1.ColumnSelections<AlertOutboxEntryTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AlertOutboxEntry>(
      rows,
      columns: columns?.call(AlertOutboxEntry.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertOutboxEntry]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AlertOutboxEntry> updateRow(
    _i1.DatabaseSession session,
    AlertOutboxEntry row, {
    _i1.ColumnSelections<AlertOutboxEntryTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AlertOutboxEntry>(
      row,
      columns: columns?.call(AlertOutboxEntry.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertOutboxEntry] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AlertOutboxEntry?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AlertOutboxEntryUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AlertOutboxEntry>(
      id,
      columnValues: columnValues(AlertOutboxEntry.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AlertOutboxEntry]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AlertOutboxEntry>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AlertOutboxEntryUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<AlertOutboxEntryTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertOutboxEntryTable>? orderBy,
    _i1.OrderByListBuilder<AlertOutboxEntryTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AlertOutboxEntry>(
      columnValues: columnValues(AlertOutboxEntry.t.updateTable),
      where: where(AlertOutboxEntry.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertOutboxEntry.t),
      orderByList: orderByList?.call(AlertOutboxEntry.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AlertOutboxEntry]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AlertOutboxEntry>> delete(
    _i1.DatabaseSession session,
    List<AlertOutboxEntry> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AlertOutboxEntry>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AlertOutboxEntry].
  Future<AlertOutboxEntry> deleteRow(
    _i1.DatabaseSession session,
    AlertOutboxEntry row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AlertOutboxEntry>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AlertOutboxEntry>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertOutboxEntryTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AlertOutboxEntry>(
      where: where(AlertOutboxEntry.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertOutboxEntryTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AlertOutboxEntry>(
      where: where?.call(AlertOutboxEntry.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AlertOutboxEntry] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertOutboxEntryTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AlertOutboxEntry>(
      where: where(AlertOutboxEntry.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
