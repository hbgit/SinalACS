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
import 'enums/device_cert_revocation_reason.dart' as _i2;

/// Certificado de cliente MQTT emitido para um aparelho do ACS (#94). Em regra
/// um ativo por aparelho: a emissão nova revoga a anterior (`renewed`); duas
/// emissões concorrentes do mesmo aparelho podem coexistir, e a revogação por
/// aparelho revoga todas.
///
/// Só identificadores técnicos, sem dado pessoal além do `userId` do ACS (o
/// profissional, não o titular): o `deviceId` é o UUID aleatório da
/// instalação, a `serial` são 128 bits com versão/variante de UUID v4 fixos
/// (122 aleatórios) em hex minúsculo com 32 dígitos, e a impressão digital é o SHA-256 do DER da folha. O certificado
/// em si não é guardado: a revogação só precisa da serial.
///
/// Retenção: até `notAfter` + 30 dias (a CRL só lista as não vencidas);
/// o expurgo é pendência (`PROGRESS.md`).
abstract class DeviceCertificate
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  DeviceCertificate._({
    this.id,
    required this.userId,
    required this.deviceId,
    required this.microAreaId,
    required this.serial,
    required this.fingerprintSha256,
    required this.notBefore,
    required this.notAfter,
    required this.issuedAt,
    this.revokedAt,
    this.revocationReason,
  });

  factory DeviceCertificate({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String deviceId,
    required _i1.UuidValue microAreaId,
    required String serial,
    required String fingerprintSha256,
    required DateTime notBefore,
    required DateTime notAfter,
    required DateTime issuedAt,
    DateTime? revokedAt,
    _i2.DeviceCertRevocationReason? revocationReason,
  }) = _DeviceCertificateImpl;

  factory DeviceCertificate.fromJson(Map<String, dynamic> jsonSerialization) {
    return DeviceCertificate(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      userId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['userId']),
      deviceId: jsonSerialization['deviceId'] as String,
      microAreaId: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['microAreaId'],
      ),
      serial: jsonSerialization['serial'] as String,
      fingerprintSha256: jsonSerialization['fingerprintSha256'] as String,
      notBefore: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['notBefore'],
      ),
      notAfter: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['notAfter'],
      ),
      issuedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['issuedAt'],
      ),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
      revocationReason: jsonSerialization['revocationReason'] == null
          ? null
          : _i2.DeviceCertRevocationReason.fromJson(
              (jsonSerialization['revocationReason'] as String),
            ),
    );
  }

  static final t = DeviceCertificateTable();

  static const db = DeviceCertificateRepository._();

  @override
  _i1.UuidValue? id;

  /// O ACS da sessão que pediu a emissão.
  _i1.UuidValue userId;

  /// Instalação que recebeu o certificado (o `deviceId` do token).
  String deviceId;

  /// A microárea da conta relida do banco na emissão (igual à do token, ou a
  /// emissão é recusada); é o CN da folha.
  _i1.UuidValue microAreaId;

  String serial;

  String fingerprintSha256;

  DateTime notBefore;

  DateTime notAfter;

  DateTime issuedAt;

  /// `null` = vigente.
  DateTime? revokedAt;

  _i2.DeviceCertRevocationReason? revocationReason;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [DeviceCertificate]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCertificate copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? userId,
    String? deviceId,
    _i1.UuidValue? microAreaId,
    String? serial,
    String? fingerprintSha256,
    DateTime? notBefore,
    DateTime? notAfter,
    DateTime? issuedAt,
    DateTime? revokedAt,
    _i2.DeviceCertRevocationReason? revocationReason,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCertificate',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'deviceId': deviceId,
      'microAreaId': microAreaId.toJson(),
      'serial': serial,
      'fingerprintSha256': fingerprintSha256,
      'notBefore': notBefore.toJson(),
      'notAfter': notAfter.toJson(),
      'issuedAt': issuedAt.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
      if (revocationReason != null)
        'revocationReason': revocationReason?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceCertificate',
      if (id != null) 'id': id?.toJson(),
      'userId': userId.toJson(),
      'deviceId': deviceId,
      'microAreaId': microAreaId.toJson(),
      'serial': serial,
      'fingerprintSha256': fingerprintSha256,
      'notBefore': notBefore.toJson(),
      'notAfter': notAfter.toJson(),
      'issuedAt': issuedAt.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
      if (revocationReason != null)
        'revocationReason': revocationReason?.toJson(),
    };
  }

  static DeviceCertificateInclude include() {
    return DeviceCertificateInclude._();
  }

  static DeviceCertificateIncludeList includeList({
    _i1.WhereExpressionBuilder<DeviceCertificateTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceCertificateTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceCertificateTable>? orderByList,
    DeviceCertificateInclude? include,
  }) {
    return DeviceCertificateIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DeviceCertificate.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(DeviceCertificate.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DeviceCertificateImpl extends DeviceCertificate {
  _DeviceCertificateImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue userId,
    required String deviceId,
    required _i1.UuidValue microAreaId,
    required String serial,
    required String fingerprintSha256,
    required DateTime notBefore,
    required DateTime notAfter,
    required DateTime issuedAt,
    DateTime? revokedAt,
    _i2.DeviceCertRevocationReason? revocationReason,
  }) : super._(
         id: id,
         userId: userId,
         deviceId: deviceId,
         microAreaId: microAreaId,
         serial: serial,
         fingerprintSha256: fingerprintSha256,
         notBefore: notBefore,
         notAfter: notAfter,
         issuedAt: issuedAt,
         revokedAt: revokedAt,
         revocationReason: revocationReason,
       );

  /// Returns a shallow copy of this [DeviceCertificate]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCertificate copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? userId,
    String? deviceId,
    _i1.UuidValue? microAreaId,
    String? serial,
    String? fingerprintSha256,
    DateTime? notBefore,
    DateTime? notAfter,
    DateTime? issuedAt,
    Object? revokedAt = _Undefined,
    Object? revocationReason = _Undefined,
  }) {
    return DeviceCertificate(
      id: id is _i1.UuidValue? ? id : this.id,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      microAreaId: microAreaId ?? this.microAreaId,
      serial: serial ?? this.serial,
      fingerprintSha256: fingerprintSha256 ?? this.fingerprintSha256,
      notBefore: notBefore ?? this.notBefore,
      notAfter: notAfter ?? this.notAfter,
      issuedAt: issuedAt ?? this.issuedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
      revocationReason: revocationReason is _i2.DeviceCertRevocationReason?
          ? revocationReason
          : this.revocationReason,
    );
  }
}

