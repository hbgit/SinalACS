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
import '../enums/audit_chain_reason.dart' as _i3;

/// Resultado de `admin.verifyAuditChain` (#45, D3/D9). Nunca carrega hash,
/// segredo nem conteúdo de linha.
/// - `state`: só `verified` é verde; qualquer outro, nunca.
/// - `checkedRows`: linhas conferidas antes da quebra (ou o total). Só para o
///   administrador; nulo para o coordenador (não infere volume de outra UBS).
/// - `headSequence`: última `sequence` da cadeia íntegra. Só administrador e
///   só com `verified`.
/// - `firstBrokenSequence`: onde a cadeia quebrou. Para o coordenador, só se
///   a linha quebrada for de um autor da UBS dele; senão nulo.
/// - `brokenInScope`: com `broken`, se a quebra é visível no escopo de quem
///   chama (sempre `true` para o administrador); nulo nos outros estados ou se
///   o pertencimento não pôde ser apurado.
/// - `reasonCode`: motivo fechado; o texto livre do verificador não sai do
///   servidor. Para o coordenador, quebra fora do escopo vem sem motivo.
/// - `verifiedAt`: quando a verificação servida terminou (cache de 60 s).
abstract class AdminAuditChainStatus
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  AdminAuditChainStatus._({
    required this.state,
    this.checkedRows,
    this.headSequence,
    this.firstBrokenSequence,
    this.brokenInScope,
    this.reasonCode,
    required this.verifiedAt,
  });

  factory AdminAuditChainStatus({
    required _i2.AuditIntegrityState state,
    int? checkedRows,
    int? headSequence,
    int? firstBrokenSequence,
    bool? brokenInScope,
    _i3.AuditChainReason? reasonCode,
    required DateTime verifiedAt,
  }) = _AdminAuditChainStatusImpl;

  factory AdminAuditChainStatus.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return AdminAuditChainStatus(
      state: _i2.AuditIntegrityState.fromJson(
        (jsonSerialization['state'] as String),
      ),
      checkedRows: jsonSerialization['checkedRows'] as int?,
      headSequence: jsonSerialization['headSequence'] as int?,
      firstBrokenSequence: jsonSerialization['firstBrokenSequence'] as int?,
      brokenInScope: jsonSerialization['brokenInScope'] == null
          ? null
          : _i1.BoolJsonExtension.fromJson(jsonSerialization['brokenInScope']),
      reasonCode: jsonSerialization['reasonCode'] == null
          ? null
          : _i3.AuditChainReason.fromJson(
              (jsonSerialization['reasonCode'] as String),
            ),
      verifiedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['verifiedAt'],
      ),
    );
  }

  _i2.AuditIntegrityState state;

  int? checkedRows;

  int? headSequence;

  int? firstBrokenSequence;

  bool? brokenInScope;

  _i3.AuditChainReason? reasonCode;

  DateTime verifiedAt;

  /// Returns a shallow copy of this [AdminAuditChainStatus]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AdminAuditChainStatus copyWith({
    _i2.AuditIntegrityState? state,
    int? checkedRows,
    int? headSequence,
    int? firstBrokenSequence,
    bool? brokenInScope,
    _i3.AuditChainReason? reasonCode,
    DateTime? verifiedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AdminAuditChainStatus',
      'state': state.toJson(),
      if (checkedRows != null) 'checkedRows': checkedRows,
      if (headSequence != null) 'headSequence': headSequence,
      if (firstBrokenSequence != null)
        'firstBrokenSequence': firstBrokenSequence,
      if (brokenInScope != null) 'brokenInScope': brokenInScope,
      if (reasonCode != null) 'reasonCode': reasonCode?.toJson(),
      'verifiedAt': verifiedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AdminAuditChainStatus',
      'state': state.toJson(),
      if (checkedRows != null) 'checkedRows': checkedRows,
      if (headSequence != null) 'headSequence': headSequence,
      if (firstBrokenSequence != null)
        'firstBrokenSequence': firstBrokenSequence,
      if (brokenInScope != null) 'brokenInScope': brokenInScope,
      if (reasonCode != null) 'reasonCode': reasonCode?.toJson(),
      'verifiedAt': verifiedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AdminAuditChainStatusImpl extends AdminAuditChainStatus {
  _AdminAuditChainStatusImpl({
    required _i2.AuditIntegrityState state,
    int? checkedRows,
    int? headSequence,
    int? firstBrokenSequence,
    bool? brokenInScope,
    _i3.AuditChainReason? reasonCode,
    required DateTime verifiedAt,
  }) : super._(
         state: state,
         checkedRows: checkedRows,
         headSequence: headSequence,
         firstBrokenSequence: firstBrokenSequence,
         brokenInScope: brokenInScope,
         reasonCode: reasonCode,
         verifiedAt: verifiedAt,
       );

  /// Returns a shallow copy of this [AdminAuditChainStatus]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AdminAuditChainStatus copyWith({
    _i2.AuditIntegrityState? state,
    Object? checkedRows = _Undefined,
    Object? headSequence = _Undefined,
    Object? firstBrokenSequence = _Undefined,
    Object? brokenInScope = _Undefined,
    Object? reasonCode = _Undefined,
    DateTime? verifiedAt,
  }) {
    return AdminAuditChainStatus(
      state: state ?? this.state,
      checkedRows: checkedRows is int? ? checkedRows : this.checkedRows,
      headSequence: headSequence is int? ? headSequence : this.headSequence,
      firstBrokenSequence: firstBrokenSequence is int?
          ? firstBrokenSequence
          : this.firstBrokenSequence,
      brokenInScope: brokenInScope is bool?
          ? brokenInScope
          : this.brokenInScope,
      reasonCode: reasonCode is _i3.AuditChainReason?
          ? reasonCode
          : this.reasonCode,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
