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
import '../enums/user_role.dart' as _i2;

/// Conta de equipe do backoffice (#43): identificação profissional, papel,
/// UBS e estado de acesso. Nunca inclui CPF, senha ou contato.
///
/// `ubsName` é nulo para o administrador (vê o sistema inteiro) e para o
/// coordenador ainda sem UBS — que é recusado em tudo até ter uma.
/// `mfaActive` tem a mesma leitura de `AdminAcs`: `totpEnabledAt` preenchido.
abstract class AdminStaff implements _i1.SerializableModel {
  AdminStaff._({
    required this.id,
    required this.name,
    required this.enrollmentId,
    required this.role,
    this.ubsName,
    required this.active,
    required this.mfaActive,
  });

  factory AdminStaff({
    required String id,
    required String name,
    required String enrollmentId,
    required _i2.UserRole role,
    String? ubsName,
    required bool active,
    required bool mfaActive,
  }) = _AdminStaffImpl;

  factory AdminStaff.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminStaff(
      id: jsonSerialization['id'] as String,
      name: jsonSerialization['name'] as String,
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      role: _i2.UserRole.fromJson((jsonSerialization['role'] as String)),
      ubsName: jsonSerialization['ubsName'] as String?,
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
      mfaActive: _i1.BoolJsonExtension.fromJson(jsonSerialization['mfaActive']),
    );
  }

  String id;

  String name;

  String enrollmentId;

  _i2.UserRole role;

  String? ubsName;

  bool active;

  bool mfaActive;

  /// Returns a shallow copy of this [AdminStaff]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminStaff copyWith({
    String? id,
    String? name,
    String? enrollmentId,
    _i2.UserRole? role,
    String? ubsName,
    bool? active,
    bool? mfaActive,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminStaff',
      'id': id,
      'name': name,
      'enrollmentId': enrollmentId,
      'role': role.toJson(),
      if (ubsName != null) 'ubsName': ubsName,
      'active': active,
      'mfaActive': mfaActive,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminStaffImpl extends AdminStaff {
  _AdminStaffImpl({
    required String id,
    required String name,
    required String enrollmentId,
    required _i2.UserRole role,
    String? ubsName,
    required bool active,
    required bool mfaActive,
  }) : super._(
         id: id,
         name: name,
         enrollmentId: enrollmentId,
         role: role,
         ubsName: ubsName,
         active: active,
         mfaActive: mfaActive,
       );

  /// Returns a shallow copy of this [AdminStaff]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminStaff copyWith({
    String? id,
    String? name,
    String? enrollmentId,
    _i2.UserRole? role,
    Object? ubsName = _Undefined,
    bool? active,
    bool? mfaActive,
  }) {
    return AdminStaff(
      id: id ?? this.id,
      name: name ?? this.name,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      role: role ?? this.role,
      ubsName: ubsName is String? ? ubsName : this.ubsName,
      active: active ?? this.active,
      mfaActive: mfaActive ?? this.mfaActive,
    );
  }
}