class DeviceCertificateUpdateTable
    extends _i1.UpdateTable<DeviceCertificateTable> {
  DeviceCertificateUpdateTable(super.table);

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> userId(_i1.UuidValue value) =>
      _i1.ColumnValue(
        table.userId,
        value,
      );

  _i1.ColumnValue<String, String> deviceId(String value) => _i1.ColumnValue(
    table.deviceId,
    value,
  );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> microAreaId(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.microAreaId,
    value,
  );

  _i1.ColumnValue<String, String> serial(String value) => _i1.ColumnValue(
    table.serial,
    value,
  );

  _i1.ColumnValue<String, String> fingerprintSha256(String value) =>
      _i1.ColumnValue(
        table.fingerprintSha256,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> notBefore(DateTime value) =>
      _i1.ColumnValue(
        table.notBefore,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> notAfter(DateTime value) =>
      _i1.ColumnValue(
        table.notAfter,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> issuedAt(DateTime value) =>
      _i1.ColumnValue(
        table.issuedAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> revokedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.revokedAt,
        value,
      );

  _i1.ColumnValue<
    _i2.DeviceCertRevocationReason,
    _i2.DeviceCertRevocationReason
  >
  revocationReason(_i2.DeviceCertRevocationReason? value) => _i1.ColumnValue(
    table.revocationReason,
    value,
  );
}

class DeviceCertificateTable extends _i1.Table<_i1.UuidValue?> {
  DeviceCertificateTable({super.tableRelation})
    : super(tableName: 'device_certificates') {
    updateTable = DeviceCertificateUpdateTable(this);
    userId = _i1.ColumnUuid(
      'userId',
      this,
    );
    deviceId = _i1.ColumnString(
      'deviceId',
      this,
    );
    microAreaId = _i1.ColumnUuid(
      'microAreaId',
      this,
    );
    serial = _i1.ColumnString(
      'serial',
      this,
    );
    fingerprintSha256 = _i1.ColumnString(
      'fingerprintSha256',
      this,
    );
    notBefore = _i1.ColumnDateTime(
      'notBefore',
      this,
    );
    notAfter = _i1.ColumnDateTime(
      'notAfter',
      this,
    );
    issuedAt = _i1.ColumnDateTime(
      'issuedAt',
      this,
    );
    revokedAt = _i1.ColumnDateTime(
      'revokedAt',
      this,
    );
    revocationReason = _i1.ColumnEnum(
      'revocationReason',
      this,
      _i1.EnumSerialization.byName,
    );
  }

  late final DeviceCertificateUpdateTable updateTable;

  /// O ACS da sessão que pediu a emissão.
  late final _i1.ColumnUuid userId;

  /// Instalação que recebeu o certificado (o `deviceId` do token).
  late final _i1.ColumnString deviceId;

  /// A microárea da conta relida do banco na emissão (igual à do token, ou a
  /// emissão é recusada); é o CN da folha.
  late final _i1.ColumnUuid microAreaId;

  late final _i1.ColumnString serial;

  late final _i1.ColumnString fingerprintSha256;

  late final _i1.ColumnDateTime notBefore;

  late final _i1.ColumnDateTime notAfter;

  late final _i1.ColumnDateTime issuedAt;

  /// `null` = vigente.
  late final _i1.ColumnDateTime revokedAt;

  late final _i1.ColumnEnum<_i2.DeviceCertRevocationReason> revocationReason;

  @override
  List<_i1.Column> get columns => [
    id,
    userId,
    deviceId,
    microAreaId,
    serial,
    fingerprintSha256,
    notBefore,
    notAfter,
    issuedAt,
    revokedAt,
    revocationReason,
  ];
}

class DeviceCertificateInclude extends _i1.IncludeObject {
  DeviceCertificateInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => DeviceCertificate.t;
}

class DeviceCertificateIncludeList extends _i1.IncludeList {
  DeviceCertificateIncludeList._({
    _i1.WhereExpressionBuilder<DeviceCertificateTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(DeviceCertificate.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => DeviceCertificate.t;
}

class DeviceCertificateRepository {
  const DeviceCertificateRepository._();

  /// Returns a list of [DeviceCertificate]s matching the given query parameters.
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
  Future<List<DeviceCertificate>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceCertificateTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceCertificateTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceCertificateTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<DeviceCertificate>(
      where: where?.call(DeviceCertificate.t),
      orderBy: orderBy?.call(DeviceCertificate.t),
      orderByList: orderByList?.call(DeviceCertificate.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [DeviceCertificate] matching the given query parameters.
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
  Future<DeviceCertificate?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceCertificateTable>? where,
    int? offset,
    _i1.OrderByBuilder<DeviceCertificateTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<DeviceCertificateTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<DeviceCertificate>(
      where: where?.call(DeviceCertificate.t),
      orderBy: orderBy?.call(DeviceCertificate.t),
      orderByList: orderByList?.call(DeviceCertificate.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [DeviceCertificate] by its [id] or null if no such row exists.
  Future<DeviceCertificate?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<DeviceCertificate>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [DeviceCertificate]s in the list and returns the inserted rows.
  ///
  /// The returned [DeviceCertificate]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<DeviceCertificate>> insert(
    _i1.DatabaseSession session,
    List<DeviceCertificate> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<DeviceCertificate>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [DeviceCertificate] and returns the inserted row.
  ///
  /// The returned [DeviceCertificate] will have its `id` field set.
  Future<DeviceCertificate> insertRow(
    _i1.DatabaseSession session,
    DeviceCertificate row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<DeviceCertificate>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [DeviceCertificate]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<DeviceCertificate>> update(
    _i1.DatabaseSession session,
    List<DeviceCertificate> rows, {
    _i1.ColumnSelections<DeviceCertificateTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<DeviceCertificate>(
      rows,
      columns: columns?.call(DeviceCertificate.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DeviceCertificate]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<DeviceCertificate> updateRow(
    _i1.DatabaseSession session,
    DeviceCertificate row, {
    _i1.ColumnSelections<DeviceCertificateTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<DeviceCertificate>(
      row,
      columns: columns?.call(DeviceCertificate.t),
      transaction: transaction,
    );
  }

  /// Updates a single [DeviceCertificate] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<DeviceCertificate?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<DeviceCertificateUpdateTable>
    columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<DeviceCertificate>(
      id,
      columnValues: columnValues(DeviceCertificate.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [DeviceCertificate]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<DeviceCertificate>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<DeviceCertificateUpdateTable>
    columnValues,
    required _i1.WhereExpressionBuilder<DeviceCertificateTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<DeviceCertificateTable>? orderBy,
    _i1.OrderByListBuilder<DeviceCertificateTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<DeviceCertificate>(
      columnValues: columnValues(DeviceCertificate.t.updateTable),
      where: where(DeviceCertificate.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(DeviceCertificate.t),
      orderByList: orderByList?.call(DeviceCertificate.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [DeviceCertificate]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<DeviceCertificate>> delete(
    _i1.DatabaseSession session,
    List<DeviceCertificate> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<DeviceCertificate>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [DeviceCertificate].
  Future<DeviceCertificate> deleteRow(
    _i1.DatabaseSession session,
    DeviceCertificate row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<DeviceCertificate>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<DeviceCertificate>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DeviceCertificateTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<DeviceCertificate>(
      where: where(DeviceCertificate.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<DeviceCertificateTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<DeviceCertificate>(
      where: where?.call(DeviceCertificate.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [DeviceCertificate] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<DeviceCertificateTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<DeviceCertificate>(
      where: where(DeviceCertificate.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
