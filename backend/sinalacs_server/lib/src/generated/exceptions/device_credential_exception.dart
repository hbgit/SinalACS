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

/// Recusa do login por credencial de dispositivo do participante (C-05).
///
/// Uma exceção só, com mensagem única, para segredo errado, deviceId
/// desconhecido e credencial revogada (C-12): a resposta não pode dizer ao
/// atacante qual dos três casos aconteceu.
abstract class DeviceCredentialException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  DeviceCredentialException._({required this.message});

  factory DeviceCredentialException({required String message}) =
      _DeviceCredentialExceptionImpl;

  factory DeviceCredentialException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return DeviceCredentialException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [DeviceCredentialException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCredentialException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCredentialException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'DeviceCredentialException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'DeviceCredentialException(message: $message)';
  }
}

class _DeviceCredentialExceptionImpl extends DeviceCredentialException {
  _DeviceCredentialExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [DeviceCredentialException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCredentialException copyWith({String? message}) {
    return DeviceCredentialException(message: message ?? this.message);
  }
}
