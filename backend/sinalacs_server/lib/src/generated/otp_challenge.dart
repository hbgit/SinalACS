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

/// Desafio de código OTP do login passwordless (RF01).
///
/// Mesmo padrão de hash-só de `enrollment_tokens`: o código em claro existe
/// apenas no momento da geração (enviado por SMS) e nunca é persistido. A
/// tabela guarda o HMAC, para que um dump do banco não entregue códigos
/// válidos de pacientes que estão tentando entrar agora.
abstract class OtpChallenge
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  OtpChallenge._({
    this.id,
    required this.userId,
    required this.codeHash,
    required this.attempts,
    required this.createdAt,
    required this.expiresAt,
    this.consumedAt,
  });

  factory OtpChallenge({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String codeHash,
    required int attempts,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) = _OtpChallengeImpl;

  factory OtpChallenge.fromJson(Map<String, dynamic> jsonSerialization) {
    return OtpChallenge(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      codeHash: jsonSerialization['codeHash'] as String,
      attempts: jsonSerialization['attempts'] as int,
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

  static final t = OtpChallengeTable();

  static const db = OtpChallengeRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  /// HMAC-SHA-256 do código, com campo de domínio próprio (ver HmacCpfHasher).
  String codeHash;

  /// Tentativas de verificação já gastas. O código morre ao atingir o limite,
  /// mesmo antes de expirar — 6 dígitos são 10^6 combinações, e sem contador
  /// um atacante com um código enviado teria tentativas ilimitadas.
  int attempts;

  DateTime createdAt;

  DateTime expiresAt;

  /// Marca o consumo. `null` = ainda válido; nunca consumido = o desafio mais
  /// recente do paciente é o que vale.
  DateTime? consumedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [OtpChallenge]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  OtpChallenge copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? codeHash,
    int? attempts,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? consumedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'OtpChallenge',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'codeHash': codeHash,
      'attempts': attempts,
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'OtpChallenge',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'codeHash': codeHash,
      'attempts': attempts,
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
    };
  }

  static OtpChallengeInclude include() {
    return OtpChallengeInclude._();
  }

  static OtpChallengeIncludeList includeList({
    _i1.WhereExpressionBuilder<OtpChallengeTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<OtpChallengeTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<OtpChallengeTable>? orderByList,
    OtpChallengeInclude? include,
  }) {
    return OtpChallengeIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(OtpChallenge.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(OtpChallenge.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _OtpChallengeImpl extends OtpChallenge {
  _OtpChallengeImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String codeHash,
    required int attempts,
    required DateTime createdAt,
    required DateTime expiresAt,
    DateTime? consumedAt,
  }) : super._(
         id: id,
         userId: userId,
         codeHash: codeHash,
         attempts: attempts,
         createdAt: createdAt,
         expiresAt: expiresAt,
         consumedAt: consumedAt,
       );

  /// Returns a shallow copy of this [OtpChallenge]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  OtpChallenge copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? codeHash,
    int? attempts,
    DateTime? createdAt,
    DateTime? expiresAt,
    Object? consumedAt = _Undefined,
  }) {
    return OtpChallenge(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      codeHash: codeHash ?? this.codeHash,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt is DateTime? ? consumedAt : this.consumedAt,
    );
  }
}

class OtpChallengeUpdateTable extends _i1.UpdateTable<OtpChallengeTable> {
  OtpChallengeUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<String, String> codeHash(String value) => _i1.ColumnValue(
    table.codeHash,
    value,
  );

