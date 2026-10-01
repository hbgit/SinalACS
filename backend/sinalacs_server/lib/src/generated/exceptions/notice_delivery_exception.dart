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

/// O aviso comunitário não pôde ser entregue agora: o relé de push está fora do
/// ar, lento, ou o envio não está configurado neste ambiente. Mensagem pronta
/// para o ACS ler; nunca cita token, destinatário nem o texto enviado.
abstract class NoticeDeliveryException
    implements
        _i1.SerializableException,
        _i1.SerializableModel,
        _i1.ProtocolSerialization {
  NoticeDeliveryException._({required this.message});

  factory NoticeDeliveryException({required String message}) =
      _NoticeDeliveryExceptionImpl;

  factory NoticeDeliveryException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return NoticeDeliveryException(
      message: jsonSerialization['message'] as String,
    );
  }

  String message;

  /// Returns a shallow copy of this [NoticeDeliveryException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  NoticeDeliveryException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NoticeDeliveryException',
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'NoticeDeliveryException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'NoticeDeliveryException(message: $message)';
  }
}

class _NoticeDeliveryExceptionImpl extends NoticeDeliveryException {
  _NoticeDeliveryExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [NoticeDeliveryException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  NoticeDeliveryException copyWith({String? message}) {
    return NoticeDeliveryException(message: message ?? this.message);
  }
}
