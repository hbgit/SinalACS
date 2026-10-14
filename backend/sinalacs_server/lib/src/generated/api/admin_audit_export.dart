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
import '../enums/audit_integrity_state.dart' as _i2;

/// Resultado de `admin.exportAuditLogs` (#45, D5–D8). Só o administrador
/// exporta. O arquivo é o CSV de `AuditCsv` (colunas fixas de D6: nunca
/// `userId`, `resourceId`, `ipHash`, `previousHash`, `entryHash` nem segredo).
/// - `fileName`: `auditoria_<from>_<to>.csv` em UTC compacto; sem dado pessoal.
/// - `csv`: o conteúdo (UTF-8, RFC 4180, CRLF), gerado em memória no servidor.
/// - `rowCount`, `firstSequence`, `lastSequence`: o recorte exportado (as duas
///   sequences são nulas com recorte vazio). O próprio evento `export` fica
///   sempre FORA do arquivo (`sequence` maior que `lastSequence`).
/// - `contentSha256`: SHA-256 (hex minúsculo) dos bytes UTF-8 de `csv`, o mesmo
///   gravado em `audit_exports`.
/// - `chainState`: estado da verificação global da cadeia no momento da
///   exportação (cache de 60 s); qualquer coisa diferente de `verified` é
///   registrada e devolvida como está.
/// - `generatedAt`: instante da exportação (UTC), o `requestedAt` gravado.
abstract class AdminAuditExport
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAuditExport._({
    required this.fileName,
    required this.csv,
    required this.rowCount,
    this.firstSequence,
    this.lastSequence,
    required this.contentSha256,
    required this.chainState,
    required this.generatedAt,
  });

  factory AdminAuditExport({
    required String fileName,
    required String csv,
    required int rowCount,
    int? firstSequence,
    int? lastSequence,
    required String contentSha256,
    required _i2.AuditIntegrityState chainState,
    required DateTime generatedAt,
  }) = _AdminAuditExportImpl;

  factory AdminAuditExport.fromJson(Map<String, dynamic> jsonSerialization) {
    return AdminAuditExport(
      fileName: jsonSerialization['fileName'] as String,
      csv: jsonSerialization['csv'] as String,
      rowCount: jsonSerialization['rowCount'] as int,
      firstSequence: jsonSerialization['firstSequence'] as int?,
      lastSequence: jsonSerialization['lastSequence'] as int?,
      contentSha256: jsonSerialization['contentSha256'] as String,
      chainState: _i2.AuditIntegrityState.fromJson(
        (jsonSerialization['chainState'] as String),
      ),
      generatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['generatedAt'],
      ),
    );
  }

  String fileName;

  String csv;

  int rowCount;

  int? firstSequence;

  int? lastSequence;

  String contentSha256;

  _i2.AuditIntegrityState chainState;

  DateTime generatedAt;

  /// Returns a shallow copy of this [AdminAuditExport]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAuditExport copyWith({
    String? fileName,
    String? csv,
    int? rowCount,
    int? firstSequence,
    int? lastSequence,
    String? contentSha256,
    _i2.AuditIntegrityState? chainState,
    DateTime? generatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAuditExport',
      'fileName': fileName,
      'csv': csv,
      'rowCount': rowCount,
      if (firstSequence != null) 'firstSequence': firstSequence,
      if (lastSequence != null) 'lastSequence': lastSequence,
      'contentSha256': contentSha256,
      'chainState': chainState.toJson(),
      'generatedAt': generatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAuditExport',
      'fileName': fileName,
      'csv': csv,
      'rowCount': rowCount,
      if (firstSequence != null) 'firstSequence': firstSequence,
      if (lastSequence != null) 'lastSequence': lastSequence,
      'contentSha256': contentSha256,
      'chainState': chainState.toJson(),
      'generatedAt': generatedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAuditExportImpl extends AdminAuditExport {
  _AdminAuditExportImpl({
    required String fileName,
    required String csv,
    required int rowCount,
    int? firstSequence,
    int? lastSequence,
    required String contentSha256,
    required _i2.AuditIntegrityState chainState,
    required DateTime generatedAt,
  }) : super._(
         fileName: fileName,
         csv: csv,
         rowCount: rowCount,
         firstSequence: firstSequence,
         lastSequence: lastSequence,
         contentSha256: contentSha256,
         chainState: chainState,
         generatedAt: generatedAt,
       );

  /// Returns a shallow copy of this [AdminAuditExport]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAuditExport copyWith({
    String? fileName,
    String? csv,
    int? rowCount,
    Object? firstSequence = _Undefined,
    Object? lastSequence = _Undefined,
    String? contentSha256,
    _i2.AuditIntegrityState? chainState,
    DateTime? generatedAt,
  }) {
    return AdminAuditExport(
      fileName: fileName ?? this.fileName,
      csv: csv ?? this.csv,
      rowCount: rowCount ?? this.rowCount,
      firstSequence: firstSequence is int? ? firstSequence : this.firstSequence,
      lastSequence: lastSequence is int? ? lastSequence : this.lastSequence,
      contentSha256: contentSha256 ?? this.contentSha256,
      chainState: chainState ?? this.chainState,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }
}
