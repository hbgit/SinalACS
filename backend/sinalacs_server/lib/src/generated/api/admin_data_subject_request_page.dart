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
import '../api/admin_data_subject_request.dart' as _i2;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i3;

/// Página de pedidos do titular. `nextOffset` nulo = não há mais páginas.
abstract class AdminDataSubjectRequestPage
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminDataSubjectRequestPage._({
    required this.items,
    this.nextOffset,
  });

  factory AdminDataSubjectRequestPage({
    required List<_i2.AdminDataSubjectRequest> items,
    int? nextOffset,
  }) = _AdminDataSubjectRequestPageImpl;

  factory AdminDataSubjectRequestPage.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminDataSubjectRequestPage(
      items: _i3.Protocol().deserialize<List<_i2.AdminDataSubjectRequest>>(
        jsonSerialization['items'],
      ),
      nextOffset: jsonSerialization['nextOffset'] as int?,
    );
  }

  List<_i2.AdminDataSubjectRequest> items;

  int? nextOffset;

  /// Returns a shallow copy of this [AdminDataSubjectRequestPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminDataSubjectRequestPage copyWith({
    List<_i2.AdminDataSubjectRequest>? items,
    int? nextOffset,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminDataSubjectRequestPage',
      'items': items.toJson(valueToJson: (v) => v.toJson()),
      if (nextOffset != null) 'nextOffset': nextOffset,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminDataSubjectRequestPage',
      'items': items.toJson(valueToJson: (v) => v.toJsonForProtocol()),
      if (nextOffset != null) 'nextOffset': nextOffset,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminDataSubjectRequestPageImpl extends AdminDataSubjectRequestPage {
  _AdminDataSubjectRequestPageImpl({
    required List<_i2.AdminDataSubjectRequest> items,
    int? nextOffset,
  }) : super._(
         items: items,
         nextOffset: nextOffset,
       );

  /// Returns a shallow copy of this [AdminDataSubjectRequestPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminDataSubjectRequestPage copyWith({
    List<_i2.AdminDataSubjectRequest>? items,
    Object? nextOffset = _Undefined,
  }) {
    return AdminDataSubjectRequestPage(
      items: items ?? this.items.map((e0) => e0.copyWith()).toList(),
      nextOffset: nextOffset is int? ? nextOffset : this.nextOffset,
    );
  }
}
