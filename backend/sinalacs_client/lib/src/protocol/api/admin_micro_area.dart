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

/// Microárea e o ACS vinculado, para a listagem somente leitura do backoffice.
abstract class AdminMicroArea implements _i1.SerializableModel {
  AdminMicroArea._({
    required this.id,
    required this.name,
    required this.acsName,
    required this.acsEnrollmentId,
    required this.acsActive,
  });

  factory AdminMicroArea({
    required String id,
    required String name,
    required String acsName,
    required String acsEnrollmentId,
    required bool acsActive,
  }) = _AdminMicroAreaImpl;

  factory AdminMicroArea.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminMicroArea(
      id: jsonSerialization['id'] as String,
      name: jsonSerialization['name'] as String,
      acsName: jsonSerialization['acsName'] as String,
      acsEnrollmentId: jsonSerialization['acsEnrollmentId'] as String,
      acsActive: _i1.BoolJsonExtension.fromJson(jsonSerialization['acsActive']),
    );
  }

  String id;

  String name;

  String acsName;

  String acsEnrollmentId;

  bool acsActive;

  /// Returns a shallow copy of this [AdminMicroArea]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminMicroArea copyWith({
    String? id,
    String? name,
    String? acsName,
    String? acsEnrollmentId,
    bool? acsActive,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminMicroArea',
      'id': id,
      'name': name,
      'acsName': acsName,
      'acsEnrollmentId': acsEnrollmentId,
      'acsActive': acsActive,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminMicroAreaImpl extends AdminMicroArea {
  _AdminMicroAreaImpl({
    required String id,
    required String name,
    required String acsName,
    required String acsEnrollmentId,
    required bool acsActive,
  }) : super._(
         id: id,
         name: name,
         acsName: acsName,
         acsEnrollmentId: acsEnrollmentId,
         acsActive: acsActive,
       );

  /// Returns a shallow copy of this [AdminMicroArea]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminMicroArea copyWith({
    String? id,
    String? name,
    String? acsName,
    String? acsEnrollmentId,
    bool? acsActive,
  }) {
    return AdminMicroArea(
      id: id ?? this.id,
      name: name ?? this.name,
      acsName: acsName ?? this.acsName,
      acsEnrollmentId: acsEnrollmentId ?? this.acsEnrollmentId,
      acsActive: acsActive ?? this.acsActive,
    );
  }
}
