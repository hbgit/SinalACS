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

/// Senha nova do ACS redefinida pelo backoffice (issue #43).
///
/// Existe **só** nesta resposta: não há coluna, log nem linha de auditoria que
/// a guarde — o servidor persiste apenas o hash Argon2id em `user_credentials`.
/// A senha é sorteada pelo servidor (o operador não a escolhe), pelo mesmo
/// motivo da senha inicial: uma senha escolhida por quem tem pressa vira a
/// credencial do RF07. Quem redefine mostra uma vez; perdida de novo, o caminho
/// é redefinir outra vez, nunca recuperar.
abstract class AdminPasswordResetResult implements _i1.SerializableModel {
  AdminPasswordResetResult._({required this.newPassword});

  factory AdminPasswordResetResult({required String newPassword}) =
      _AdminPasswordResetResultImpl;

  factory AdminPasswordResetResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminPasswordResetResult(
      newPassword: jsonSerialization['newPassword'] as String,
    );
  }

  String newPassword;

  /// Returns a shallow copy of this [AdminPasswordResetResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminPasswordResetResult copyWith({String? newPassword});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminPasswordResetResult',
      'newPassword': newPassword,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminPasswordResetResultImpl extends AdminPasswordResetResult {
  _AdminPasswordResetResultImpl({required String newPassword})
    : super._(newPassword: newPassword);

  /// Returns a shallow copy of this [AdminPasswordResetResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminPasswordResetResult copyWith({String? newPassword}) {
    return AdminPasswordResetResult(
      newPassword: newPassword ?? this.newPassword,
    );
  }
}
