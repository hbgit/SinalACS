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
import 'enums/telemetry_source.dart' as _i2;

/// Evento de telemetria do PRD §1.3 (#83). Só anexa: nunca se atualiza.
/// Sem `relation` para `alerts` nem `users`: o expurgo de um não depende do outro.
abstract class TelemetryEvent
    implements _i1.TableRow<int?>, _i1.ProtocolSerialization {
  TelemetryEvent._({
    this.id,
    required this.eventId,
    required this.eventName,
    int? schemaVersion,
    required this.source,
    required this.occurredAt,
    required this.receivedAt,
    this.clockSkewMs,
    this.actorId,
    this.devicePseudonym,
    this.patientPseudonym,
    this.alertId,
    required this.appVersion,
    required this.payload,
  }) : schemaVersion = schemaVersion ?? 1;

  factory TelemetryEvent({
    int? id,
    required _i1.UuidValue eventId,
    required String eventName,
    int? schemaVersion,
    required _i2.TelemetrySource source,
    required DateTime occurredAt,
    required DateTime receivedAt,
    int? clockSkewMs,
    _i1.UuidValue? actorId,
    String? devicePseudonym,
    String? patientPseudonym,
    _i1.UuidValue? alertId,
    required String appVersion,
    required String payload,
  }) = _TelemetryEventImpl;

  factory TelemetryEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return TelemetryEvent(
      id: jsonSerialization['id'] as int?,
      eventId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['eventId'],
      ),
      eventName: jsonSerialization['eventName'] as String,
      schemaVersion: jsonSerialization['schemaVersion'] as int?,
      source: _i2.TelemetrySource.fromJson(
        (jsonSerialization['source'] as String),
      ),
      occurredAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['occurredAt'],
      ),
      receivedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['receivedAt'],
      ),
      clockSkewMs: jsonSerialization['clockSkewMs'] as int?,
      actorId: jsonSerialization['actorId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['actorId']),
      devicePseudonym: jsonSerialization['devicePseudonym'] as String?,
      patientPseudonym: jsonSerialization['patientPseudonym'] as String?,
      alertId: jsonSerialization['alertId'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['alertId']),
      appVersion: jsonSerialization['appVersion'] as String,
      payload: jsonSerialization['payload'] as String,
    );
  }

  static final t = TelemetryEventTable();

  static const db = TelemetryEventRepository._();

  @override
  int? id;

  /// Identificador do evento, gerado por quem emite. Único: o reenvio do mesmo
  /// lote não duplica linha. Os eventos do backend usam UUID v5 determinístico.
  _i1.UuidValue eventId;

  /// Um de `alert_triggered`, `alert_received_acs`, `sync_attempt`,
  /// `sync_result` ou `visit_registered`.
  String eventName;

  /// Versão do esquema do `payload`. Hoje 1.
  int schemaVersion;

  _i2.TelemetrySource source;

  /// Relógio de quem emitiu (UTC). No app pode estar errado: ver `clockSkewMs`.
  DateTime occurredAt;

  /// Relógio do servidor ao gravar. Base da retenção.
  DateTime receivedAt;

  /// `receivedAt` menos o instante de envio do app. Nulo nos eventos do backend.
  int? clockSkewMs;

  /// ACS autor, vindo do token e nunca do cliente. Dado de profissional.
  _i1.UuidValue? actorId;

  /// HMAC-SHA-256 do id da instalação, domínio `device`. Nunca o id cru.
  String? devicePseudonym;

  /// HMAC-SHA-256 do UUID do paciente, domínio `patient`, calculado no servidor.
  String? patientPseudonym;

  _i1.UuidValue? alertId;

  String appVersion;

  /// JSON em texto, esquema fechado por evento, sem PII (sem UUID do paciente).
  String payload;

  @override
  _i1.Table<int?> get table => t;

  /// Returns a shallow copy of this [TelemetryEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TelemetryEvent copyWith({
    int? id,
    _i1.UuidValue? eventId,
    String? eventName,
    int? schemaVersion,
    _i2.TelemetrySource? source,
    DateTime? occurredAt,
    DateTime? receivedAt,
    int? clockSkewMs,
    _i1.UuidValue? actorId,
    String? devicePseudonym,
    String? patientPseudonym,
    _i1.UuidValue? alertId,
    String? appVersion,
    String? payload,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TelemetryEvent',
      if (id != null) 'id': id,
      'eventId': eventId.toJson(),
      'eventName': eventName,
      'schemaVersion': schemaVersion,
      'source': source.toJson(),
      'occurredAt': occurredAt.toJson(),
      'receivedAt': receivedAt.toJson(),
      if (clockSkewMs != null) 'clockSkewMs': clockSkewMs,
      if (actorId != null) 'actorId': actorId?.toJson(),
      if (devicePseudonym != null) 'devicePseudonym': devicePseudonym,
      if (patientPseudonym != null) 'patientPseudonym': patientPseudonym,
      if (alertId != null) 'alertId': alertId?.toJson(),
      'appVersion': appVersion,
      'payload': payload,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TelemetryEvent',
      if (id != null) 'id': id,
      'eventId': eventId.toJson(),
      'eventName': eventName,
      'schemaVersion': schemaVersion,
      'source': source.toJson(),
      'occurredAt': occurredAt.toJson(),
      'receivedAt': receivedAt.toJson(),
      if (clockSkewMs != null) 'clockSkewMs': clockSkewMs,
      if (actorId != null) 'actorId': actorId?.toJson(),
      if (devicePseudonym != null) 'devicePseudonym': devicePseudonym,
      if (patientPseudonym != null) 'patientPseudonym': patientPseudonym,
      if (alertId != null) 'alertId': alertId?.toJson(),
      'appVersion': appVersion,
      'payload': payload,
    };
  }

  static TelemetryEventInclude include() {
    return TelemetryEventInclude._();
  }

  static TelemetryEventIncludeList includeList({
    _i1.WhereExpressionBuilder<TelemetryEventTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TelemetryEventTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TelemetryEventTable>? orderByList,
    TelemetryEventInclude? include,
  }) {
    return TelemetryEventIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(TelemetryEvent.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(TelemetryEvent.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TelemetryEventImpl extends TelemetryEvent {
  _TelemetryEventImpl({
    int? id,
    required _i1.UuidValue eventId,
    required String eventName,
    int? schemaVersion,
    required _i2.TelemetrySource source,
    required DateTime occurredAt,
    required DateTime receivedAt,
    int? clockSkewMs,
    _i1.UuidValue? actorId,
    String? devicePseudonym,
    String? patientPseudonym,
    _i1.UuidValue? alertId,
    required String appVersion,
    required String payload,
  }) : super._(
         id: id,
         eventId: eventId,
         eventName: eventName,
         schemaVersion: schemaVersion,
         source: source,
         occurredAt: occurredAt,
         receivedAt: receivedAt,
         clockSkewMs: clockSkewMs,
         actorId: actorId,
         devicePseudonym: devicePseudonym,
         patientPseudonym: patientPseudonym,
         alertId: alertId,
         appVersion: appVersion,
         payload: payload,
       );

  /// Returns a shallow copy of this [TelemetryEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TelemetryEvent copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? eventId,
    String? eventName,
    int? schemaVersion,
    _i2.TelemetrySource? source,
    DateTime? occurredAt,
    DateTime? receivedAt,
    Object? clockSkewMs = _Undefined,
    Object? actorId = _Undefined,
    Object? devicePseudonym = _Undefined,
    Object? patientPseudonym = _Undefined,
    Object? alertId = _Undefined,
    String? appVersion,
    String? payload,
  }) {
    return TelemetryEvent(
      id: id is int? ? id : this.id,
      eventId: eventId ?? this.eventId,
      eventName: eventName ?? this.eventName,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      source: source ?? this.source,
      occurredAt: occurredAt ?? this.occurredAt,
      receivedAt: receivedAt ?? this.receivedAt,
      clockSkewMs: clockSkewMs is int? ? clockSkewMs : this.clockSkewMs,
      actorId: actorId is _i1.UuidValue? ? actorId : this.actorId,
      devicePseudonym: devicePseudonym is String?
          ? devicePseudonym
          : this.devicePseudonym,
      patientPseudonym: patientPseudonym is String?
          ? patientPseudonym
          : this.patientPseudonym,
      alertId: alertId is _i1.UuidValue? ? alertId : this.alertId,
      appVersion: appVersion ?? this.appVersion,
      payload: payload ?? this.payload,
    );
  }
}

class TelemetryEventUpdateTable extends _i1.UpdateTable<TelemetryEventTable> {
  TelemetryEventUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> eventId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.eventId,
        value,
      );

  _i1.ColumnValue<String, String> eventName(String value) => _i1.ColumnValue(
    table.eventName,
    value,
  );

  _i1.ColumnValue<int, int> schemaVersion(int value) => _i1.ColumnValue(
    table.schemaVersion,
    value,
  );

  _i1.ColumnValue<_i2.TelemetrySource, _i2.TelemetrySource> source(
    _i2.TelemetrySource value,
  ) => _i1.ColumnValue(
    table.source,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> occurredAt(DateTime value) =>
      _i1.ColumnValue(
        table.occurredAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> receivedAt(DateTime value) =>
      _i1.ColumnValue(
        table.receivedAt,
        value,
      );

  _i1.ColumnValue<int, int> clockSkewMs(int? value) => _i1.ColumnValue(
    table.clockSkewMs,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> actorId(_i1.UuidValue? value) =>
      _i1.ColumnValue(
        table.actorId,
        value,
      );

  _i1.ColumnValue<String, String> devicePseudonym(String? value) =>
      _i1.ColumnValue(
        table.devicePseudonym,
        value,
      );

  _i1.ColumnValue<String, String> patientPseudonym(String? value) =>
      _i1.ColumnValue(
        table.patientPseudonym,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> alertId(_i1.UuidValue? value) =>
      _i1.ColumnValue(
        table.alertId,
        value,
      );

  _i1.ColumnValue<String, String> appVersion(String value) => _i1.ColumnValue(
    table.appVersion,
    value,
  );

  _i1.ColumnValue<String, String> payload(String value) => _i1.ColumnValue(
    table.payload,
    value,
  );
}

class TelemetryEventTable extends _i1.Table<int?> {
  TelemetryEventTable({super.tableRelation})
    : super(tableName: 'telemetry_events') {
    updateTable = TelemetryEventUpdateTable(this);
    eventId = _i1.ColumnUuid(
      'eventId',
      this,
    );
    eventName = _i1.ColumnString(
      'eventName',
      this,
    );
    schemaVersion = _i1.ColumnInt(
      'schemaVersion',
      this,
      hasDefault: true,
    );
    source = _i1.ColumnEnum(
      'source',
      this,
      _i1.EnumSerialization.byName,
    );
    occurredAt = _i1.ColumnDateTime(
      'occurredAt',
      this,
    );
    receivedAt = _i1.ColumnDateTime(
      'receivedAt',
      this,
    );
    clockSkewMs = _i1.ColumnInt(
      'clockSkewMs',
      this,
    );
    actorId = _i1.ColumnUuid(
      'actorId',
      this,
    );
    devicePseudonym = _i1.ColumnString(
      'devicePseudonym',
      this,
    );
    patientPseudonym = _i1.ColumnString(
      'patientPseudonym',
      this,
    );
    alertId = _i1.ColumnUuid(
      'alertId',
      this,
    );
    appVersion = _i1.ColumnString(
      'appVersion',
      this,
    );
    payload = _i1.ColumnString(
      'payload',
      this,
    );
  }

  late final TelemetryEventUpdateTable updateTable;

  /// Identificador do evento, gerado por quem emite. Único: o reenvio do mesmo
  /// lote não duplica linha. Os eventos do backend usam UUID v5 determinístico.
  late final _i1.ColumnUuid eventId;

  /// Um de `alert_triggered`, `alert_received_acs`, `sync_attempt`,
  /// `sync_result` ou `visit_registered`.
  late final _i1.ColumnString eventName;

  /// Versão do esquema do `payload`. Hoje 1.
  late final _i1.ColumnInt schemaVersion;

  late final _i1.ColumnEnum<_i2.TelemetrySource> source;

  /// Relógio de quem emitiu (UTC). No app pode estar errado: ver `clockSkewMs`.
  late final _i1.ColumnDateTime occurredAt;

  /// Relógio do servidor ao gravar. Base da retenção.
  late final _i1.ColumnDateTime receivedAt;

  /// `receivedAt` menos o instante de envio do app. Nulo nos eventos do backend.
  late final _i1.ColumnInt clockSkewMs;

  /// ACS autor, vindo do token e nunca do cliente. Dado de profissional.
  late final _i1.ColumnUuid actorId;

  /// HMAC-SHA-256 do id da instalação, domínio `device`. Nunca o id cru.
  late final _i1.ColumnString devicePseudonym;

  /// HMAC-SHA-256 do UUID do paciente, domínio `patient`, calculado no servidor.
  late final _i1.ColumnString patientPseudonym;

  late final _i1.ColumnUuid alertId;

  late final _i1.ColumnString appVersion;

  /// JSON em texto, esquema fechado por evento, sem PII (sem UUID do paciente).
  late final _i1.ColumnString payload;

  @override
  List<_i1.Column> get columns => [
    id,
    eventId,
    eventName,
    schemaVersion,
    source,
    occurredAt,
    receivedAt,
    clockSkewMs,
    actorId,
    devicePseudonym,
    patientPseudonym,
    alertId,
    appVersion,
    payload,
  ];
}

class TelemetryEventInclude extends _i1.IncludeObject {
  TelemetryEventInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<int?> get table => TelemetryEvent.t;
}

class TelemetryEventIncludeList extends _i1.IncludeList {
  TelemetryEventIncludeList._({
    _i1.WhereExpressionBuilder<TelemetryEventTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(TelemetryEvent.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<int?> get table => TelemetryEvent.t;
}

class TelemetryEventRepository {
  const TelemetryEventRepository._();

  /// Returns a list of [TelemetryEvent]s matching the given query parameters.
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
  Future<List<TelemetryEvent>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TelemetryEventTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TelemetryEventTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TelemetryEventTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<TelemetryEvent>(
      where: where?.call(TelemetryEvent.t),
      orderBy: orderBy?.call(TelemetryEvent.t),
      orderByList: orderByList?.call(TelemetryEvent.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [TelemetryEvent] matching the given query parameters.
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
  Future<TelemetryEvent?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TelemetryEventTable>? where,
    int? offset,
    _i1.OrderByBuilder<TelemetryEventTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TelemetryEventTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<TelemetryEvent>(
      where: where?.call(TelemetryEvent.t),
      orderBy: orderBy?.call(TelemetryEvent.t),
      orderByList: orderByList?.call(TelemetryEvent.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [TelemetryEvent] by its [id] or null if no such row exists.
  Future<TelemetryEvent?> findById(
    _i1.DatabaseSession session,
    int id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<TelemetryEvent>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [TelemetryEvent]s in the list and returns the inserted rows.
  ///
  /// The returned [TelemetryEvent]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<TelemetryEvent>> insert(
    _i1.DatabaseSession session,
    List<TelemetryEvent> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<TelemetryEvent>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [TelemetryEvent] and returns the inserted row.
  ///
  /// The returned [TelemetryEvent] will have its `id` field set.
  Future<TelemetryEvent> insertRow(
    _i1.DatabaseSession session,
    TelemetryEvent row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<TelemetryEvent>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [TelemetryEvent]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<TelemetryEvent>> update(
    _i1.DatabaseSession session,
    List<TelemetryEvent> rows, {
    _i1.ColumnSelections<TelemetryEventTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<TelemetryEvent>(
      rows,
      columns: columns?.call(TelemetryEvent.t),
      transaction: transaction,
    );
  }

  /// Updates a single [TelemetryEvent]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<TelemetryEvent> updateRow(
    _i1.DatabaseSession session,
    TelemetryEvent row, {
    _i1.ColumnSelections<TelemetryEventTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<TelemetryEvent>(
      row,
      columns: columns?.call(TelemetryEvent.t),
      transaction: transaction,
    );
  }

  /// Updates a single [TelemetryEvent] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<TelemetryEvent?> updateById(
    _i1.DatabaseSession session,
    int id, {
    required _i1.ColumnValueListBuilder<TelemetryEventUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<TelemetryEvent>(
      id,
      columnValues: columnValues(TelemetryEvent.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [TelemetryEvent]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<TelemetryEvent>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<TelemetryEventUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<TelemetryEventTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TelemetryEventTable>? orderBy,
    _i1.OrderByListBuilder<TelemetryEventTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<TelemetryEvent>(
      columnValues: columnValues(TelemetryEvent.t.updateTable),
      where: where(TelemetryEvent.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(TelemetryEvent.t),
      orderByList: orderByList?.call(TelemetryEvent.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [TelemetryEvent]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<TelemetryEvent>> delete(
    _i1.DatabaseSession session,
    List<TelemetryEvent> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<TelemetryEvent>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [TelemetryEvent].
  Future<TelemetryEvent> deleteRow(
    _i1.DatabaseSession session,
    TelemetryEvent row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<TelemetryEvent>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<TelemetryEvent>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<TelemetryEventTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<TelemetryEvent>(
      where: where(TelemetryEvent.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TelemetryEventTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<TelemetryEvent>(
      where: where?.call(TelemetryEvent.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [TelemetryEvent] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<TelemetryEventTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<TelemetryEvent>(
      where: where(TelemetryEvent.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
