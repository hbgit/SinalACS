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

import 'package:serverpod_client/serverpod_client.dart' as _i1;

/// Contador da extensão `CRL Number` da CRL dos aparelhos (#94). Uma única
/// linha (`id = 1`), incrementada a cada publicação; começa em 1000, acima do
/// `01` da CRL inicial do `init.sh`, e sobrevive a reinícios. Sem dado pessoal.
abstract class DeviceCrlCounter implements _i1.SerializableModel {
  DeviceCrlCounter._({
    this.id,
    required this.lastNumber,
  });

  factory DeviceCrlCounter({
    int? id,
    required int lastNumber,
  }) = _DeviceCrlCounterImpl;

  factory DeviceCrlCounter.fromJson(Map<String, dynamic> jsonSerialization) {
    return DeviceCrlCounter(
      id: jsonSerialization['id'] as int?,
      lastNumber: jsonSerialization['lastNumber'] as int,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  int lastNumber;

  /// Returns a shallow copy of this [DeviceCrlCounter]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCrlCounter copyWith({
    int? id,
    int? lastNumber,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCrlCounter',
      if (id != null) 'id': id,
      'lastNumber': lastNumber,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _DeviceCrlCounterImpl extends DeviceCrlCounter {
  _DeviceCrlCounterImpl({
    int? id,
    required int lastNumber,
  }) : super._(
         id: id,
         lastNumber: lastNumber,
       );

  /// Returns a shallow copy of this [DeviceCrlCounter]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCrlCounter copyWith({
    Object? id = _Undefined,
    int? lastNumber,
  }) {
    return DeviceCrlCounter(
      id: id is int? ? id : this.id,
      lastNumber: lastNumber ?? this.lastNumber,
    );
  }
}
