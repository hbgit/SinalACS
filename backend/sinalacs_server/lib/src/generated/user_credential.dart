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

/// Credencial de login institucional (RF07). Uma linha por usuário, 1:1 com
/// `users` — o `userId` tem índice único.
///
/// Tabela própria em vez de colunas em `acs` por três motivos: a senha não é
/// dado de domínio do ACS (um coordenador ou administrador passa a ter
/// credencial sem que a tabela `acs` ganhe uma linha que não é dele), os
/// parâmetros do Argon2id precisam viajar com o hash, e o contador de
/// tentativas é estado de autenticação, não de territorialização.
abstract class UserCredential
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  UserCredential._({
    this.id,
    required this.userId,
    required this.passwordHash,
    required this.passwordSalt,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
    required this.failedAttempts,
    this.lockedUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserCredential({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String passwordHash,
    required String passwordSalt,
    required int memoryKb,
    required int iterations,
    required int parallelism,
    required int failedAttempts,
    DateTime? lockedUntil,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _UserCredentialImpl;

  factory UserCredential.fromJson(Map<String, dynamic> jsonSerialization) {
    return UserCredential(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      passwordHash: jsonSerialization['passwordHash'] as String,
      passwordSalt: jsonSerialization['passwordSalt'] as String,
      memoryKb: jsonSerialization['memoryKb'] as int,
      iterations: jsonSerialization['iterations'] as int,
      parallelism: jsonSerialization['parallelism'] as int,
      failedAttempts: jsonSerialization['failedAttempts'] as int,
      lockedUntil: jsonSerialization['lockedUntil'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['lockedUntil'],
            ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  static final t = UserCredentialTable();

  static const db = UserCredentialRepository._();

  @override
  _i1.UuidValue? id;

  _i1.UuidValue userId;

  /// Argon2id em base64. **Nunca** a senha.
  String passwordHash;

  /// Salt por credencial, em base64. Guardado junto do hash porque a
  /// verificação precisa dele — e ao lado dos parâmetros, para que subir o
  /// custo não invalide as credenciais já emitidas.
  String passwordSalt;

  int memoryKb;

  int iterations;

  int parallelism;

  /// Estado do bloqueio por tentativas (achado F6). Zera no login bem-sucedido.
  int failedAttempts;

  /// `null` = não bloqueado.
  DateTime? lockedUntil;

  DateTime createdAt;

  DateTime updatedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [UserCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  UserCredential copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? passwordHash,
    String? passwordSalt,
    int? memoryKb,
    int? iterations,
    int? parallelism,
    int? failedAttempts,
    DateTime? lockedUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'UserCredential',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'passwordHash': passwordHash,
      'passwordSalt': passwordSalt,
      'memoryKb': memoryKb,
      'iterations': iterations,
      'parallelism': parallelism,
      'failedAttempts': failedAttempts,
      if (lockedUntil != null) 'lockedUntil': lockedUntil?.toJson(),
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'UserCredential',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'passwordHash': passwordHash,
      'passwordSalt': passwordSalt,
      'memoryKb': memoryKb,
      'iterations': iterations,
      'parallelism': parallelism,
      'failedAttempts': failedAttempts,
      if (lockedUntil != null) 'lockedUntil': lockedUntil?.toJson(),
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  static UserCredentialInclude include() {
    return UserCredentialInclude._();
  }

  static UserCredentialIncludeList includeList({
    _i1.WhereExpressionBuilder<UserCredentialTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<UserCredentialTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<UserCredentialTable>? orderByList,
    UserCredentialInclude? include,
  }) {
    return UserCredentialIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(UserCredential.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(UserCredential.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _UserCredentialImpl extends UserCredential {
  _UserCredentialImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String passwordHash,
    required String passwordSalt,
    required int memoryKb,
    required int iterations,
    required int parallelism,
    required int failedAttempts,
    DateTime? lockedUntil,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         userId: userId,
         passwordHash: passwordHash,
         passwordSalt: passwordSalt,
         memoryKb: memoryKb,
         iterations: iterations,
         parallelism: parallelism,
         failedAttempts: failedAttempts,
         lockedUntil: lockedUntil,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [UserCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  UserCredential copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? passwordHash,
    String? passwordSalt,
    int? memoryKb,
    int? iterations,
    int? parallelism,
    int? failedAttempts,
    Object? lockedUntil = _Undefined,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserCredential(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      memoryKb: memoryKb ?? this.memoryKb,
      iterations: iterations ?? this.iterations,
      parallelism: parallelism ?? this.parallelism,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: lockedUntil is DateTime? ? lockedUntil : this.lockedUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class UserCredentialUpdateTable extends _i1.UpdateTable<UserCredentialTable> {
  UserCredentialUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<String, String> passwordHash(String value) => _i1.ColumnValue(
    table.passwordHash,
    value,
  );

  _i1.ColumnValue<String, String> passwordSalt(String value) => _i1.ColumnValue(
    table.passwordSalt,
    value,
  );

  _i1.ColumnValue<int, int> memoryKb(int value) => _i1.ColumnValue(
    table.memoryKb,
    value,
  );

  _i1.ColumnValue<int, int> iterations(int value) => _i1.ColumnValue(
    table.iterations,
    value,
  );

  _i1.ColumnValue<int, int> parallelism(int value) => _i1.ColumnValue(
    table.parallelism,
    value,
  );

  _i1.ColumnValue<int, int> failedAttempts(int value) => _i1.ColumnValue(
    table.failedAttempts,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> lockedUntil(DateTime? value) =>
      _i1.ColumnValue(
        table.lockedUntil,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> updatedAt(DateTime value) =>
      _i1.ColumnValue(
        table.updatedAt,
        value,
      );
}

class UserCredentialTable extends _i1.Table<_i1.UuidValue?> {
  UserCredentialTable({super.tableRelation})
    : super(tableName: 'user_credentials') {
    updateTable = UserCredentialUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    passwordHash = _i1.ColumnString(
      'passwordHash',
      this,
    );
    passwordSalt = _i1.ColumnString(
      'passwordSalt',
      this,
    );
    memoryKb = _i1.ColumnInt(
      'memoryKb',
      this,
    );
    iterations = _i1.ColumnInt(
      'iterations',
      this,
    );
    parallelism = _i1.ColumnInt(
      'parallelism',
      this,
    );
    failedAttempts = _i1.ColumnInt(
      'failedAttempts',
      this,
    );
    lockedUntil = _i1.ColumnDateTime(
      'lockedUntil',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    updatedAt = _i1.ColumnDateTime(
      'updatedAt',
      this,
    );
  }

  late final UserCredentialUpdateTable updateTable;

  late final _i1.ColumnUuid userId;

  /// Argon2id em base64. **Nunca** a senha.
  late final _i1.ColumnString passwordHash;

  /// Salt por credencial, em base64. Guardado junto do hash porque a
  /// verificação precisa dele — e ao lado dos parâmetros, para que subir o
  /// custo não invalide as credenciais já emitidas.
  late final _i1.ColumnString passwordSalt;

  late final _i1.ColumnInt memoryKb;

  late final _i1.ColumnInt iterations;

  late final _i1.ColumnInt parallelism;

  /// Estado do bloqueio por tentativas (achado F6). Zera no login bem-sucedido.
  late final _i1.ColumnInt failedAttempts;

  /// `null` = não bloqueado.
  late final _i1.ColumnDateTime lockedUntil;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnDateTime updatedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    passwordHash,
    passwordSalt,
    memoryKb,
    iterations,
    parallelism,
    failedAttempts,
    lockedUntil,
    createdAt,
    updatedAt,
  ];
}

class UserCredentialInclude extends _i1.IncludeObject {
  UserCredentialInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => UserCredential.t;
}

class UserCredentialIncludeList extends _i1.IncludeList {
  UserCredentialIncludeList._({
    _i1.WhereExpressionBuilder<UserCredentialTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(UserCredential.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => UserCredential.t;
}

class UserCredentialRepository {
  const UserCredentialRepository._();

  /// Returns a list of [UserCredential]s matching the given query parameters.
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
  Future<List<UserCredential>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<UserCredentialTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<UserCredentialTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<UserCredentialTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<UserCredential>(
      where: where?.call(UserCredential.t),
      orderBy: orderBy?.call(UserCredential.t),
      orderByList: orderByList?.call(UserCredential.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [UserCredential] matching the given query parameters.
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
  Future<UserCredential?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<UserCredentialTable>? where,
    int? offset,
    _i1.OrderByBuilder<UserCredentialTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<UserCredentialTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<UserCredential>(
      where: where?.call(UserCredential.t),
      orderBy: orderBy?.call(UserCredential.t),
      orderByList: orderByList?.call(UserCredential.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [UserCredential] by its [id] or null if no such row exists.
  Future<UserCredential?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<UserCredential>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [UserCredential]s in the list and returns the inserted rows.
  ///
  /// The returned [UserCredential]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<UserCredential>> insert(
    _i1.DatabaseSession session,
    List<UserCredential> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<UserCredential>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [UserCredential] and returns the inserted row.
  ///
  /// The returned [UserCredential] will have its `id` field set.
  Future<UserCredential> insertRow(
    _i1.DatabaseSession session,
    UserCredential row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<UserCredential>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [UserCredential]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<UserCredential>> update(
    _i1.DatabaseSession session,
    List<UserCredential> rows, {
    _i1.ColumnSelections<UserCredentialTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<UserCredential>(
      rows,
      columns: columns?.call(UserCredential.t),
      transaction: transaction,
    );
  }

  /// Updates a single [UserCredential]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<UserCredential> updateRow(
    _i1.DatabaseSession session,
    UserCredential row, {
    _i1.ColumnSelections<UserCredentialTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<UserCredential>(
      row,
      columns: columns?.call(UserCredential.t),
      transaction: transaction,
    );
  }

  /// Updates a single [UserCredential] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<UserCredential?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<UserCredentialUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<UserCredential>(
      id,
      columnValues: columnValues(UserCredential.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [UserCredential]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<UserCredential>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<UserCredentialUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<UserCredentialTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<UserCredentialTable>? orderBy,
    _i1.OrderByListBuilder<UserCredentialTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<UserCredential>(
      columnValues: columnValues(UserCredential.t.updateTable),
      where: where(UserCredential.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(UserCredential.t),
      orderByList: orderByList?.call(UserCredential.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [UserCredential]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<UserCredential>> delete(
    _i1.DatabaseSession session,
    List<UserCredential> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<UserCredential>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [UserCredential].
  Future<UserCredential> deleteRow(
    _i1.DatabaseSession session,
    UserCredential row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<UserCredential>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<UserCredential>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<UserCredentialTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<UserCredential>(
      where: where(UserCredential.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<UserCredentialTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<UserCredential>(
      where: where?.call(UserCredential.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [UserCredential] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<UserCredentialTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<UserCredential>(
      where: where(UserCredential.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
