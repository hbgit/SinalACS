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

/// O broker MQTT não está conectado, então o alerta não pôde ser publicado.
/// Substitui o MqttUnavailableException que o servidor dart:io mapeava para
/// HTTP 503.
///
/// NÃO é mais lançada por alerts.createRedAlert: com o outbox transacional, um
/// broker indisponível deixou de recusar o alerta — ele é gravado, a entrega
/// fica pendente, e o campo `published` do RedAlertResult volta falso. Um
/// alerta vermelho não é descartado por indisponibilidade do broker (INV-03).
///
/// Mantida no protocolo por ora; nenhum endpoint a lança hoje.
abstract class AlertDispatchUnavailableException
    implements _i1.SerializableException, _i1.SerializableModel {
  AlertDispatchUnavailableException._({required this.message});

  factory AlertDispatchUnavailableException({required String message}) =
      _AlertDispatchUnavailableExceptionImpl;

  factory AlertDispatchUnavailableException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AlertDispatchUnavailableException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [AlertDispatchUnavailableException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertDispatchUnavailableException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AlertDispatchUnavailableException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'AlertDispatchUnavailableException(message: $message)';
  }
}

class _AlertDispatchUnavailableExceptionImpl
    extends AlertDispatchUnavailableException {
  _AlertDispatchUnavailableExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [AlertDispatchUnavailableException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertDispatchUnavailableException copyWith({String? message}) {
    return AlertDispatchUnavailableException(message: message ?? this.message);
  }
}
