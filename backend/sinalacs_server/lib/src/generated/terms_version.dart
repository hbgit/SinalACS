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

/// Versão dos termos anunciada ao paciente (LGPD-RF18, #46). O TEXTO jurídico
/// não fica aqui: vive no app do paciente. Aqui só o anúncio e a revisão.
abstract class TermsVersion
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  TermsVersion._({
    this.id,
    required this.version,
    required this.summary,
    required this.effectiveFrom,
    required this.createdBy,
    required this.createdAt,
    this.legallyReviewedAt,
    this.legallyReviewedBy,
    this.publishedAt,
    this.publishedBy,
  });

  factory TermsVersion({
    _i1.UuidValue? id,
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required _i1.UuidValue createdBy,
    required DateTime createdAt,
    DateTime? legallyReviewedAt,
    _i1.UuidValue? legallyReviewedBy,
    DateTime? publishedAt,
    _i1.UuidValue? publishedBy,
  }) = _TermsVersionImpl;

  factory TermsVersion.fromJson(Map<String, dynamic> jsonSerialization) {
    return TermsVersion(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      version: jsonSerialization['version'] as String,
      summary: jsonSerialization['summary'] as String,
      effectiveFrom: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['effectiveFrom'],
      ),
      createdBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['createdBy'],
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      legallyReviewedAt: jsonSerialization['legallyReviewedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['legallyReviewedAt'],
            ),
      legallyReviewedBy: jsonSerialization['legallyReviewedBy'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['legallyReviewedBy'],
            ),
      publishedAt: jsonSerialization['publishedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['publishedAt'],
            ),
      publishedBy: jsonSerialization['publishedBy'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['publishedBy'],
            ),
    );
  }

  static final t = TermsVersionTable();

  static const db = TermsVersionRepository._();

  @override
  _i1.UuidValue? id;

  String version;

  String summary;

  DateTime effectiveFrom;

  _i1.UuidValue createdBy;

  DateTime createdAt;

  DateTime? legallyReviewedAt;

  _i1.UuidValue? legallyReviewedBy;

  DateTime? publishedAt;

  _i1.UuidValue? publishedBy;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [TermsVersion]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TermsVersion copyWith({
    _i1.UuidValue? id,
    String? version,
    String? summary,
    DateTime? effectiveFrom,
    _i1.UuidValue? createdBy,
    DateTime? createdAt,
    DateTime? legallyReviewedAt,
    _i1.UuidValue? legallyReviewedBy,
    DateTime? publishedAt,
    _i1.UuidValue? publishedBy,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TermsVersion',
      if (id != null) 'id': id?.toJson(),
      'version': version,
      'summary': summary,
      'effectiveFrom': effectiveFrom.toJson(),
      'createdBy': createdBy.toJson(),
      'createdAt': createdAt.toJson(),
      if (legallyReviewedAt != null)
        'legallyReviewedAt': legallyReviewedAt?.toJson(),
      if (legallyReviewedBy != null)
        'legallyReviewedBy': legallyReviewedBy?.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
      if (publishedBy != null) 'publishedBy': publishedBy?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TermsVersion',
      if (id != null) 'id': id?.toJson(),
      'version': version,
      'summary': summary,
      'effectiveFrom': effectiveFrom.toJson(),
      'createdBy': createdBy.toJson(),
      'createdAt': createdAt.toJson(),
      if (legallyReviewedAt != null)
        'legallyReviewedAt': legallyReviewedAt?.toJson(),
      if (legallyReviewedBy != null)
        'legallyReviewedBy': legallyReviewedBy?.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
      if (publishedBy != null) 'publishedBy': publishedBy?.toJson(),
    };
  }

  static TermsVersionInclude include() {
    return TermsVersionInclude._();
  }

  static TermsVersionIncludeList includeList({
    _i1.WhereExpressionBuilder<TermsVersionTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TermsVersionTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TermsVersionTable>? orderByList,
    TermsVersionInclude? include,
  }) {
    return TermsVersionIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(TermsVersion.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(TermsVersion.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TermsVersionImpl extends TermsVersion {
  _TermsVersionImpl({
    _i1.UuidValue? id,
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required _i1.UuidValue createdBy,
    required DateTime createdAt,
    DateTime? legallyReviewedAt,
    _i1.UuidValue? legallyReviewedBy,
    DateTime? publishedAt,
    _i1.UuidValue? publishedBy,
  }) : super._(
         id: id,
         version: version,
         summary: summary,
         effectiveFrom: effectiveFrom,
         createdBy: createdBy,
         createdAt: createdAt,
         legallyReviewedAt: legallyReviewedAt,
         legallyReviewedBy: legallyReviewedBy,
         publishedAt: publishedAt,
         publishedBy: publishedBy,
       );

  /// Returns a shallow copy of this [TermsVersion]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TermsVersion copyWith({
    Object? id = _Undefined,
    String? version,
    String? summary,
    DateTime? effectiveFrom,
    _i1.UuidValue? createdBy,
    DateTime? createdAt,
    Object? legallyReviewedAt = _Undefined,
    Object? legallyReviewedBy = _Undefined,
    Object? publishedAt = _Undefined,
    Object? publishedBy = _Undefined,
  }) {
    return TermsVersion(
      id: id is _i1.UuidValue? ? id : this.id,
      version: version ?? this.version,
      summary: summary ?? this.summary,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      legallyReviewedAt: legallyReviewedAt is DateTime?
          ? legallyReviewedAt
          : this.legallyReviewedAt,
      legallyReviewedBy: legallyReviewedBy is _i1.UuidValue?
          ? legallyReviewedBy
          : this.legallyReviewedBy,
      publishedAt: publishedAt is DateTime? ? publishedAt : this.publishedAt,
      publishedBy: publishedBy is _i1.UuidValue?
          ? publishedBy
          : this.publishedBy,
    );
  }
}

class TermsVersionUpdateTable extends _i1.UpdateTable<TermsVersionTable> {
  TermsVersionUpdateTable(super.table);

  _i1.ColumnValue<String, String> version(String value) => _i1.ColumnValue(
    table.version,
    value,
  );

  _i1.ColumnValue<String, String> summary(String value) => _i1.ColumnValue(
    table.summary,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> effectiveFrom(DateTime value) =>
      _i1.ColumnValue(
        table.effectiveFrom,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> createdBy(
    _i1.UuidValue value,
  ) => _i1.ColumnValue(
    table.createdBy,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _i1.ColumnValue(
        table.createdAt,
        value,
      );

  _i1.ColumnValue<DateTime, DateTime> legallyReviewedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.legallyReviewedAt,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> legallyReviewedBy(
    _i1.UuidValue? value,
  ) => _i1.ColumnValue(
    table.legallyReviewedBy,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> publishedAt(DateTime? value) =>
      _i1.ColumnValue(
        table.publishedAt,
        value,
      );

  _i1.ColumnValue<_i1.UuidValue, _i1.UuidValue> publishedBy(
    _i1.UuidValue? value,
  ) => _i1.ColumnValue(
    table.publishedBy,
    value,
  );
}

class TermsVersionTable extends _i1.Table<_i1.UuidValue?> {
  TermsVersionTable({super.tableRelation})
    : super(tableName: 'terms_versions') {
    updateTable = TermsVersionUpdateTable(this);
    version = _i1.ColumnString(
      'version',
      this,
    );
    summary = _i1.ColumnString(
      'summary',
      this,
    );
    effectiveFrom = _i1.ColumnDateTime(
      'effectiveFrom',
      this,
    );
    createdBy = _i1.ColumnUuid(
      'createdBy',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
    legallyReviewedAt = _i1.ColumnDateTime(
      'legallyReviewedAt',
      this,
    );
    legallyReviewedBy = _i1.ColumnUuid(
      'legallyReviewedBy',
      this,
    );
    publishedAt = _i1.ColumnDateTime(
      'publishedAt',
      this,
    );
    publishedBy = _i1.ColumnUuid(
      'publishedBy',
      this,
    );
  }

  late final TermsVersionUpdateTable updateTable;

  late final _i1.ColumnString version;

  late final _i1.ColumnString summary;

  late final _i1.ColumnDateTime effectiveFrom;

  late final _i1.ColumnUuid createdBy;

  late final _i1.ColumnDateTime createdAt;

  late final _i1.ColumnDateTime legallyReviewedAt;

  late final _i1.ColumnUuid legallyReviewedBy;

  late final _i1.ColumnDateTime publishedAt;

  late final _i1.ColumnUuid publishedBy;

  @override
  List<_i1.Column> get columns => [
    id,
    version,
    summary,
    effectiveFrom,
    createdBy,
    createdAt,
    legallyReviewedAt,
    legallyReviewedBy,
    publishedAt,
    publishedBy,
  ];
}

class TermsVersionInclude extends _i1.IncludeObject {
  TermsVersionInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => TermsVersion.t;
}

class TermsVersionIncludeList extends _i1.IncludeList {
  TermsVersionIncludeList._({
    _i1.WhereExpressionBuilder<TermsVersionTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(TermsVersion.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => TermsVersion.t;
}

class TermsVersionRepository {
  const TermsVersionRepository._();

  /// Returns a list of [TermsVersion]s matching the given query parameters.
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
  Future<List<TermsVersion>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TermsVersionTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TermsVersionTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TermsVersionTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<TermsVersion>(
      where: where?.call(TermsVersion.t),
      orderBy: orderBy?.call(TermsVersion.t),
      orderByList: orderByList?.call(TermsVersion.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [TermsVersion] matching the given query parameters.
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
  Future<TermsVersion?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TermsVersionTable>? where,
    int? offset,
    _i1.OrderByBuilder<TermsVersionTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<TermsVersionTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<TermsVersion>(
      where: where?.call(TermsVersion.t),
      orderBy: orderBy?.call(TermsVersion.t),
      orderByList: orderByList?.call(TermsVersion.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [TermsVersion] by its [id] or null if no such row exists.
  Future<TermsVersion?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<TermsVersion>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [TermsVersion]s in the list and returns the inserted rows.
  ///
  /// The returned [TermsVersion]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<TermsVersion>> insert(
    _i1.DatabaseSession session,
    List<TermsVersion> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<TermsVersion>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [TermsVersion] and returns the inserted row.
  ///
  /// The returned [TermsVersion] will have its `id` field set.
  Future<TermsVersion> insertRow(
    _i1.DatabaseSession session,
    TermsVersion row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<TermsVersion>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [TermsVersion]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<TermsVersion>> update(
    _i1.DatabaseSession session,
    List<TermsVersion> rows, {
    _i1.ColumnSelections<TermsVersionTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<TermsVersion>(
      rows,
      columns: columns?.call(TermsVersion.t),
      transaction: transaction,
    );
  }

  /// Updates a single [TermsVersion]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<TermsVersion> updateRow(
    _i1.DatabaseSession session,
    TermsVersion row, {
    _i1.ColumnSelections<TermsVersionTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<TermsVersion>(
      row,
      columns: columns?.call(TermsVersion.t),
      transaction: transaction,
    );
  }

  /// Updates a single [TermsVersion] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<TermsVersion?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<TermsVersionUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<TermsVersion>(
      id,
      columnValues: columnValues(TermsVersion.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [TermsVersion]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<TermsVersion>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<TermsVersionUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<TermsVersionTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<TermsVersionTable>? orderBy,
    _i1.OrderByListBuilder<TermsVersionTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<TermsVersion>(
      columnValues: columnValues(TermsVersion.t.updateTable),
      where: where(TermsVersion.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(TermsVersion.t),
      orderByList: orderByList?.call(TermsVersion.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [TermsVersion]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<TermsVersion>> delete(
    _i1.DatabaseSession session,
    List<TermsVersion> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<TermsVersion>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [TermsVersion].
  Future<TermsVersion> deleteRow(
    _i1.DatabaseSession session,
    TermsVersion row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<TermsVersion>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<TermsVersion>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<TermsVersionTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<TermsVersion>(
      where: where(TermsVersion.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<TermsVersionTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<TermsVersion>(
      where: where?.call(TermsVersion.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [TermsVersion] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<TermsVersionTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<TermsVersion>(
      where: where(TermsVersion.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
