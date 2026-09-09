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
import 'enums/alert_status.dart' as _i3;

/// Alerta de urgência disparado pelo paciente.
///
/// Campos microAreaId, acknowledgedAt e version vêm da migração v1.2.0 e
/// estavam ausentes da AlertEntity antiga — o modelo segue o SQL, não a
/// entidade Dart que havia divergido.
abstract class Alert
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  Alert._({
    this.id,
    required this.patientId,
    this.acsId,
    this.microAreaId,
    required this.triggeredAt,
    this.receivedAt,
    this.respondedAt,
    this.acknowledgedAt,
    required this.riskLevel,
    required this.locationHash,
    required this.status,
    required this.mqttTopic,
    required this.deviceId,
    required this.retryCount,
    required this.version,
  });

  factory Alert({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    _i1.UuidValue? acsId,
    _i1.UuidValue? microAreaId,
    required DateTime triggeredAt,
    DateTime? receivedAt,
    DateTime? respondedAt,
    DateTime? acknowledgedAt,
    required _i2.RiskLevel riskLevel,
    required String locationHash,
    required _i3.AlertStatus status,
    required String mqttTopic,
    required String deviceId,
    required int retryCount,
    required int version,
  }) = _AlertImpl;

  factory Alert.fromJson(Map<String, dynamic> jsonSerialization) {
    return Alert(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      acsId: jsonSerialization['acsId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['acsId']),
      microAreaId: jsonSerialization['microAreaId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['microAreaId'],
            ),
      triggeredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['triggeredAt'],
      ),
      receivedAt: jsonSerialization['receivedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['receivedAt']),
      respondedAt: jsonSerialization['respondedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['respondedAt'],
            ),
      acknowledgedAt: jsonSerialization['acknowledgedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['acknowledgedAt'],
            ),
      riskLevel: _i2.RiskLevel.fromJson(
        (jsonSerialization['riskLevel'] as String),
      ),
      locationHash: jsonSerialization['locationHash'] as String,
      status: _i3.AlertStatus.fromJson((jsonSerialization['status'] as String)),
      mqttTopic: jsonSerialization['mqttTopic'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      retryCount: jsonSerialization['retryCount'] as int,
      version: jsonSerialization['version'] as int,
    );
  }

  static final t = AlertTable();

  static const db = AlertRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue patientId;

  _i1.UuidValue? acsId;

  _i1.UuidValue? microAreaId;

  DateTime triggeredAt;

  DateTime? receivedAt;

  DateTime? respondedAt;

  DateTime? acknowledgedAt;

  _i2.RiskLevel riskLevel;

  String locationHash;

  _i3.AlertStatus status;

  String mqttTopic;

  String deviceId;

  int retryCount;

  int version;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [Alert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Alert copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    _i1.UuidValue? acsId,
    _i1.UuidValue? microAreaId,
    DateTime? triggeredAt,
    DateTime? receivedAt,
    DateTime? respondedAt,
    DateTime? acknowledgedAt,
    _i2.RiskLevel? riskLevel,
    String? locationHash,
    _i3.AlertStatus? status,
    String? mqttTopic,
    String? deviceId,
    int? retryCount,
    int? version,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Alert',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      if (acsId != null) 'acsId': acsId?.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'triggeredAt': triggeredAt.toJson(),
      if (receivedAt != null) 'receivedAt': receivedAt?.toJson(),
      if (respondedAt != null) 'respondedAt': respondedAt?.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
      'riskLevel': riskLevel.toJson(),
      'locationHash': locationHash,
      'status': status.toJson(),
      'mqttTopic': mqttTopic,
      'deviceId': deviceId,
      'retryCount': retryCount,
      'version': version,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Alert',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      if (acsId != null) 'acsId': acsId?.toJson(),
      if (microAreaId != null) 'microAreaId': microAreaId?.toJson(),
      'triggeredAt': triggeredAt.toJson(),
      if (receivedAt != null) 'receivedAt': receivedAt?.toJson(),
      if (respondedAt != null) 'respondedAt': respondedAt?.toJson(),
      if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt?.toJson(),
      'riskLevel': riskLevel.toJson(),
      'locationHash': locationHash,
      'status': status.toJson(),
      'mqttTopic': mqttTopic,
      'deviceId': deviceId,
      'retryCount': retryCount,
      'version': version,
    };
  }

  static AlertInclude include() {
    return AlertInclude._();
  }

  static AlertIncludeList includeList({
    _i1.WhereExpressionBuilder<AlertTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertTable>? orderByList,
    AlertInclude? include,
  }) {
    return AlertIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Alert.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(Alert.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertImpl extends Alert {
  _AlertImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    _i1.UuidValue? acsId,
    _i1.UuidValue? microAreaId,
    required DateTime triggeredAt,
    DateTime? receivedAt,
    DateTime? respondedAt,
    DateTime? acknowledgedAt,
    required _i2.RiskLevel riskLevel,
    required String locationHash,
    required _i3.AlertStatus status,
    required String mqttTopic,
    required String deviceId,
    required int retryCount,
    required int version,
  }) : super._(
         id: id,
         patientId: patientId,
         acsId: acsId,
         microAreaId: microAreaId,
         triggeredAt: triggeredAt,
         receivedAt: receivedAt,
         respondedAt: respondedAt,
         acknowledgedAt: acknowledgedAt,
         riskLevel: riskLevel,
         locationHash: locationHash,
         status: status,
         mqttTopic: mqttTopic,
         deviceId: deviceId,
         retryCount: retryCount,
         version: version,
       );

  /// Returns a shallow copy of this [Alert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Alert copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    Object? acsId = _Undefined,
    Object? microAreaId = _Undefined,
    DateTime? triggeredAt,
    Object? receivedAt = _Undefined,
    Object? respondedAt = _Undefined,
    Object? acknowledgedAt = _Undefined,
    _i2.RiskLevel? riskLevel,
    String? locationHash,
    _i3.AlertStatus? status,
    String? mqttTopic,
    String? deviceId,
    int? retryCount,
    int? version,
  }) {
    return Alert(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      acsId: acsId is _i1.UuidValue? ? acsId : this.acsId,
      microAreaId: microAreaId is _i1.UuidValue?
          ? microAreaId
          : this.microAreaId,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      receivedAt: receivedAt is DateTime? ? receivedAt : this.receivedAt,
      respondedAt: respondedAt is DateTime? ? respondedAt : this.respondedAt,
      acknowledgedAt: acknowledgedAt is DateTime?
          ? acknowledgedAt
          : this.acknowledgedAt,
      riskLevel: riskLevel ?? this.riskLevel,
      locationHash: locationHash ?? this.locationHash,
      status: status ?? this.status,
      mqttTopic: mqttTopic ?? this.mqttTopic,
      deviceId: deviceId ?? this.deviceId,
      retryCount: retryCount ?? this.retryCount,
      version: version ?? this.version,
    );
  }
}

