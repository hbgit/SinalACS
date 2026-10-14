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
import '../api/notice_history_entry.dart' as _i2;
import 'package:sinalacs_server/src/generated/protocol.dart' as _i3;

/// Página do histórico de avisos agendados (#46), mais recentes primeiro.
abstract class NoticeHistoryPage
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  NoticeHistoryPage._({required this.entries});

  factory NoticeHistoryPage({required List<_i2.NoticeHistoryEntry> entries}) =
      _NoticeHistoryPageImpl;

  factory NoticeHistoryPage.fromJson(Map<String, dynamic> jsonSerialization) {
    return NoticeHistoryPage(
      entries: _i3.Protocol().deserialize<List<_i2.NoticeHistoryEntry>>(
        jsonSerialization['entries'],
      ),
    );
  }

  List<_i2.NoticeHistoryEntry> entries;

  /// Returns a shallow copy of this [NoticeHistoryPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  NoticeHistoryPage copyWith({List<_i2.NoticeHistoryEntry>? entries});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NoticeHistoryPage',
      'entries': entries.toJson(valueToJson: (v) => v.toJson()),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'NoticeHistoryPage',
      'entries': entries.toJson(valueToJson: (v) => v.toJsonForProtocol()),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _NoticeHistoryPageImpl extends NoticeHistoryPage {
  _NoticeHistoryPageImpl({required List<_i2.NoticeHistoryEntry> entries})
    : super._(entries: entries);

  /// Returns a shallow copy of this [NoticeHistoryPage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  NoticeHistoryPage copyWith({List<_i2.NoticeHistoryEntry>? entries}) {
    return NoticeHistoryPage(
      entries: entries ?? this.entries.map((e0) => e0.copyWith()).toList(),
    );
  }
}
