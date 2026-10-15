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
import '../api/admin_alert.dart' as _i2;
import 'package:sinalacs_client/src/protocol/protocol.dart' as _i3;

/// Página de alertas. `nextOffset` nulo = não há mais páginas.
abstract class AdminAlertPage implements _i1.SerializableModel {
  AdminAlertPage._({
    required this.items,
    this.nextOffset,
  });

  factory AdminAlertPage({
    required List<_i2.AdminAlert> items,
    int? nextOffset,
  }) = _AdminAlertPageImpl;

  factory AdminAlertPage.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAlertPage(
      items: _i3.Protocol().deserialize<List<_i2.AdminAlert>>(
        jsonSerialization['items'],
      ),
      nextOffset: jsonSerialization['nextOffset'] as int?,
    );
  }

  List<_i2.AdminAlert> items;

  int? nextOffset;

  /// Returns a shallow copy of this [AdminAlertPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAlertPage copyWith({
    List<_i2.AdminAlert>? items,
    int? nextOffset,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAlertPage',
      'items': items.toJson(valueToJson: (v) => v.toJson()),
      if (nextOffset != null) 'nextOffset': nextOffset,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAlertPageImpl extends AdminAlertPage {
  _AdminAlertPageImpl({
    required List<_i2.AdminAlert> items,
    int? nextOffset,
  }) : super._(
         items: items,
         nextOffset: nextOffset,
       );

  /// Returns a shallow copy of this [AdminAlertPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAlertPage copyWith({
    List<_i2.AdminAlert>? items,
    Object? nextOffset = _Undefined,
  }) {
    return AdminAlertPage(
      items: items ?? this.items.map((e0) => e0.copyWith()).toList(),
      nextOffset: nextOffset is int? ? nextOffset : this.nextOffset,
    );
  }
}
