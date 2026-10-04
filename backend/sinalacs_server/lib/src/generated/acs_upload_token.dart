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

/// Token de envio diferido do ACS (D7 do plano 2026-10-03). Deixa o aparelho
/// subir as visitas pendentes de um ACS que já saiu — com a autoria DELE —
/// sem sessão e sem nenhum outro poder: o único uso é `visits.syncDeferred`
/// (e `visits.revokeUploadToken`). Um vigente por (usuário, aparelho): a
/// emissão revoga o anterior. Validade de 7 dias, sem rotação.
///
/// **Nunca** o token: só o SHA-256 dele em hex. O token é 256 bits aleatórios,
/// então um hash simples basta (não há senha humana para adivinhar).
abstract class AcsUploadToken
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AcsUploadToken._({
    this.id,
    required this.userId,
    required this.tokenHash,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
  });

  factory AcsUploadToken({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime expiresAt,
    DateTime? revokedAt,
  }) = _AcsUploadTokenImpl;

  factory AcsUploadToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return AcsUploadToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      tokenHash: jsonSerialization['tokenHash'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      issuedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['issuedAt'],
      ),
      expiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
    );
  }

  static final t = AcsUploadTokenTable();

  static const db = AcsUploadTokenRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  String tokenHash;

  /// Instalação que recebeu o token. Token apresentado por outro aparelho é
  /// recusado e revogado.
  String deviceId;

  DateTime issuedAt;

  /// Teto fixo (`issuedAt` + 7 dias); o uso não o estende.
  DateTime expiresAt;

  /// `null` = vigente. Preenchido na revogação (pedido do app, novo login no
  /// mesmo aparelho, aparelho divergente ou conta inativa/sem microárea).
  DateTime? revokedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AcsUploadToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AcsUploadToken copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? expiresAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AcsUploadToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'tokenHash': tokenHash,
      'deviceId': deviceId,
      'issuedAt': issuedAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AcsUploadToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'tokenHash': tokenHash,
      'deviceId': deviceId,
      'issuedAt': issuedAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  static AcsUploadTokenInclude include() {
    return AcsUploadTokenInclude._();
  }

  static AcsUploadTokenIncludeList includeList({
    _i1.WhereExpressionBuilder<AcsUploadTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsUploadTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsUploadTokenTable>? orderByList,
    AcsUploadTokenInclude? include,
  }) {
    return AcsUploadTokenIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AcsUploadToken.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AcsUploadToken.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsUploadTokenImpl extends AcsUploadToken {
  _AcsUploadTokenImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime expiresAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         userId: userId,
         tokenHash: tokenHash,
         deviceId: deviceId,
         issuedAt: issuedAt,
         expiresAt: expiresAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [AcsUploadToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AcsUploadToken copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? expiresAt,
    Object? revokedAt = _Undefined,
  }) {
    return AcsUploadToken(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      tokenHash: tokenHash ?? this.tokenHash,
      deviceId: deviceId ?? this.deviceId,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}

class AcsUploadTokenUpdateTable extends _i1.UpdateTable<AcsUploadTokenTable> {
  AcsUploadTokenUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<String, String> tokenHash(String value) => _i1.ColumnValue(
    table.tokenHash,
    value,
  );

  _i1.ColumnValue<String, String> deviceId(String value) => _i1.ColumnValue(
    table.deviceId,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> issuedAt(DateTime value) =>
      _i1.ColumnValue(
        table.issuedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> expiresAt(DateTime value) =>
      _i1.ColumnValue(
        table.expiresAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> revokedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.revokedAt,
        value,
      );
}

class AcsUploadTokenTable extends _i1.Table<_i1.UuidValue?> {
  AcsUploadTokenTable({super.tableRelation})
    : super(tableName: 'acs_upload_tokens') {
    updateTable = AcsUploadTokenUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    tokenHash = _i1.ColumnString(
      'tokenHash',
      this,
    );
    deviceId = _i1.ColumnString(
      'deviceId',
      this,
    );
    issuedAt = _i1.ColumnDateTime(
      'issuedAt',
      this,
    );
    expiresAt = _i1.ColumnDateTime(
      'expiresAt',
      this,
    );
    revokedAt = _i1.ColumnDateTime(
      'revokedAt',
      this,
    );
  }

  late final AcsUploadTokenUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  late final _i1.ColumnString tokenHash;

  /// Instalação que recebeu o token. Token apresentado por outro aparelho é
  /// recusado e revogado.
  late final _i1.ColumnString deviceId;

  late final _i1.ColumnDateTime issuedAt;

  /// Teto fixo (`issuedAt` + 7 dias); o uso não o estende.
  late final _i1.ColumnDateTime expiresAt;

  /// `null` = vigente. Preenchido na revogação (pedido do app, novo login no
  /// mesmo aparelho, aparelho divergente ou conta inativa/sem microárea).
  late final _i1.ColumnDateTime revokedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    tokenHash,
    deviceId,
    issuedAt,
    expiresAt,
    revokedAt,
  ];
}

class AcsUploadTokenInclude extends _i1.IncludeObject {
  AcsUploadTokenInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AcsUploadToken.t;
}

class AcsUploadTokenIncludeList extends _i1.IncludeList {
  AcsUploadTokenIncludeList._({
    _i1.WhereExpressionBuilder<AcsUploadTokenTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AcsUploadToken.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AcsUploadToken.t;
}

class AcsUploadTokenRepository {
  const AcsUploadTokenRepository._();

  /// Returns a list of [AcsUploadToken]s matching the given query parameters.
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
  Future<List<AcsUploadToken>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsUploadTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsUploadTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsUploadTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AcsUploadToken>(
      where: where?.call(AcsUploadToken.t),
      orderBy: orderBy?.call(AcsUploadToken.t),
      orderByList: orderByList?.call(AcsUploadToken.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AcsUploadToken] matching the given query parameters.
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
  Future<AcsUploadToken?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsUploadTokenTable>? where,
    int? offset,
    _i1.OrderByBuilder<AcsUploadTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsUploadTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AcsUploadToken>(
      where: where?.call(AcsUploadToken.t),
      orderBy: orderBy?.call(AcsUploadToken.t),
      orderByList: orderByList?.call(AcsUploadToken.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AcsUploadToken] by its [id] or null if no such row exists.
  Future<AcsUploadToken?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AcsUploadToken>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AcsUploadToken]s in the list and returns the inserted rows.
  ///
  /// The returned [AcsUploadToken]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AcsUploadToken>> insert(
    _i1.DatabaseSession session,
    List<AcsUploadToken> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AcsUploadToken>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AcsUploadToken] and returns the inserted row.
  ///
  /// The returned [AcsUploadToken] will have its `id` field set.
  Future<AcsUploadToken> insertRow(
    _i1.DatabaseSession session,
    AcsUploadToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AcsUploadToken>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AcsUploadToken]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AcsUploadToken>> update(
    _i1.DatabaseSession session,
    List<AcsUploadToken> rows, {
    _i1.ColumnSelections<AcsUploadTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AcsUploadToken>(
      rows,
      columns: columns?.call(AcsUploadToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AcsUploadToken]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AcsUploadToken> updateRow(
    _i1.DatabaseSession session,
    AcsUploadToken row, {
    _i1.ColumnSelections<AcsUploadTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AcsUploadToken>(
      row,
      columns: columns?.call(AcsUploadToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AcsUploadToken] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AcsUploadToken?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AcsUploadTokenUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AcsUploadToken>(
      id,
      columnValues: columnValues(AcsUploadToken.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AcsUploadToken]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AcsUploadToken>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AcsUploadTokenUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<AcsUploadTokenTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsUploadTokenTable>? orderBy,
    _i1.OrderByListBuilder<AcsUploadTokenTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AcsUploadToken>(
      columnValues: columnValues(AcsUploadToken.t.updateTable),
      where: where(AcsUploadToken.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AcsUploadToken.t),
      orderByList: orderByList?.call(AcsUploadToken.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AcsUploadToken]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AcsUploadToken>> delete(
    _i1.DatabaseSession session,
    List<AcsUploadToken> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AcsUploadToken>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AcsUploadToken].
  Future<AcsUploadToken> deleteRow(
    _i1.DatabaseSession session,
    AcsUploadToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AcsUploadToken>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AcsUploadToken>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AcsUploadTokenTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AcsUploadToken>(
      where: where(AcsUploadToken.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsUploadTokenTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AcsUploadToken>(
      where: where?.call(AcsUploadToken.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AcsUploadToken] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AcsUploadTokenTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AcsUploadToken>(
      where: where(AcsUploadToken.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
