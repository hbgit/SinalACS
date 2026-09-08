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

/// Microárea: a unidade de territorialização que delimita o acesso do ACS.
abstract class MicroArea implements _i1.SerializableModel {
  MicroArea._({
    this.id,
    required this.name,
    required this.ubsId,
    required this.geoJsonBoundary,
  });

  factory MicroArea({
    _i1.UuidValue? id,
    required String name,
    required _i1.UuidValue ubsId,
    required String geoJsonBoundary,
  }) = _MicroAreaImpl;

  factory MicroArea.fromJson(Map<String, dynamic> jsonSerialization) {
    return MicroArea(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      name: jsonSerialization['name'] as String,
      ubsId: _i1.UuidValueJsonExtension.fromJson(jsonSerialization['ubsId']),
      geoJsonBoundary: jsonSerialization['geoJsonBoundary'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String name;

  _i1.UuidValue ubsId;

  String geoJsonBoundary;

  /// Returns a shallow copy of this [MicroArea]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  MicroArea copyWith({
    _i1.UuidValue? id,
    String? name,
    _i1.UuidValue? ubsId,
    String? geoJsonBoundary,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MicroArea',
      if (id != null) 'id': id?.toJson(),
      'name': name,
      'ubsId': ubsId.toJson(),
      'geoJsonBoundary': geoJsonBoundary,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MicroAreaImpl extends MicroArea {
  _MicroAreaImpl({
    _i1.UuidValue? id,
    required String name,
    required _i1.UuidValue ubsId,
    required String geoJsonBoundary,
  }) : super._(
         id: id,
         name: name,
         ubsId: ubsId,
         geoJsonBoundary: geoJsonBoundary,
       );

  /// Returns a shallow copy of this [MicroArea]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  MicroArea copyWith({
    Object? id = _Undefined,
    String? name,
    _i1.UuidValue? ubsId,
    String? geoJsonBoundary,
  }) {
    return MicroArea(
      id: id is _i1.UuidValue? ? id : this.id,
      name: name ?? this.name,
      ubsId: ubsId ?? this.ubsId,
      geoJsonBoundary: geoJsonBoundary ?? this.geoJsonBoundary,
    );
  }
}