class AlertUpdateTable extends _i1.UpdateTable<AlertTable> {
  AlertUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> patientId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.patientId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> acsId(_i1.UuidValue? value) =>
      _i1.ColumnValue(
        table.acsId,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> microAreaId(
    _i1.UuidValue? value,
  ) => _i1.ColumnValue(
    table.microAreaId,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> triggeredAt(DateTime value) =>
      _i1.ColumnValue(
        table.triggeredAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> receivedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.receivedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> respondedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.respondedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> acknowledgedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.acknowledgedAt,
        value,
      );

  _i1.ColumnValue<_i2.RiskLevel, _i2.RiskLevel> riskLevel(
    _i2.RiskLevel value,
  ) => _i1.ColumnValue(
    table.riskLevel,
    value,
  );

  _i1.ColumnValue<String, String> locationHash(String value) => _i1.ColumnValue(
    table.locationHash,
    value,
  );

  _i1.ColumnValue<_i3.AlertStatus, _i3.AlertStatus> status(
    _i3.AlertStatus value,
  ) => _i1.ColumnValue(
    table.status,
    value,
  );

  _i1.ColumnValue<String, String> mqttTopic(String value) => _i1.ColumnValue(
    table.mqttTopic,
    value,
  );

  _i1.ColumnValue<String, String> deviceId(String value) => _i1.ColumnValue(
    table.deviceId,
    value,
  );

  _i1.ColumnValue<int, int> retryCount(int value) => _i1.ColumnValue(
    table.retryCount,
    value,
  );

  _i1.ColumnValue<int, int> version(int value) => _i1.ColumnValue(
    table.version,
    value,
  );
}

class AlertTable extends _i1.Table<_i1.UuidValue?> {
  AlertTable({super.tableRelation}) : super(tableName: 'alerts') {
    updateTable = AlertUpdateTable(this);
    patientId = _i1.ColumnUuid(
      'patientId',
      this,
    );
    acsId = _i1.ColumnUuid(
      'acsId',
      this,
    );
    microAreaId = _i1.ColumnUuid(
      'microAreaId',
      this,
    );
    triggeredAt = _i1.ColumnDateTime(
      'triggeredAt',
      this,
    );
    receivedAt = _i1.ColumnDateTime(
      'receivedAt',
      this,
    );
    respondedAt = _i1.ColumnDateTime(
      'respondedAt',
      this,
    );
    acknowledgedAt = _i1.ColumnDateTime(
      'acknowledgedAt',
      this,
    );
    riskLevel = _i1.ColumnEnum(
      'riskLevel',
      this,
      _i1.EnumSerialization.byName,
    );
    locationHash = _i1.ColumnString(
      'locationHash',
      this,
    );
    status = _i1.ColumnEnum(
      'status',
      this,
      _i1.EnumSerialization.byName,
    );
    mqttTopic = _i1.ColumnString(
      'mqttTopic',
      this,
    );
    deviceId = _i1.ColumnString(
      'deviceId',
      this,
    );
    retryCount = _i1.ColumnInt(
      'retryCount',
      this,
    );
    version = _i1.ColumnInt(
      'version',
      this,
    );
  }

  late final AlertUpdateTable updateTable;

  late final _i1.ColumnUuid patientId;

  late final _i1.ColumnUuid acsId;

  late final _i1.ColumnUuid microAreaId;

  late final _i1.ColumnDateTime triggeredAt;

  late final _i1.ColumnDateTime receivedAt;

  late final _i1.ColumnDateTime respondedAt;

  late final _i1.ColumnDateTime acknowledgedAt;

  late final _i1.ColumnEnum<_i2.RiskLevel> riskLevel;

  late final _i1.ColumnString locationHash;

  late final _i1.ColumnEnum<_i3.AlertStatus> status;

  late final _i1.ColumnString mqttTopic;

  late final _i1.ColumnString deviceId;

  late final _i1.ColumnInt retryCount;

  late final _i1.ColumnInt version;

  @override
  List<_i1.Column> get columns => [
    id,
    patientId,
    acsId,
    microAreaId,
    triggeredAt,
    receivedAt,
    respondedAt,
    acknowledgedAt,
    riskLevel,
    locationHash,
    status,
    mqttTopic,
    deviceId,
    retryCount,
    version,
  ];
}

class AlertInclude extends _i1.IncludeObject {
  AlertInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Alert.t;
}

class AlertIncludeList extends _i1.IncludeList {
  AlertIncludeList._({
    _i1.WhereExpressionBuilder<AlertTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Alert.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Alert.t;
}

class AlertRepository {
  const AlertRepository._();

  /// Returns a list of [Alert]s matching the given query parameters.
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
  Future<List<Alert>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Alert>(
      where: where?.call(Alert.t),
      orderBy: orderBy?.call(Alert.t),
      orderByList: orderByList?.call(Alert.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Alert] matching the given query parameters.
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
  Future<Alert?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertTable>? where,
    int? offset,
    _i1.OrderByBuilder<AlertTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Alert>(
      where: where?.call(Alert.t),
      orderBy: orderBy?.call(Alert.t),
      orderByList: orderByList?.call(Alert.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Alert] by its [id] or null if no such row exists.
  Future<Alert?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Alert>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Alert]s in the list and returns the inserted rows.
  ///
  /// The returned [Alert]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<Alert>> insert(
    _i1.DatabaseSession session,
    List<Alert> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<Alert>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [Alert] and returns the inserted row.
  ///
  /// The returned [Alert] will have its `id` field set.
  Future<Alert> insertRow(
    _i1.DatabaseSession session,
    Alert row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<Alert>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [Alert]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<Alert>> update(
    _i1.DatabaseSession session,
    List<Alert> rows, {
    _i1.ColumnSelections<AlertTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<Alert>(
      rows,
      columns: columns?.call(Alert.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Alert]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Alert> updateRow(
    _i1.DatabaseSession session,
    Alert row, {
    _i1.ColumnSelections<AlertTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<Alert>(
      row,
      columns: columns?.call(Alert.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Alert] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Alert?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AlertUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<Alert>(
      id,
      columnValues: columnValues(Alert.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Alert]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<Alert>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AlertUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<AlertTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertTable>? orderBy,
    _i1.OrderByListBuilder<AlertTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<Alert>(
      columnValues: columnValues(Alert.t.updateTable),
      where: where(Alert.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Alert.t),
      orderByList: orderByList?.call(Alert.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [Alert]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<Alert>> delete(
    _i1.DatabaseSession session,
    List<Alert> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<Alert>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [Alert].
  Future<Alert> deleteRow(
    _i1.DatabaseSession session,
    Alert row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Alert>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<Alert>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<Alert>(
      where: where(Alert.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AlertTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<Alert>(
      where: where?.call(Alert.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Alert] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AlertTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Alert>(
      where: where(Alert.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
