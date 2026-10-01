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

/// Recusa de negócio de uma operação do titular sobre os próprios dados
/// (consentimento obrigatório, texto de correção vazio ou longo demais).
/// Mensagem pronta para a pessoa ler; nunca cita dado do paciente.
abstract class DataRightsException
    implements _i1.SerializableException, _i1.SerializableModel {
  DataRightsException._({required this.message});

  factory DataRightsException({required String message}) =
      _DataRightsExceptionImpl;

  factory DataRightsException.fromJson(Map<String, dynamic> jsonSerialization) {
    return DataRightsException(message: jsonSerialization['message'] as String);
  }

  String message;

  /// Returns a shallow copy of this [DataRightsException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  DataRightsException copyWith({String? message});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'DataRightsException',
      'message': message,
    };
  }

  @override
  String toString() {
    return 'DataRightsException(message: $message)';
  }
}

class _DataRightsExceptionImpl extends DataRightsException {
  _DataRightsExceptionImpl({required String message})
    : super._(message: message);

  /// Returns a shallow copy of this [DataRightsException]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  DataRightsException copyWith({String? message}) {
    return DataRightsException(message: message ?? this.message);
  }
}
