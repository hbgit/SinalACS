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

/// Convite de uso único gerado pelo ACS para um paciente já cadastrado em
/// sua microárea concluir o onboarding no próprio aparelho. Não cria
/// identidade nova (RF01/RF07 — autenticação institucional — segue sem
/// decisão própria); ativa o acesso de um paciente que já existe em
/// `patients`, na microárea de quem gerou o convite.
abstract class EnrollmentToken
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  EnrollmentToken._({
    this.id,
    required this.tokenHash,
    required this.patientId,
    required this.microAreaId,
    required this.createdByAcsId,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
  });

  factory EnrollmentToken({
    _i1.UuidValue? id,
    required String tokenHash,
    required _i1.UuidValue patientId,
    required _i1.UuidValue microAreaId,
    required _i1.UuidValue createdByAcsId,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) = _EnrollmentTokenImpl;

  factory EnrollmentToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return EnrollmentToken(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      tokenHash: jsonSerialization['tokenHash'] as String,
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      microAreaId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['microAreaId'],
      ),
      createdByAcsId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['createdByAcsId'],
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      expiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      consumedAt: jsonSerialization['consumedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['consumedAt']),
    );
  }

  static final t = EnrollmentTokenTable();

  static const db = EnrollmentTokenRepository._();

  @override
  _i1.UuidValue? id;

  /// sha256 do token real. O valor em claro só existe no momento da geração
  /// (devolvido ao ACS para virar QR Code) e nunca é persistido — mesmo
  /// padrão de `users.cpfHash`.
  String tokenHash;

  _i1.UuidValue patientId;

  _i1.UuidValue microAreaId;

  _i1.UuidValue createdByAcsId;

  DateTime createdAt;

  DateTime expiresAt;

  /// Marca o consumo atômico. `null` = ainda válido para uso.
  DateTime? consumedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [EnrollmentToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  EnrollmentToken copyWith({
    _i1.UuidValue? id,
    String? tokenHash,
    _i1.UuidValue? patientId,
    _i1.UuidValue? microAreaId,
    _i1.UuidValue? createdByAcsId,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? consumedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EnrollmentToken',
      if (id != null) 'id': id?.toJson(),
      'tokenHash': tokenHash,
      'patientId': patientId.toJson(),
      'microAreaId': microAreaId.toJson(),
      'createdByAcsId': createdByAcsId.toJson(),
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'EnrollmentToken',
      if (id != null) 'id': id?.toJson(),
      'tokenHash': tokenHash,
      'patientId': patientId.toJson(),
      'microAreaId': microAreaId.toJson(),
      'createdByAcsId': createdByAcsId.toJson(),
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
    };
  }

  static EnrollmentTokenInclude include() {
    return EnrollmentTokenInclude._();
  }

  static EnrollmentTokenIncludeList includeList({
    _i1.WhereExpressionBuilder<EnrollmentTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<EnrollmentTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<EnrollmentTokenTable>? orderByList,
    EnrollmentTokenInclude? include,
  }) {
    return EnrollmentTokenIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EnrollmentToken.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(EnrollmentToken.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _EnrollmentTokenImpl extends EnrollmentToken {
  _EnrollmentTokenImpl({
    _i1.UuidValue? id,
    required String tokenHash,
    required _i1.UuidValue patientId,
    required _i1.UuidValue microAreaId,
    required _i1.UuidValue createdByAcsId,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) : super._(
         id: id,
         tokenHash: tokenHash,
         patientId: patientId,
         microAreaId: microAreaId,
         createdByAcsId: createdByAcsId,
         createdAt: createdAt,
         expiresAt: expiresAt,
         consumedAt: consumedAt,
       );

  /// Returns a shallow copy of this [EnrollmentToken]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  EnrollmentToken copyWith({
    Object? id = _Undefined,
    String? tokenHash,
    _i1.UuidValue? patientId,
    _i1.UuidValue? microAreaId,
    _i1.UuidValue? createdByAcsId,
    DateTime? createdAt,
    DateTime? expiresAt,
    Object? consumedAt = _Undefined,
  }) {
    return EnrollmentToken(
      id: id is _i1.UuidValue? ? id : this.id,
      tokenHash: tokenHash ?? this.tokenHash,
      patientId: patientId ?? this.patientId,
      microAreaId: microAreaId ?? this.microAreaId,
      createdByAcsId: createdByAcsId ?? this.createdByAcsId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt is DateTime? ? consumedAt : this.consumedAt,
    );
  }
}

class EnrollmentTokenUpdateTable extends _i1.UpdateTable<EnrollmentTokenTable> {
  EnrollmentTokenUpdateTable(super.table);

  _i1.ColumnValue<String, String> tokenHash(String value) => _i1.ColumnValue(
    table.tokenHash,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> patientId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.patientId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> microAreaId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.microAreaId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> createdByAcsId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.createdByAcsId,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> expiresAt(DateTime value) =>
      _i1.ColumnValue(
        table.expiresAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> consumedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.consumedAt,
        value,
      );
}

class EnrollmentTokenTable extends _i1.Table<_i1.UuidValue?> {
  EnrollmentTokenTable({super.tableRelation})
    : super(tableName: 'enrollment_tokens') {
    updateTable = EnrollmentTokenUpdateTable(this);
    tokenHash = _i1.ColumnString(
      'tokenHash',
      this,
    );
    patientId = _i1.ColumnUuid(
      'patientId',
      this,
    );
    microAreaId = _i1.ColumnUuid(
      'microAreaId',
      this,
    );
    createdByAcsId = _i1.ColumnUuid(
      'createdByAcsId',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    expiresAt = _i1.ColumnDateTime(
      'expiresAt',
      this,
    );
    consumedAt = _i1.ColumnDateTime(
      'consumedAt',
      this,
    );
  }

  late final EnrollmentTokenUpdateTable updateTable;

  /// sha256 do token real. O valor em claro só existe no momento da geração
  /// (devolvido ao ACS para virar QR Code) e nunca é persistido — mesmo
  /// padrão de `users.cpfHash`.
  late final _i1.ColumnString tokenHash;

  late final _i1.ColumnUuid patientId;

  late final _i1.ColumnUuid microAreaId;

  late final _i1.ColumnUuid createdByAcsId;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnDateTime expiresAt;

  /// Marca o consumo atômico. `null` = ainda válido para uso.
  late final _i1.ColumnDateTime consumedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    tokenHash,
    patientId,
    microAreaId,
    createdByAcsId,
    createdAt,
    expiresAt,
    consumedAt,
  ];
}

class EnrollmentTokenInclude extends _i1.IncludeObject {
  EnrollmentTokenInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => EnrollmentToken.t;
}

class EnrollmentTokenIncludeList extends _i1.IncludeList {
  EnrollmentTokenIncludeList._({
    _i1.WhereExpressionBuilder<EnrollmentTokenTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(EnrollmentToken.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => EnrollmentToken.t;
}

class EnrollmentTokenRepository {
  const EnrollmentTokenRepository._();

  /// Returns a list of [EnrollmentToken]s matching the given query parameters.
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
  Future<List<EnrollmentToken>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<EnrollmentTokenTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<EnrollmentTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<EnrollmentTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<EnrollmentToken>(
      where: where?.call(EnrollmentToken.t),
      orderBy: orderBy?.call(EnrollmentToken.t),
      orderByList: orderByList?.call(EnrollmentToken.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [EnrollmentToken] matching the given query parameters.
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
  Future<EnrollmentToken?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<EnrollmentTokenTable>? where,
    int? offset,
    _i1.OrderByBuilder<EnrollmentTokenTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<EnrollmentTokenTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<EnrollmentToken>(
      where: where?.call(EnrollmentToken.t),
      orderBy: orderBy?.call(EnrollmentToken.t),
      orderByList: orderByList?.call(EnrollmentToken.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [EnrollmentToken] by its [id] or null if no such row exists.
  Future<EnrollmentToken?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<EnrollmentToken>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [EnrollmentToken]s in the list and returns the inserted rows.
  ///
  /// The returned [EnrollmentToken]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<EnrollmentToken>> insert(
    _i1.DatabaseSession session,
    List<EnrollmentToken> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<EnrollmentToken>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [EnrollmentToken] and returns the inserted row.
  ///
  /// The returned [EnrollmentToken] will have its `id` field set.
  Future<EnrollmentToken> insertRow(
    _i1.DatabaseSession session,
    EnrollmentToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<EnrollmentToken>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [EnrollmentToken]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<EnrollmentToken>> update(
    _i1.DatabaseSession session,
    List<EnrollmentToken> rows, {
    _i1.ColumnSelections<EnrollmentTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<EnrollmentToken>(
      rows,
      columns: columns?.call(EnrollmentToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [EnrollmentToken]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<EnrollmentToken> updateRow(
    _i1.DatabaseSession session,
    EnrollmentToken row, {
    _i1.ColumnSelections<EnrollmentTokenTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<EnrollmentToken>(
      row,
      columns: columns?.call(EnrollmentToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [EnrollmentToken] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<EnrollmentToken?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<EnrollmentTokenUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<EnrollmentToken>(
      id,
      columnValues: columnValues(EnrollmentToken.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [EnrollmentToken]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<EnrollmentToken>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<EnrollmentTokenUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<EnrollmentTokenTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<EnrollmentTokenTable>? orderBy,
    _i1.OrderByListBuilder<EnrollmentTokenTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<EnrollmentToken>(
      columnValues: columnValues(EnrollmentToken.t.updateTable),
      where: where(EnrollmentToken.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EnrollmentToken.t),
      orderByList: orderByList?.call(EnrollmentToken.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [EnrollmentToken]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<EnrollmentToken>> delete(
    _i1.DatabaseSession session,
    List<EnrollmentToken> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<EnrollmentToken>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [EnrollmentToken].
  Future<EnrollmentToken> deleteRow(
    _i1.DatabaseSession session,
    EnrollmentToken row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<EnrollmentToken>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<EnrollmentToken>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<EnrollmentTokenTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<EnrollmentToken>(
      where: where(EnrollmentToken.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<EnrollmentTokenTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<EnrollmentToken>(
      where: where?.call(EnrollmentToken.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [EnrollmentToken] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<EnrollmentTokenTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<EnrollmentToken>(
      where: where(EnrollmentToken.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
