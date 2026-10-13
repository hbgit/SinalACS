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

/// Registro de cada exportação da trilha de auditoria (#45). Append-only:
/// guarda quem exportou, os filtros, o intervalo de `sequence` coberto e o
/// SHA-256 do conteúdo, para que a própria exportação seja auditável.
abstract class AuditExport implements _i1.SerializableModel {
  AuditExport._({
    this.id,
    required this.requestedBy,
    required this.requestedAt,
    required this.filtersJson,
    required this.format,
    required this.rowCount,
    this.firstSequence,
    this.lastSequence,
    required this.contentSha256,
    required this.chainState,
  });

  factory AuditExport({
    _i1.UuidValue? id,
    required _i1.UuidValue requestedBy,
    required DateTime requestedAt,
    required String filtersJson,
    required String format,
    required int rowCount,
    int? firstSequence,
    int? lastSequence,
    required String contentSha256,
    required String chainState,
  }) = _AuditExportImpl;

  factory AuditExport.fromJson(Map<String, dynamic> jsonSerialization) {
    return AuditExport(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      requestedBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['requestedBy'],
      ),
      requestedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['requestedAt'],
      ),
      filtersJson: jsonSerialization['filtersJson'] as String,
      format: jsonSerialization['format'] as String,
      rowCount: jsonSerialization['rowCount'] as int,
      firstSequence: jsonSerialization['firstSequence'] as int?,
      lastSequence: jsonSerialization['lastSequence'] as int?,
      contentSha256: jsonSerialization['contentSha256'] as String,
      chainState: jsonSerialization['chainState'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  _i1.UuidValue requestedBy;

  DateTime requestedAt;

  String filtersJson;

  String format;

  int rowCount;

  int? firstSequence;

  int? lastSequence;

  String contentSha256;

  /// Resultado da verificação da cadeia no momento da exportação.
  String chainState;

  /// Returns a shallow copy of this [AuditExport]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AuditExport copyWith({
    _i1.UuidValue? id,
    _i1.UuidValue? requestedBy,
    DateTime? requestedAt,
    String? filtersJson,
    String? format,
    int? rowCount,
    int? firstSequence,
    int? lastSequence,
    String? contentSha256,
    String? chainState,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AuditExport',
      if (id != null) 'id': id?.toJson(),
      'requestedBy': requestedBy.toJson(),
      'requestedAt': requestedAt.toJson(),
      'filtersJson': filtersJson,
      'format': format,
      'rowCount': rowCount,
      if (firstSequence != null) 'firstSequence': firstSequence,
      if (lastSequence != null) 'lastSequence': lastSequence,
      'contentSha256': contentSha256,
      'chainState': chainState,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AuditExportImpl extends AuditExport {
  _AuditExportImpl({
    _i1.UuidValue? id,
    required _i1.UuidValue requestedBy,
    required DateTime requestedAt,
    required String filtersJson,
    required String format,
    required int rowCount,
    int? firstSequence,
    int? lastSequence,
    required String contentSha256,
    required String chainState,
  }) : super._(
         id: id,
         requestedBy: requestedBy,
         requestedAt: requestedAt,
         filtersJson: filtersJson,
         format: format,
         rowCount: rowCount,
         firstSequence: firstSequence,
         lastSequence: lastSequence,
         contentSha256: contentSha256,
         chainState: chainState,
       );

  /// Returns a shallow copy of this [AuditExport]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AuditExport copyWith({
    Object? id = _Undefined,
    _i1.UuidValue? requestedBy,
    DateTime? requestedAt,
    String? filtersJson,
    String? format,
    int? rowCount,
    Object? firstSequence = _Undefined,
    Object? lastSequence = _Undefined,
    String? contentSha256,
    String? chainState,
  }) {
    return AuditExport(
      id: id is _i1.UuidValue? ? id : this.id,
      requestedBy: requestedBy ?? this.requestedBy,
      requestedAt: requestedAt ?? this.requestedAt,
      filtersJson: filtersJson ?? this.filtersJson,
      format: format ?? this.format,
      rowCount: rowCount ?? this.rowCount,
      firstSequence: firstSequence is int? ? firstSequence : this.firstSequence,
      lastSequence: lastSequence is int? ? lastSequence : this.lastSequence,
      contentSha256: contentSha256 ?? this.contentSha256,
      chainState: chainState ?? this.chainState,
    );
  }
}
