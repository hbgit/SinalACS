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

/// Aviso de mudança dos termos (LGPD-RF18): a versão que passa a valer, a data
/// de vigência e um resumo do que muda. Publicado com pelo menos 15 dias de
/// antecedência (`TermsChangeSchedule`). Só texto público; nada do titular.
abstract class TermsChangeNotice implements _i1.SerializableModel {
  TermsChangeNotice._({
    required this.version,
    required this.effectiveFrom,
    required this.summary,
  });

  factory TermsChangeNotice({
    required String version,
    required DateTime effectiveFrom,
    required String summary,
  }) = _TermsChangeNoticeImpl;

  factory TermsChangeNotice.fromJson(Map<String, dynamic> jsonSerialization) {
    return TermsChangeNotice(
      version: jsonSerialization['version'] as String,
      effectiveFrom: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['effectiveFrom'],
      ),
      summary: jsonSerialization['summary'] as String,
    );
  }

  String version;

  DateTime effectiveFrom;

  String summary;

  /// Returns a shallow copy of this [TermsChangeNotice]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TermsChangeNotice copyWith({
    String? version,
    DateTime? effectiveFrom,
    String? summary,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TermsChangeNotice',
      'version': version,
      'effectiveFrom': effectiveFrom.toJson(),
      'summary': summary,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TermsChangeNoticeImpl extends TermsChangeNotice {
  _TermsChangeNoticeImpl({
    required String version,
    required DateTime effectiveFrom,
    required String summary,
  }) : super._(
         version: version,
         effectiveFrom: effectiveFrom,
         summary: summary,
       );

  /// Returns a shallow copy of this [TermsChangeNotice]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TermsChangeNotice copyWith({
    String? version,
    DateTime? effectiveFrom,
    String? summary,
  }) {
    return TermsChangeNotice(
      version: version ?? this.version,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      summary: summary ?? this.summary,
    );
  }
}
