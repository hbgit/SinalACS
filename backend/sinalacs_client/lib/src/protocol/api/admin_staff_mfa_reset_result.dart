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

/// Redefinição da MFA de uma conta de equipe pelo backoffice (issue #43), com
/// o código de ativação novo emitido **pela tela** — o deferimento da #48.
///
/// Fecha a pendência registrada no `PROGRESS.md` (L665): até aqui só a CLI de
/// operador `bin/issue_staff_activation_code.dart` emitia, e a emissão não
/// entrava em `audit_logs`. Agora a operação faz as duas coisas numa transação
/// só — zera as quatro colunas `totp*` da conta e grava
/// `activationCodeHash/ExpiresAt/IssuedBy/IssuedAt` — e a linha
/// `admin_staff`/`mfa_reset` com o id do alvo fica na trilha.
///
/// O código existe **só** nesta resposta: o servidor guarda apenas o SHA-256
/// (`StaffActivationCode.hash`), como no `#48`. Quem redefine mostra uma vez;
/// perdido de novo, o caminho é redefinir outra vez, nunca recuperar.
abstract class AdminStaffMfaResetResult implements _i1.SerializableModel {
  AdminStaffMfaResetResult._({
    required this.activationCode,
    required this.activationCodeExpiresAt,
  });

  factory AdminStaffMfaResetResult({
    required String activationCode,
    required DateTime activationCodeExpiresAt,
  }) = _AdminStaffMfaResetResultImpl;

  factory AdminStaffMfaResetResult.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminStaffMfaResetResult(
      activationCode: jsonSerialization['activationCode'] as String,
      activationCodeExpiresAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['activationCodeExpiresAt'],
      ),
    );
  }

  String activationCode;

  DateTime activationCodeExpiresAt;

  /// Returns a shallow copy of this [AdminStaffMfaResetResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminStaffMfaResetResult copyWith({
    String? activationCode,
    DateTime? activationCodeExpiresAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminStaffMfaResetResult',
      'activationCode': activationCode,
      'activationCodeExpiresAt': activationCodeExpiresAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _AdminStaffMfaResetResultImpl extends AdminStaffMfaResetResult {
  _AdminStaffMfaResetResultImpl({
    required String activationCode,
    required DateTime activationCodeExpiresAt,
  }) : super._(
         activationCode: activationCode,
         activationCodeExpiresAt: activationCodeExpiresAt,
       );

  /// Returns a shallow copy of this [AdminStaffMfaResetResult]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminStaffMfaResetResult copyWith({
    String? activationCode,
    DateTime? activationCodeExpiresAt,
  }) {
    return AdminStaffMfaResetResult(
      activationCode: activationCode ?? this.activationCode,
      activationCodeExpiresAt:
          activationCodeExpiresAt ?? this.activationCodeExpiresAt,
    );
  }
}