  _i1.ColumnValue<int, int> attempts(int value) => _i1.ColumnValue(
    table.attempts,
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

class OtpChallengeTable extends _i1.Table<_i1.UuidValue?> {
  OtpChallengeTable({super.tableRelation})
    : super(tableName: 'otp_challenges') {
    updateTable = OtpChallengeUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    codeHash = _i1.ColumnString(
      'codeHash',
      this,
    );
    attempts = _i1.ColumnInt(
      'attempts',
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

  late final OtpChallengeUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  /// HMAC-SHA-256 do código, com campo de domínio próprio (ver HmacCpfHasher).
  late final _i1.ColumnString codeHash;

  /// Tentativas de verificação já gastas. O código morre ao atingir o limite,
  /// mesmo antes de expirar — 6 dígitos são 10^6 combinações, e sem contador
  /// um atacante com um código enviado teria tentativas ilimitadas.
  late final _i1.ColumnInt attempts;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnDateTime expiresAt;

  /// Marca o consumo. `null` = ainda válido; nunca consumido = o desafio mais
  /// recente do paciente é o que vale.
  late final _i1.ColumnDateTime consumedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    codeHash,
    attempts,
    createdAt,
    expiresAt,
    consumedAt,
  ];
}

class OtpChallengeInclude extends _i1.IncludeObject {
  OtpChallengeInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => OtpChallenge.t;
}

class OtpChallengeIncludeList extends _i1.IncludeList {
  OtpChallengeIncludeList._({
    _i1.WhereExpressionBuilder<OtpChallengeTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(OtpChallenge.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => OtpChallenge.t;
}

class OtpChallengeRepository {
  const OtpChallengeRepository._();

  /// Returns a list of [OtpChallenge]s matching the given query parameters.
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
  Future<List<OtpChallenge>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<OtpChallengeTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<OtpChallengeTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<OtpChallengeTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<OtpChallenge>(
      where: where?.call(OtpChallenge.t),
      orderBy: orderBy?.call(OtpChallenge.t),
      orderByList: orderByList?.call(OtpChallenge.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [OtpChallenge] matching the given query parameters.
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
  Future<OtpChallenge?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<OtpChallengeTable>? where,
    int? offset,
    _i1.OrderByBuilder<OtpChallengeTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<OtpChallengeTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<OtpChallenge>(
      where: where?.call(OtpChallenge.t),
      orderBy: orderBy?.call(OtpChallenge.t),
      orderByList: orderByList?.call(OtpChallenge.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [OtpChallenge] by its [id] or null if no such row exists.
  Future<OtpChallenge?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<OtpChallenge>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [OtpChallenge]s in the list and returns the inserted rows.
  ///
  /// The returned [OtpChallenge]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<OtpChallenge>> insert(
    _i1.DatabaseSession session,
    List<OtpChallenge> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<OtpChallenge>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [OtpChallenge] and returns the inserted row.
  ///
  /// The returned [OtpChallenge] will have its `id` field set.
  Future<OtpChallenge> insertRow(
    _i1.DatabaseSession session,
    OtpChallenge row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<OtpChallenge>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [OtpChallenge]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<OtpChallenge>> update(
    _i1.DatabaseSession session,
    List<OtpChallenge> rows, {
    _i1.ColumnSelections<OtpChallengeTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<OtpChallenge>(
      rows,
      columns: columns?.call(OtpChallenge.t),
      transaction: transaction,
    );
  }

  /// Updates a single [OtpChallenge]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<OtpChallenge> updateRow(
    _i1.DatabaseSession session,
    OtpChallenge row, {
    _i1.ColumnSelections<OtpChallengeTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<OtpChallenge>(
      row,
      columns: columns?.call(OtpChallenge.t),
      transaction: transaction,
    );
  }

  /// Updates a single [OtpChallenge] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<OtpChallenge?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<OtpChallengeUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<OtpChallenge>(
      id,
      columnValues: columnValues(OtpChallenge.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [OtpChallenge]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<OtpChallenge>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<OtpChallengeUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<OtpChallengeTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<OtpChallengeTable>? orderBy,
    _i1.OrderByListBuilder<OtpChallengeTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<OtpChallenge>(
      columnValues: columnValues(OtpChallenge.t.updateTable),
      where: where(OtpChallenge.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(OtpChallenge.t),
      orderByList: orderByList?.call(OtpChallenge.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [OtpChallenge]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<OtpChallenge>> delete(
    _i1.DatabaseSession session,
    List<OtpChallenge> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<OtpChallenge>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [OtpChallenge].
  Future<OtpChallenge> deleteRow(
    _i1.DatabaseSession session,
    OtpChallenge row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<OtpChallenge>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<OtpChallenge>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<OtpChallengeTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<OtpChallenge>(
      where: where(OtpChallenge.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<OtpChallengeTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<OtpChallenge>(
      where: where?.call(OtpChallenge.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [OtpChallenge] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<OtpChallengeTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<OtpChallenge>(
      where: where(OtpChallenge.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
