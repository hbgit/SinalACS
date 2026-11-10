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

/// Credencial de dispositivo do participante (C-05, RF24).
///
/// O convite QR do agente (enrollment_tokens) vira, ao ser concluído, uma
/// credencial de longa duração amarrada a ESTE aparelho: o app gera um
/// `deviceId` (UUID aleatório de instalação — nunca um identificador de
/// hardware, spec/lgpd_data_audit.md §2.4) e um segredo aleatório de 32
/// bytes; o servidor guarda só o hash do segredo, e o app guarda o segredo
/// protegido pelo PIN local (Argon2id + AES-GCM, no Keystore do aparelho).
/// O PIN nunca sai do aparelho: o login seguinte (`auth.loginDevice`)
/// apresenta deviceId + segredo, e o JWT sai com o device_id da credencial.
///
/// `revokedAt` é a invalidação da recuperação de acesso (C-12): um convite
/// novo vinculado ao mesmo paciente revoga as credenciais anteriores, e um
/// aparelho revogado recebe a mesma recusa de um segredo errado.
abstract class PatientDeviceCredential
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  PatientDeviceCredential._({
    this.id,
    required this.patientId,
    required this.deviceId,
    required this.credentialHash,
    required this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  factory PatientDeviceCredential({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required String deviceId,
    required String credentialHash,
    required DateTime createdAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) = _PatientDeviceCredentialImpl;

  factory PatientDeviceCredential.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return PatientDeviceCredential(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      patientId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['patientId'],
      ),
      deviceId: jsonSerialization['deviceId'] as String,
      credentialHash: jsonSerialization['credentialHash'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      lastUsedAt: jsonSerialization['lastUsedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['lastUsedAt']),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
    );
  }

  static final t = PatientDeviceCredentialTable();

  static const db = PatientDeviceCredentialRepository._();

  @override
  _i1.UuidValue? id;

  /// Dono da credencial — o identificador pseudônimo do participante
  /// (`users.id`/`patients.id`; sem CPF desde C-05).
  _i1.UuidValue patientId;

  /// UUID minúsculo de instalação, validado em `isDeviceIdFormat`. Único:
  /// um aparelho não pode ter duas credenciais vivas, e a reemissão grava
  /// uma linha nova com outro deviceId (C-12).
  String deviceId;

  /// SHA-256 (hex) de `sinalacs-pdc-v1:<segredo>` — o segredo tem 256 bits
  /// de entropia, então hash rápido basta; nunca em claro.
  String credentialHash;

  DateTime createdAt;

  /// Atualizado a cada `auth.loginDevice` bem-sucedido (LGPD-RT06: retenção
  /// do acesso do titular).
  DateTime? lastUsedAt;

  /// `null` = credencial viva. Preenchido pela C-12 (novo convite revoga a
  /// credencial anterior do mesmo paciente).
  DateTime? revokedAt;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [PatientDeviceCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PatientDeviceCredential copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? patientId,
    String? deviceId,
    String? credentialHash,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PatientDeviceCredential',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'deviceId': deviceId,
      'credentialHash': credentialHash,
      'createdAt': createdAt.toJson(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PatientDeviceCredential',
      if (id != null) 'id': id?.toJson(),
      'patientId': patientId.toJson(),
      'deviceId': deviceId,
      'credentialHash': credentialHash,
      'createdAt': createdAt.toJson(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  static PatientDeviceCredentialInclude include() {
    return PatientDeviceCredentialInclude._();
  }

  static PatientDeviceCredentialIncludeList includeList({
    _i1.WhereExpressionBuilder<PatientDeviceCredentialTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PatientDeviceCredentialTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PatientDeviceCredentialTable>? orderByList,
    PatientDeviceCredentialInclude? include,
  }) {
    return PatientDeviceCredentialIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PatientDeviceCredential.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(PatientDeviceCredential.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PatientDeviceCredentialImpl extends PatientDeviceCredential {
  _PatientDeviceCredentialImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue patientId,
    required String deviceId,
    required String credentialHash,
    required DateTime createdAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         patientId: patientId,
         deviceId: deviceId,
         credentialHash: credentialHash,
         createdAt: createdAt,
         lastUsedAt: lastUsedAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [PatientDeviceCredential]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PatientDeviceCredential copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? patientId,
    String? deviceId,
    String? credentialHash,
    DateTime? createdAt,
    Object? lastUsedAt = _Undefined,
    Object? revokedAt = _Undefined,
  }) {
    return PatientDeviceCredential(
      id: id is _i1.UuidValue? ? id : this.id,
      patientId: patientId ?? this.patientId,
      deviceId: deviceId ?? this.deviceId,
      credentialHash: credentialHash ?? this.credentialHash,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt is DateTime? ? lastUsedAt : this.lastUsedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}

class PatientDeviceCredentialUpdateTable
    extends _i1.UpdateTable<PatientDeviceCredentialTable> {
  PatientDeviceCredentialUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> patientId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.patientId,
    value,
  );

  _i1.ColumnValue<String, String> deviceId(String value) => _i1.ColumnValue(
    table.deviceId,
    value,
  );

  _i1.ColumnValue<String, String> credentialHash(String value) =>
      _i1.ColumnValue(
        table.credentialHash,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> lastUsedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.lastUsedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> revokedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.revokedAt,
        value,
      );
}

class PatientDeviceCredentialTable extends _i1.Table<_i1.UuidValue?> {
  PatientDeviceCredentialTable({super.tableRelation})
    : super(tableName: 'patient_device_credentials') {
    updateTable = PatientDeviceCredentialUpdateTable(this);
    patientId = _i1.ColumnUuid(
      'patientId',
      this,
    );
    deviceId = _i1.ColumnString(
      'deviceId',
      this,
    );
    credentialHash = _i1.ColumnString(
      'credentialHash',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    lastUsedAt = _i1.ColumnDateTime(
      'lastUsedAt',
      this,
    );
    revokedAt = _i1.ColumnDateTime(
      'revokedAt',
      this,
    );
  }

  late final PatientDeviceCredentialUpdateTable updateTable;

  /// Dono da credencial — o identificador pseudônimo do participante
  /// (`users.id`/`patients.id`; sem CPF desde C-05).
  late final _i1.ColumnUuid patientId;

  /// UUID minúsculo de instalação, validado em `isDeviceIdFormat`. Único:
  /// um aparelho não pode ter duas credenciais vivas, e a reemissão grava
  /// uma linha nova com outro deviceId (C-12).
  late final _i1.ColumnString deviceId;

  /// SHA-256 (hex) de `sinalacs-pdc-v1:<segredo>` — o segredo tem 256 bits
  /// de entropia, então hash rápido basta; nunca em claro.
  late final _i1.ColumnString credentialHash;

  late final _i1.ColumnDateTime createdAt;

  /// Atualizado a cada `auth.loginDevice` bem-sucedido (LGPD-RT06: retenção
  /// do acesso do titular).
  late final _i1.ColumnDateTime lastUsedAt;

  /// `null` = credencial viva. Preenchido pela C-12 (novo convite revoga a
  /// credencial anterior do mesmo paciente).
  late final _i1.ColumnDateTime revokedAt;

  @override
  List<_i1.Column> get columns => [
    id,
    patientId,
    deviceId,
    credentialHash,
    createdAt,
    lastUsedAt,
    revokedAt,
  ];
}

class PatientDeviceCredentialInclude extends _i1.IncludeObject {
  PatientDeviceCredentialInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => PatientDeviceCredential.t;
}

class PatientDeviceCredentialIncludeList extends _i1.IncludeList {
  PatientDeviceCredentialIncludeList._({
    _i1.WhereExpressionBuilder<PatientDeviceCredentialTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(PatientDeviceCredential.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => PatientDeviceCredential.t;
}

class PatientDeviceCredentialRepository {
  const PatientDeviceCredentialRepository._();

  /// Returns a list of [PatientDeviceCredential]s matching the given query parameters.
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
  Future<List<PatientDeviceCredential>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<PatientDeviceCredentialTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PatientDeviceCredentialTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PatientDeviceCredentialTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<PatientDeviceCredential>(
      where: where?.call(PatientDeviceCredential.t),
      orderBy: orderBy?.call(PatientDeviceCredential.t),
      orderByList: orderByList?.call(PatientDeviceCredential.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [PatientDeviceCredential] matching the given query parameters.
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
  Future<PatientDeviceCredential?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<PatientDeviceCredentialTable>? where,
    int? offset,
    _i1.OrderByBuilder<PatientDeviceCredentialTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PatientDeviceCredentialTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<PatientDeviceCredential>(
      where: where?.call(PatientDeviceCredential.t),
      orderBy: orderBy?.call(PatientDeviceCredential.t),
      orderByList: orderByList?.call(PatientDeviceCredential.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [PatientDeviceCredential] by its [id] or null if no such row exists.
  Future<PatientDeviceCredential?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<PatientDeviceCredential>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [PatientDeviceCredential]s in the list and returns the inserted rows.
  ///
  /// The returned [PatientDeviceCredential]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<PatientDeviceCredential>> insert(
    _i1.DatabaseSession session,
    List<PatientDeviceCredential> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<PatientDeviceCredential>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [PatientDeviceCredential] and returns the inserted row.
  ///
  /// The returned [PatientDeviceCredential] will have its `id` field set.
  Future<PatientDeviceCredential> insertRow(
    _i1.DatabaseSession session,
    PatientDeviceCredential row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<PatientDeviceCredential>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [PatientDeviceCredential]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<PatientDeviceCredential>> update(
    _i1.DatabaseSession session,
    List<PatientDeviceCredential> rows, {
    _i1.ColumnSelections<PatientDeviceCredentialTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<PatientDeviceCredential>(
      rows,
      columns: columns?.call(PatientDeviceCredential.t),
      transaction: transaction,
    );
  }

  /// Updates a single [PatientDeviceCredential]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<PatientDeviceCredential> updateRow(
    _i1.DatabaseSession session,
    PatientDeviceCredential row, {
    _i1.ColumnSelections<PatientDeviceCredentialTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<PatientDeviceCredential>(
      row,
      columns: columns?.call(PatientDeviceCredential.t),
      transaction: transaction,
    );
  }

  /// Updates a single [PatientDeviceCredential] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<PatientDeviceCredential?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<PatientDeviceCredentialUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<PatientDeviceCredential>(
      id,
      columnValues: columnValues(PatientDeviceCredential.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [PatientDeviceCredential]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<PatientDeviceCredential>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<PatientDeviceCredentialUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<PatientDeviceCredentialTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PatientDeviceCredentialTable>? orderBy,
    _i1.OrderByListBuilder<PatientDeviceCredentialTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<PatientDeviceCredential>(
      columnValues: columnValues(PatientDeviceCredential.t.updateTable),
      where: where(PatientDeviceCredential.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PatientDeviceCredential.t),
      orderByList: orderByList?.call(PatientDeviceCredential.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [PatientDeviceCredential]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<PatientDeviceCredential>> delete(
    _i1.DatabaseSession session,
    List<PatientDeviceCredential> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<PatientDeviceCredential>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [PatientDeviceCredential].
  Future<PatientDeviceCredential> deleteRow(
    _i1.DatabaseSession session,
    PatientDeviceCredential row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<PatientDeviceCredential>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<PatientDeviceCredential>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<PatientDeviceCredentialTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<PatientDeviceCredential>(
      where: where(PatientDeviceCredential.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<PatientDeviceCredentialTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<PatientDeviceCredential>(
      where: where?.call(PatientDeviceCredential.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [PatientDeviceCredential] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<PatientDeviceCredentialTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<PatientDeviceCredential>(
      where: where(PatientDeviceCredential.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
