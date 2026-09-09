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

/// Unidade Básica de Saúde.
abstract class Ubs implements _i1.SerializableModel {
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

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String name;

  String address;

  String city;

  String state;

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
