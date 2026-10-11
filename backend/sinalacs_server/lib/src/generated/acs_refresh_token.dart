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

/// Refresh token do ACS (LGPD-RT06). Uma linha por token emitido; os tokens de
/// um mesmo login formam uma *família* (`familyId`) e a rotação encadeia
/// dentro dela.
///
/// **Nunca** o token: só o SHA-256 dele em hex. O token é 256 bits aleatórios,
/// então um hash simples basta (não há senha humana para adivinhar).
abstract class AcsRefreshToken
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  AcsRefreshToken._({
    this.id,
    required this.userId,
    required this.familyId,
    required this.tokenHash,
    required this.deviceId,
    required this.issuedAt,
    required this.idleExpiresAt,
    required this.absoluteExpiresAt,
    this.rotatedAt,
    this.revokedAt,
  });

  factory AcsRefreshToken({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i1.UuidValue familyId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime idleExpiresAt,
    required DateTime absoluteExpiresAt,
    DateTime? rotatedAt,
    DateTime? revokedAt,
  }) = _AcsRefreshTokenImpl;

  factory AcsRefreshToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return AcsRefreshToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      familyId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['familyId'],
      ),
      tokenHash: jsonSerialization['tokenHash'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      issuedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['issuedAt'],
      ),
      idleExpiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['idleExpiresAt'],
      ),
      absoluteExpiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['absoluteExpiresAt'],
      ),
      rotatedAt: jsonSerialization['rotatedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['rotatedAt']),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
    );
  }

  static final t = AcsRefreshTokenTable();

  static const db = AcsRefreshTokenRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  /// Todos os tokens nascidos do mesmo login por senha+TOTP.
  _i1.UuidValue familyId;

  String tokenHash;

  /// Aparelho que recebeu o token. Token apresentado por outro aparelho
  /// revoga a família.
  String deviceId;

  DateTime issuedAt;

  /// Janela ociosa: renovada a cada rotação, nunca além de `absoluteExpiresAt`.
  DateTime idleExpiresAt;

  /// Teto do turno, fixado no login por senha+TOTP e herdado pelos filhos.
  DateTime absoluteExpiresAt;

  /// `null` = ainda não usado. Preenchido na rotação.
  DateTime? rotatedAt;

  /// `null` = vigente. Preenchido na revogação da família ou no logout.
  DateTime? revokedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [AcsRefreshToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AcsRefreshToken copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    _i1.UuidValue? familyId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? idleExpiresAt,
    DateTime? absoluteExpiresAt,
    DateTime? rotatedAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AcsRefreshToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'familyId': familyId.toJson(),
      'tokenHash': tokenHash,
      'deviceId': deviceId,
      'issuedAt': issuedAt.toJson(),
      'idleExpiresAt': idleExpiresAt.toJson(),
      'absoluteExpiresAt': absoluteExpiresAt.toJson(),
      if (rotatedAt != null) 'rotatedAt': rotatedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AcsRefreshToken',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'familyId': familyId.toJson(),
      'tokenHash': tokenHash,
      'deviceId': deviceId,
      'issuedAt': issuedAt.toJson(),
      'idleExpiresAt': idleExpiresAt.toJson(),
      'absoluteExpiresAt': absoluteExpiresAt.toJson(),
      if (rotatedAt != null) 'rotatedAt': rotatedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  static AcsRefreshTokenInclude include() {
    return AcsRefreshTokenInclude._();
  }

  static AcsRefreshTokenIncludeList includeList({
    _i1.WhereExpressionBuilder<AcsRefreshTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsRefreshTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsRefreshTokenTable>? orderByList,
    AcsRefreshTokenInclude? include,
  }) {
    return AcsRefreshTokenIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AcsRefreshToken.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AcsRefreshToken.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AcsRefreshTokenImpl extends AcsRefreshToken {
  _AcsRefreshTokenImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required _i1.UuidValue familyId,
    required String tokenHash,
    required String deviceId,
    required DateTime issuedAt,
    required DateTime idleExpiresAt,
    required DateTime absoluteExpiresAt,
    DateTime? rotatedAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         userId: userId,
         familyId: familyId,
         tokenHash: tokenHash,
         deviceId: deviceId,
         issuedAt: issuedAt,
         idleExpiresAt: idleExpiresAt,
         absoluteExpiresAt: absoluteExpiresAt,
         rotatedAt: rotatedAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [AcsRefreshToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AcsRefreshToken copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    _i1.UuidValue? familyId,
    String? tokenHash,
    String? deviceId,
    DateTime? issuedAt,
    DateTime? idleExpiresAt,
    DateTime? absoluteExpiresAt,
    Object? rotatedAt = _Undefined,
    Object? revokedAt = _Undefined,
  }) {
    return AcsRefreshToken(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      familyId: familyId ?? this.familyId,
      tokenHash: tokenHash ?? this.tokenHash,
      deviceId: deviceId ?? this.deviceId,
      issuedAt: issuedAt ?? this.issuedAt,
      idleExpiresAt: idleExpiresAt ?? this.idleExpiresAt,
      absoluteExpiresAt: absoluteExpiresAt ?? this.absoluteExpiresAt,
      rotatedAt: rotatedAt is DateTime? ? rotatedAt : this.rotatedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}

class AcsRefreshTokenUpdateTable extends _i1.UpdateTable<AcsRefreshTokenTable> {
  AcsRefreshTokenUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> familyId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.familyId,
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

  _i1.ColumnValue<DateTime, DateTime> idleExpiresAt(DateTime value) =>
      _i1.ColumnValue(
        table.idleExpiresAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> absoluteExpiresAt(DateTime value) =>
      _i1.ColumnValue(
        table.absoluteExpiresAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> rotatedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.rotatedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> revokedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.revokedAt,
        value,
      );
}

class AcsRefreshTokenTable extends _i1.Table<_i1.UuidValue?> {
  AcsRefreshTokenTable({super.tableRelation})
    : super(tableName: 'acs_refresh_tokens') {
    updateTable = AcsRefreshTokenUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    familyId = _i1.ColumnUuid(
      'familyId',
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
    idleExpiresAt = _i1.ColumnDateTime(
      'idleExpiresAt',
      this,
    );
    absoluteExpiresAt = _i1.ColumnDateTime(
      'absoluteExpiresAt',
      this,
    );
    rotatedAt = _i1.ColumnDateTime(
      'rotatedAt',
      this,
    );
    revokedAt = _i1.ColumnDateTime(
      'revokedAt',
      this,
    );
  }

  late final AcsRefreshTokenUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  /// Todos os tokens nascidos do mesmo login por senha+TOTP.
  late final _i1.ColumnUuid familyId;

  late final _i1.ColumnString tokenHash;

  /// Aparelho que recebeu o token. Token apresentado por outro aparelho
  /// revoga a família.
  late final _i1.ColumnString deviceId;

  late final _i1.ColumnDateTime issuedAt;

  /// Janela ociosa: renovada a cada rotação, nunca além de `absoluteExpiresAt`.
  late final _i1.ColumnDateTime idleExpiresAt;

  /// Teto do turno, fixado no login por senha+TOTP e herdado pelos filhos.
  late final _i1.ColumnDateTime absoluteExpiresAt;

  /// `null` = ainda não usado. Preenchido na rotação.
  late final _i1.ColumnDateTime rotatedAt;

  /// `null` = vigente. Preenchido na revogação da família ou no logout.
  late final _i1.ColumnDateTime revokedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    familyId,
    tokenHash,
    deviceId,
    issuedAt,
    idleExpiresAt,
    absoluteExpiresAt,
    rotatedAt,
    revokedAt,
  ];
}

class AcsRefreshTokenInclude extends _i1.IncludeObject {
  AcsRefreshTokenInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AcsRefreshToken.t;
}

class AcsRefreshTokenIncludeList extends _i1.IncludeList {
  AcsRefreshTokenIncludeList._({
    _i1.WhereExpressionBuilder<AcsRefreshTokenTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AcsRefreshToken.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => AcsRefreshToken.t;
}

class AcsRefreshTokenRepository {
  const AcsRefreshTokenRepository._();

  /// Returns a list of [AcsRefreshToken]s matching the given query parameters.
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
  Future<List<AcsRefreshToken>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsRefreshTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsRefreshTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsRefreshTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AcsRefreshToken>(
      where: where?.call(AcsRefreshToken.t),
      orderBy: orderBy?.call(AcsRefreshToken.t),
      orderByList: orderByList?.call(AcsRefreshToken.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AcsRefreshToken] matching the given query parameters.
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
  Future<AcsRefreshToken?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsRefreshTokenTable>? where,
    int? offset,
    _i1.OrderByBuilder<AcsRefreshTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AcsRefreshTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AcsRefreshToken>(
      where: where?.call(AcsRefreshToken.t),
      orderBy: orderBy?.call(AcsRefreshToken.t),
      orderByList: orderByList?.call(AcsRefreshToken.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AcsRefreshToken] by its [id] or null if no such row exists.
  Future<AcsRefreshToken?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AcsRefreshToken>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AcsRefreshToken]s in the list and returns the inserted rows.
  ///
  /// The returned [AcsRefreshToken]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<AcsRefreshToken>> insert(
    _i1.DatabaseSession session,
    List<AcsRefreshToken> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<AcsRefreshToken>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [AcsRefreshToken] and returns the inserted row.
  ///
  /// The returned [AcsRefreshToken] will have its `id` field set.
  Future<AcsRefreshToken> insertRow(
    _i1.DatabaseSession session,
    AcsRefreshToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AcsRefreshToken>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AcsRefreshToken]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AcsRefreshToken>> update(
    _i1.DatabaseSession session,
    List<AcsRefreshToken> rows, {
    _i1.ColumnSelections<AcsRefreshTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AcsRefreshToken>(
      rows,
      columns: columns?.call(AcsRefreshToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AcsRefreshToken]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AcsRefreshToken> updateRow(
    _i1.DatabaseSession session,
    AcsRefreshToken row, {
    _i1.ColumnSelections<AcsRefreshTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AcsRefreshToken>(
      row,
      columns: columns?.call(AcsRefreshToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AcsRefreshToken] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AcsRefreshToken?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<AcsRefreshTokenUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<AcsRefreshToken>(
      id,
      columnValues: columnValues(AcsRefreshToken.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AcsRefreshToken]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<AcsRefreshToken>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<AcsRefreshTokenUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<AcsRefreshTokenTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AcsRefreshTokenTable>? orderBy,
    _i1.OrderByListBuilder<AcsRefreshTokenTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<AcsRefreshToken>(
      columnValues: columnValues(AcsRefreshToken.t.updateTable),
      where: where(AcsRefreshToken.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AcsRefreshToken.t),
      orderByList: orderByList?.call(AcsRefreshToken.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [AcsRefreshToken]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AcsRefreshToken>> delete(
    _i1.DatabaseSession session,
    List<AcsRefreshToken> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AcsRefreshToken>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AcsRefreshToken].
  Future<AcsRefreshToken> deleteRow(
    _i1.DatabaseSession session,
    AcsRefreshToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AcsRefreshToken>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AcsRefreshToken>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AcsRefreshTokenTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AcsRefreshToken>(
      where: where(AcsRefreshToken.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<AcsRefreshTokenTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AcsRefreshToken>(
      where: where?.call(AcsRefreshToken.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AcsRefreshToken] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<AcsRefreshTokenTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AcsRefreshToken>(
      where: where(AcsRefreshToken.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
