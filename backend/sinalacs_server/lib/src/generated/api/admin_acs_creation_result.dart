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
import '../api/admin_acs.dart' as _i2;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i3;

/// ACS recém-cadastrado e a senha inicial gerada (issue #43).
///
/// A senha existe **só** aqui e na resposta de `admin.createAcs`: não há coluna,
/// log nem linha de auditoria que a guarde — o servidor persiste apenas o hash
/// Argon2id em `user_credentials`. A trilha registra `created` com o id do ACS e
/// nunca a credencial. Quem cadastra mostra uma vez; perdida a senha, o caminho
/// é redefinir, não recuperar (operação seguinte da mesma issue).
abstract class AdminAcsCreationResult
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAcsCreationResult._({
    required this.acs,
    required this.initialPassword,
  });

  factory AdminAcsCreationResult({
    required _i2.AdminAcs acs,
    required String initialPassword,
  }) = _AdminAcsCreationResultImpl;

  factory AdminAcsCreationResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminAcsCreationResult(
      acs: _i3.Protocol().deserialize<_i2.AdminAcs>(jsonSerialization['acs']),
      initialPassword: jsonSerialization['initialPassword'] as String,
    );
  }

  _i2.AdminAcs acs;

  String initialPassword;

  /// Returns a shallow copy of this [AdminAcsCreationResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAcsCreationResult copyWith({
    _i2.AdminAcs? acs,
    String? initialPassword,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAcsCreationResult',
      'acs': acs.toJson(),
      'initialPassword': initialPassword,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAcsCreationResult',
      'acs': acs.toJsonForProtocol(),
      'initialPassword': initialPassword,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminAcsCreationResultImpl extends AdminAcsCreationResult {
  _AdminAcsCreationResultImpl({
    required _i2.AdminAcs acs,
    required String initialPassword,
  }) : super._(
         acs: acs,
         initialPassword: initialPassword,
       );

  /// Returns a shallow copy of this [AdminAcsCreationResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAcsCreationResult copyWith({
    _i2.AdminAcs? acs,
    String? initialPassword,
  }) {
    return AdminAcsCreationResult(
      acs: acs ?? this.acs.copyWith(),
      initialPassword: initialPassword ?? this.initialPassword,
    );
  }
}
