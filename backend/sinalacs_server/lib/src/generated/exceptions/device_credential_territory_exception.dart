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

/// Recusa do login por credencial de dispositivo quando o titular não tem
/// microárea vinculada (C-05, RF24).
///
/// Diferente de [DeviceCredentialException]: o aparelho e o segredo estão
/// certos, mas falta o território — é estado administrativo do cadastro, e
/// pode ser transitório (troca de microárea). O app não pode destruir a
/// credencial local por causa desta recusa; a mensagem, sim, é para a pessoa
/// ler.
abstract class DeviceCredentialTerritoryException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  DeviceCredentialTerritoryException._({required this.message});

  factory DeviceCredentialTerritoryException({required String message}) =
      _DeviceCredentialTerritoryExceptionImpl;

  factory DeviceCredentialTerritoryException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return DeviceCredentialTerritoryException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [DeviceCredentialTerritoryException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCredentialTerritoryException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCredentialTerritoryException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceCredentialTerritoryException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'DeviceCredentialTerritoryException(message: $message)';
  }
}

class _DeviceCredentialTerritoryExceptionImpl
    extends DeviceCredentialTerritoryException {
  _DeviceCredentialTerritoryExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [DeviceCredentialTerritoryException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCredentialTerritoryException copyWith({String? message}) {
    return DeviceCredentialTerritoryException(message: message ?? this.message);
  }
}
