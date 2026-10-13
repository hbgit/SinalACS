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
import '../enums/user_role.dart' as _i2;

/// Filtro da trilha de auditoria do backoffice (#45, D1/D2/D10). Todos os
/// campos são opcionais e combinados por AND; nulo = sem restrição. Nunca
/// alarga o escopo: o coordenador continua vendo só os autores da UBS dele.
///
/// Validação no `AdminReadService` (antes de auditar a leitura):
/// - `actorEnrollmentId`: matrícula do autor (ACS ou staff), igualdade sem
///   caixa, 1 a 32 caracteres. Paciente não é filtrável por identificador.
/// - `actionType`: `read`, `write`, `login` ou `export`.
/// - `resourceType`, `result`: `^[a-z_]{1,64}$`, igualdade.
/// - `from`/`to`: UTC; `from` inclusivo, `to` exclusivo, `from < to` e janela
///   de no máximo 366 dias quando os dois vêm.
/// - `search`: 2 a 64 caracteres; casa só o início da matrícula do autor,
///   `resourceType` e `result` (sem caixa, curingas escapados). Nunca hash,
///   IP, UUID ou nome.
/// Não há filtro por `resourceId` (D10: pode ser id de paciente).
abstract class AdminAuditFilter
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAuditFilter._({
    this.actorEnrollmentId,
    this.actorRole,
    this.actionType,
    this.resourceType,
    this.result,
    this.from,
    this.to,
    this.search,
  });

  factory AdminAuditFilter({
    String? actorEnrollmentId,
    _i2.UserRole? actorRole,
    String? actionType,
    String? resourceType,
    String? result,
    DateTime? from,
    DateTime? to,
    String? search,
  }) = _AdminAuditFilterImpl;

  factory AdminAuditFilter.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAuditFilter(
      actorEnrollmentId: jsonSerialization['actorEnrollmentId'] as String?,
      actorRole: jsonSerialization['actorRole'] == null
          ? null
          : _i2.UserRole.fromJson((jsonSerialization['actorRole'] as String)),
      actionType: jsonSerialization['actionType'] as String?,
      resourceType: jsonSerialization['resourceType'] as String?,
      result: jsonSerialization['result'] as String?,
      from: jsonSerialization['from'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['from']),
      to: jsonSerialization['to'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['to']),
      search: jsonSerialization['search'] as String?,
    );
  }

  String? actorEnrollmentId;

  _i2.UserRole? actorRole;

  String? actionType;

  String? resourceType;

  String? result;

  DateTime? from;

  DateTime? to;

  String? search;

  /// Returns a shallow copy of this [AdminAuditFilter]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAuditFilter copyWith({
    String? actorEnrollmentId,
    _i2.UserRole? actorRole,
    String? actionType,
    String? resourceType,
    String? result,
    DateTime? from,
    DateTime? to,
    String? search,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAuditFilter',
      if (actorEnrollmentId != null) 'actorEnrollmentId': actorEnrollmentId,
      if (actorRole != null) 'actorRole': actorRole?.toJson(),
      if (actionType != null) 'actionType': actionType,
      if (resourceType != null) 'resourceType': resourceType,
      if (result != null) 'result': result,
      if (from != null) 'from': from?.toJson(),
      if (to != null) 'to': to?.toJson(),
      if (search != null) 'search': search,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAuditFilter',
      if (actorEnrollmentId != null) 'actorEnrollmentId': actorEnrollmentId,
      if (actorRole != null) 'actorRole': actorRole?.toJson(),
      if (actionType != null) 'actionType': actionType,
      if (resourceType != null) 'resourceType': resourceType,
      if (result != null) 'result': result,
      if (from != null) 'from': from?.toJson(),
      if (to != null) 'to': to?.toJson(),
      if (search != null) 'search': search,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAuditFilterImpl extends AdminAuditFilter {
  _AdminAuditFilterImpl({
    String? actorEnrollmentId,
    _i2.UserRole? actorRole,
    String? actionType,
    String? resourceType,
    String? result,
    DateTime? from,
    DateTime? to,
    String? search,
  }) : super._(
         actorEnrollmentId: actorEnrollmentId,
         actorRole: actorRole,
         actionType: actionType,
         resourceType: resourceType,
         result: result,
         from: from,
         to: to,
         search: search,
       );

  /// Returns a shallow copy of this [AdminAuditFilter]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAuditFilter copyWith({
    Object? actorEnrollmentId = _Undefined,
    Object? actorRole = _Undefined,
    Object? actionType = _Undefined,
    Object? resourceType = _Undefined,
    Object? result = _Undefined,
    Object? from = _Undefined,
    Object? to = _Undefined,
    Object? search = _Undefined,
  }) {
    return AdminAuditFilter(
      actorEnrollmentId: actorEnrollmentId is String?
          ? actorEnrollmentId
          : this.actorEnrollmentId,
      actorRole: actorRole is _i2.UserRole? ? actorRole : this.actorRole,
      actionType: actionType is String? ? actionType : this.actionType,
      resourceType: resourceType is String? ? resourceType : this.resourceType,
      result: result is String? ? result : this.result,
      from: from is DateTime? ? from : this.from,
      to: to is DateTime? ? to : this.to,
      search: search is String? ? search : this.search,
    );
  }
}
