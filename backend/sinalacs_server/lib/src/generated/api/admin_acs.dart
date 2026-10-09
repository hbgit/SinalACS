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

/// ACS no backoffice (#43): identificação profissional, território e estado de
/// acesso. Nunca inclui CPF, senha ou contato.
///
/// `mfaActive` é `user_credentials.totpEnabledAt IS NOT NULL` — MFA **ativa**,
/// não apenas iniciada: um enrollment pendente (`totpEnabledAt` nulo) não vale
/// como proteção e a tela precisa poder dizer isso.
abstract class AdminAcs
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAcs._({
    required this.id,
    required this.name,
    required this.enrollmentId,
    required this.ubsId,
    required this.ubsName,
    this.microAreaId,
    this.microAreaName,
    required this.active,
    required this.mfaActive,
  });

  factory AdminAcs({
    required String id,
    required String name,
    required String enrollmentId,
    required String ubsId,
    required String ubsName,
    String? microAreaId,
    String? microAreaName,
    required bool active,
    required bool mfaActive,
  }) = _AdminAcsImpl;

  factory AdminAcs.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAcs(
      id: jsonSerialization['id'] as String,
      name: jsonSerialization['name'] as String,
      enrollmentId: jsonSerialization['enrollmentId'] as String,
      ubsId: jsonSerialization['ubsId'] as String,
      ubsName: jsonSerialization['ubsName'] as String,
      microAreaId: jsonSerialization['microAreaId'] as String?,
      microAreaName: jsonSerialization['microAreaName'] as String?,
      active: _i1.BoolJsonExtension.fromJson(jsonSerialization['active']),
      mfaActive: _i1.BoolJsonExtension.fromJson(jsonSerialization['mfaActive']),
    );
  }

  String id;

  String name;

  String enrollmentId;

  String ubsId;

  String ubsName;

  /// Nulos enquanto o ACS não tem território (`users.microAreaId`). A listagem
  /// inclui quem não tem microárea, para poder vinculá-lo.
  String? microAreaId;

  String? microAreaName;

  bool active;

  bool mfaActive;

  /// Returns a shallow copy of this [AdminAcs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAcs copyWith({
    String? id,
    String? name,
    String? enrollmentId,
    String? ubsId,
    String? ubsName,
    String? microAreaId,
    String? microAreaName,
    bool? active,
    bool? mfaActive,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAcs',
      'id': id,
      'name': name,
      'enrollmentId': enrollmentId,
      'ubsId': ubsId,
      'ubsName': ubsName,
      if (microAreaId != null) 'microAreaId': microAreaId,
      if (microAreaName != null) 'microAreaName': microAreaName,
      'active': active,
      'mfaActive': mfaActive,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAcs',
      'id': id,
      'name': name,
      'enrollmentId': enrollmentId,
      'ubsId': ubsId,
      'ubsName': ubsName,
      if (microAreaId != null) 'microAreaId': microAreaId,
      if (microAreaName != null) 'microAreaName': microAreaName,
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

class _AdminAcsImpl extends AdminAcs {
  _AdminAcsImpl({
    required String id,
    required String name,
    required String enrollmentId,
    required String ubsId,
    required String ubsName,
    String? microAreaId,
    String? microAreaName,
    required bool active,
    required bool mfaActive,
  }) : super._(
         id: id,
         name: name,
         enrollmentId: enrollmentId,
         ubsId: ubsId,
         ubsName: ubsName,
         microAreaId: microAreaId,
         microAreaName: microAreaName,
         active: active,
         mfaActive: mfaActive,
       );

  /// Returns a shallow copy of this [AdminAcs]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAcs copyWith({
    String? id,
    String? name,
    String? enrollmentId,
    String? ubsId,
    String? ubsName,
    Object? microAreaId = _Undefined,
    Object? microAreaName = _Undefined,
    bool? active,
    bool? mfaActive,
  }) {
    return AdminAcs(
      id: id ?? this.id,
      name: name ?? this.name,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      ubsId: ubsId ?? this.ubsId,
      ubsName: ubsName ?? this.ubsName,
      microAreaId: microAreaId is String? ? microAreaId : this.microAreaId,
      microAreaName: microAreaName is String?
          ? microAreaName
          : this.microAreaName,
      active: active ?? this.active,
      mfaActive: mfaActive ?? this.mfaActive,
    );
  }
}
