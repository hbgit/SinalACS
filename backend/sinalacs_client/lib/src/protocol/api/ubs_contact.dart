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

/// Contato da UBS do ACS autenticado (RF13). Só o que o botão "Ligar para a UBS"
/// precisa: o nome para a mensagem e o telefone para o discador.
abstract class UbsContact implements _i1.SerializableModel {
  UbsContact._({
    required this.name,
    this.phone,
  });

  factory UbsContact({
    required String name,
    String? phone,
  }) = _UbsContactImpl;

  factory UbsContact.fromJson(Map<String, dynamic> jsonSerialization) {
    return UbsContact(
      name: jsonSerialization['name'] as String,
      phone: jsonSerialization['phone'] as String?,
    );
  }

  String name;

  String? phone;

  /// Returns a shallow copy of this [UbsContact]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  UbsContact copyWith({
    String? name,
    String? phone,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'UbsContact',
      'name': name,
      if (phone != null) 'phone': phone,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _UbsContactImpl extends UbsContact {
  _UbsContactImpl({
    required String name,
    String? phone,
  }) : super._(
         name: name,
         phone: phone,
       );

  /// Returns a shallow copy of this [UbsContact]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  UbsContact copyWith({
    String? name,
    Object? phone = _Undefined,
  }) {
    return UbsContact(
      name: name ?? this.name,
      phone: phone is String? ? phone : this.phone,
    );
  }
}
