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

/// Unidade Básica de Saúde.
abstract class Ubs
    implements _i1.TableRow<_i1.UuidValue?>, _i1.ProtocolSerialization {
  Ubs._({
    this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
  });

  factory Ubs({
    _i1.UuidValue? id,
    required String name,
    required String address,
    required String city,
    required String state,
  }) = _UbsImpl;

  factory Ubs.fromJson(Map<String, dynamic> jsonSerialization) {
    return Ubs(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      name: jsonSerialization['name'] as String,
      address: jsonSerialization['address'] as String,
      city: jsonSerialization['city'] as String,
      state: jsonSerialization['state'] as String,
    );
  }

  static final t = UbsTable();

  static const db = UbsRepository._();

  @override
  _i1.UuidValue? id;

  String name;

  String address;

  String city;

  String state;

  @override
  _i1.Table<_i1.UuidValue?> get table => t;

  /// Returns a shallow copy of this [Ubs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Ubs copyWith({
    _i1.UuidValue? id,
    String? name,
    String? address,
    String? city,
    String? state,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Ubs',
      if (id != null) 'id': id?.toJson(),
      'name': name,
      'address': address,
      'city': city,
      'state': state,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Ubs',
      if (id != null) 'id': id?.toJson(),
      'name': name,
      'address': address,
      'city': city,
      'state': state,
    };
  }

  static UbsInclude include() {
    return UbsInclude._();
  }

  static UbsIncludeList includeList({
    _i1.WhereExpressionBuilder<UbsTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<UbsTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<UbsTable>? orderByList,
    UbsInclude? include,
  }) {
    return UbsIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Ubs.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(Ubs.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _UbsImpl extends Ubs {
  _UbsImpl({
    _i1.UuidValue? id,
    required String name,
    required String address,
    required String city,
    required String state,
  }) : super._(
         id: id,
         name: name,
         address: address,
         city: city,
         state: state,
       );

  /// Returns a shallow copy of this [Ubs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Ubs copyWith({
    Object? id = _Undefined,
    String? name,
    String? address,
    String? city,
    String? state,
  }) {
    return Ubs(
      id: id is _i1.UuidValue? ? id : this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
    );
  }
}

class UbsUpdateTable extends _i1.UpdateTable<UbsTable> {
  UbsUpdateTable(super.table);

  _i1.ColumnValue<String, String> name(String value) => _i1.ColumnValue(
    table.name,
    value,
  );

  _i1.ColumnValue<String, String> address(String value) => _i1.ColumnValue(
    table.address,
    value,
  );

  _i1.ColumnValue<String, String> city(String value) => _i1.ColumnValue(
    table.city,
    value,
  );

  _i1.ColumnValue<String, String> state(String value) => _i1.ColumnValue(
    table.state,
    value,
  );
}

class UbsTable extends _i1.Table<_i1.UuidValue?> {
  UbsTable({super.tableRelation}) : super(tableName: 'ubs') {
    updateTable = UbsUpdateTable(this);
    name = _i1.ColumnString(
      'name',
      this,
    );
    address = _i1.ColumnString(
      'address',
      this,
    );
    city = _i1.ColumnString(
      'city',
      this,
    );
    state = _i1.ColumnString(
      'state',
      this,
    );
  }

  late final UbsUpdateTable updateTable;

  late final _i1.ColumnString name;

  late final _i1.ColumnString address;

  late final _i1.ColumnString city;

  late final _i1.ColumnString state;

  @override
  List<_i1.Column> get columns => [
    id,
    name,
    address,
    city,
    state,
  ];
}

class UbsInclude extends _i1.IncludeObject {
  UbsInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Ubs.t;
}

class UbsIncludeList extends _i1.IncludeList {
  UbsIncludeList._({
    _i1.WhereExpressionBuilder<UbsTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Ubs.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<_i1.UuidValue?> get table => Ubs.t;
}

class UbsRepository {
  const UbsRepository._();

  /// Returns a list of [Ubs]s matching the given query parameters.
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
  Future<List<Ubs>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<UbsTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<UbsTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<UbsTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Ubs>(
      where: where?.call(Ubs.t),
      orderBy: orderBy?.call(Ubs.t),
      orderByList: orderByList?.call(Ubs.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Ubs] matching the given query parameters.
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
  Future<Ubs?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<UbsTable>? where,
    int? offset,
    _i1.OrderByBuilder<UbsTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<UbsTable>? orderByList,
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Ubs>(
      where: where?.call(Ubs.t),
      orderBy: orderBy?.call(Ubs.t),
      orderByList: orderByList?.call(Ubs.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Ubs] by its [id] or null if no such row exists.
  Future<Ubs?> findById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    _i1.Transaction? transaction,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Ubs>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Ubs]s in the list and returns the inserted rows.
  ///
  /// The returned [Ubs]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<Ubs>> insert(
    _i1.DatabaseSession session,
    List<Ubs> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<Ubs>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [Ubs] and returns the inserted row.
  ///
  /// The returned [Ubs] will have its `id` field set.
  Future<Ubs> insertRow(
    _i1.DatabaseSession session,
    Ubs row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<Ubs>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [Ubs]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<Ubs>> update(
    _i1.DatabaseSession session,
    List<Ubs> rows, {
    _i1.ColumnSelections<UbsTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<Ubs>(
      rows,
      columns: columns?.call(Ubs.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Ubs]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Ubs> updateRow(
    _i1.DatabaseSession session,
    Ubs row, {
    _i1.ColumnSelections<UbsTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<Ubs>(
      row,
      columns: columns?.call(Ubs.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Ubs] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Ubs?> updateById(
    _i1.DatabaseSession session,
    _i1.UuidValue id, {
    required _i1.ColumnValueListBuilder<UbsUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<Ubs>(
      id,
      columnValues: columnValues(Ubs.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Ubs]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<Ubs>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<UbsUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<UbsTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<UbsTable>? orderBy,
    _i1.OrderByListBuilder<UbsTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<Ubs>(
      columnValues: columnValues(Ubs.t.updateTable),
      where: where(Ubs.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Ubs.t),
      orderByList: orderByList?.call(Ubs.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [Ubs]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<Ubs>> delete(
    _i1.DatabaseSession session,
    List<Ubs> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<Ubs>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [Ubs].
  Future<Ubs> deleteRow(
    _i1.DatabaseSession session,
    Ubs row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Ubs>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<Ubs>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<UbsTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<Ubs>(
      where: where(Ubs.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<UbsTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<Ubs>(
      where: where?.call(Ubs.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Ubs] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<UbsTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Ubs>(
      where: where(Ubs.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
