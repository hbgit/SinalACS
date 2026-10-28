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

/// A emissão do certificado de cliente MQTT do aparelho (#94) não pode ser
/// feita AGORA, mas pode dar certo mais tarde sem intervenção da coordenação:
/// o aparelho passou do limite de emissões por hora, ou a microárea da sessão
/// ficou para trás da gravada na conta (a próxima renovação do token traz a
/// nova). O app a trata como transitória: mantém o certificado guardado que
/// ainda vale e tenta de novo. Mensagem pronta para o ACS ler.
abstract class DeviceCertificateRetryLaterException
    implements _i1.SerializableException, _i1.SerializableModel {
  DeviceCertificateRetryLaterException._({required this.message});

  factory DeviceCertificateRetryLaterException({required String message}) =
      _DeviceCertificateRetryLaterExceptionImpl;

  factory DeviceCertificateRetryLaterException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return DeviceCertificateRetryLaterException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [DeviceCertificateRetryLaterException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DeviceCertificateRetryLaterException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DeviceCertificateRetryLaterException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'DeviceCertificateRetryLaterException(message: $message)';
  }
}

class _DeviceCertificateRetryLaterExceptionImpl
    extends DeviceCertificateRetryLaterException {
  _DeviceCertificateRetryLaterExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [DeviceCertificateRetryLaterException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DeviceCertificateRetryLaterException copyWith({String? message}) {
    return DeviceCertificateRetryLaterException(
      message: message ?? this.message,
    );
  }
}
