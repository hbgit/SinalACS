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

/// Versão dos termos de uso no backoffice (#46, LGPD-RF18). Sem os campos de
/// quem revisou/publicou: o admin vê quando, não a identidade.
abstract class TermsVersionEntry implements _i1.SerializableModel {
  TermsVersionEntry._({
    required this.id,
    required this.version,
    required this.summary,
    required this.effectiveFrom,
    required this.createdAt,
    this.legallyReviewedAt,
    this.publishedAt,
  });

  factory TermsVersionEntry({
    required String id,
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required DateTime createdAt,
    DateTime? legallyReviewedAt,
    DateTime? publishedAt,
  }) = _TermsVersionEntryImpl;

  factory TermsVersionEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return TermsVersionEntry(
      id: jsonSerialization['id'] as String,
      version: jsonSerialization['version'] as String,
      summary: jsonSerialization['summary'] as String,
      effectiveFrom: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['effectiveFrom'],
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      legallyReviewedAt: jsonSerialization['legallyReviewedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['legallyReviewedAt'],
            ),
      publishedAt: jsonSerialization['publishedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['publishedAt'],
            ),
    );
  }

  String id;

  String version;

  String summary;

  DateTime effectiveFrom;

  DateTime createdAt;

  DateTime? legallyReviewedAt;

  DateTime? publishedAt;

  /// Returns a shallow copy of this [TermsVersionEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TermsVersionEntry copyWith({
    String? id,
    String? version,
    String? summary,
    DateTime? effectiveFrom,
    DateTime? createdAt,
    DateTime? legallyReviewedAt,
    DateTime? publishedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TermsVersionEntry',
      'id': id,
      'version': version,
      'summary': summary,
      'effectiveFrom': effectiveFrom.toJson(),
      'createdAt': createdAt.toJson(),
      if (legallyReviewedAt != null)
        'legallyReviewedAt': legallyReviewedAt?.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TermsVersionEntryImpl extends TermsVersionEntry {
  _TermsVersionEntryImpl({
    required String id,
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required DateTime createdAt,
    DateTime? legallyReviewedAt,
    DateTime? publishedAt,
  }) : super._(
         id: id,
         version: version,
         summary: summary,
         effectiveFrom: effectiveFrom,
         createdAt: createdAt,
         legallyReviewedAt: legallyReviewedAt,
         publishedAt: publishedAt,
       );

  /// Returns a shallow copy of this [TermsVersionEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TermsVersionEntry copyWith({
    String? id,
    String? version,
    String? summary,
    DateTime? effectiveFrom,
    DateTime? createdAt,
    Object? legallyReviewedAt = _Undefined,
    Object? publishedAt = _Undefined,
  }) {
    return TermsVersionEntry(
      id: id ?? this.id,
      version: version ?? this.version,
      summary: summary ?? this.summary,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      createdAt: createdAt ?? this.createdAt,
      legallyReviewedAt: legallyReviewedAt is DateTime?
          ? legallyReviewedAt
          : this.legallyReviewedAt,
      publishedAt: publishedAt is DateTime? ? publishedAt : this.publishedAt,
    );
  }
}
