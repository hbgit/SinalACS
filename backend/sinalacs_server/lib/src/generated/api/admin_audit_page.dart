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
import '../api/admin_audit_entry.dart' as _i2;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i3;

/// Página de auditoria por keyset: `nextBeforeSequence` é o `sequence` da última
/// linha devolvida (o log só cresce, então `offset` repetiria linhas).
abstract class AdminAuditPage
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAuditPage._({
    required this.items,
    this.nextBeforeSequence,
  });

  factory AdminAuditPage({
    required List<_i2.AdminAuditEntry> items,
    int? nextBeforeSequence,
  }) = _AdminAuditPageImpl;

  factory AdminAuditPage.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAuditPage(
      items: _i3.Protocol().deserialize<List<_i2.AdminAuditEntry>>(
        jsonSerialization['items'],
      ),
      nextBeforeSequence: jsonSerialization['nextBeforeSequence'] as int?,
    );
  }

  List<_i2.AdminAuditEntry> items;

  int? nextBeforeSequence;

  /// Returns a shallow copy of this [AdminAuditPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAuditPage copyWith({
    List<_i2.AdminAuditEntry>? items,
    int? nextBeforeSequence,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAuditPage',
      'items': items.toJson(valueToJson: (v) => v.toJson()),
      if (nextBeforeSequence != null) 'nextBeforeSequence': nextBeforeSequence,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAuditPage',
      'items': items.toJson(valueToJson: (v) => v.toJsonForProtocol()),
      if (nextBeforeSequence != null) 'nextBeforeSequence': nextBeforeSequence,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAuditPageImpl extends AdminAuditPage {
  _AdminAuditPageImpl({
    required List<_i2.AdminAuditEntry> items,
    int? nextBeforeSequence,
  }) : super._(
         items: items,
         nextBeforeSequence: nextBeforeSequence,
       );

  /// Returns a shallow copy of this [AdminAuditPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAuditPage copyWith({
    List<_i2.AdminAuditEntry>? items,
    Object? nextBeforeSequence = _Undefined,
  }) {
    return AdminAuditPage(
      items: items ?? this.items.map((e0) => e0.copyWith()).toList(),
      nextBeforeSequence: nextBeforeSequence is int?
          ? nextBeforeSequence
          : this.nextBeforeSequence,
    );
  }
}
