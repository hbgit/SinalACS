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

/// Versão dos termos anunciada ao paciente (LGPD-RF18, #46). O TEXTO jurídico
/// não fica aqui: vive no app do paciente. Aqui só o anúncio e a revisão.
abstract class TermsVersion implements _i1.SerializableModel {
  TermsVersion._({
    this.id,
    required this.version,
    required this.summary,
    required this.effectiveFrom,
    required this.createdBy,
    required this.createdAt,
    this.legallyReviewedAt,
    this.legallyReviewedBy,
    this.publishedAt,
    this.publishedBy,
  });

  factory TermsVersion({
    _i1.UuidValue? id,
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required _i1.UuidValue createdBy,
    required DateTime createdAt,
    DateTime? legallyReviewedAt,
    _i1.UuidValue? legallyReviewedBy,
    DateTime? publishedAt,
    _i1.UuidValue? publishedBy,
  }) = _TermsVersionImpl;

  factory TermsVersion.fromJson(Map<String, dynamic> jsonSerialization) {
    return TermsVersion(
      id: jsonSerialization['id'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      version: jsonSerialization['version'] as String,
      summary: jsonSerialization['summary'] as String,
      effectiveFrom: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['effectiveFrom'],
      ),
      createdBy: _i1.UuidValueJsonExtension.fromJson(
        jsonSerialization['createdBy'],
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      legallyReviewedAt: jsonSerialization['legallyReviewedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['legallyReviewedAt'],
            ),
      legallyReviewedBy: jsonSerialization['legallyReviewedBy'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['legallyReviewedBy'],
            ),
      publishedAt: jsonSerialization['publishedAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['publishedAt'],
            ),
      publishedBy: jsonSerialization['publishedBy'] == null
          ? null
          : _i1.UuidValueJsonExtension.fromJson(
              jsonSerialization['publishedBy'],
            ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  _i1.UuidValue? id;

  String version;

  String summary;

  DateTime effectiveFrom;

  _i1.UuidValue createdBy;

  DateTime createdAt;

  DateTime? legallyReviewedAt;

  _i1.UuidValue? legallyReviewedBy;

  DateTime? publishedAt;

  _i1.UuidValue? publishedBy;

  /// Returns a shallow copy of this [TermsVersion]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TermsVersion copyWith({
    _i1.UuidValue? id,
    String? version,
    String? summary,
    DateTime? effectiveFrom,
    _i1.UuidValue? createdBy,
    DateTime? createdAt,
    DateTime? legallyReviewedAt,
    _i1.UuidValue? legallyReviewedBy,
    DateTime? publishedAt,
    _i1.UuidValue? publishedBy,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TermsVersion',
      if (id != null) 'id': id?.toJson(),
      'version': version,
      'summary': summary,
      'effectiveFrom': effectiveFrom.toJson(),
      'createdBy': createdBy.toJson(),
      'createdAt': createdAt.toJson(),
      if (legallyReviewedAt != null)
        'legallyReviewedAt': legallyReviewedAt?.toJson(),
      if (legallyReviewedBy != null)
        'legallyReviewedBy': legallyReviewedBy?.toJson(),
      if (publishedAt != null) 'publishedAt': publishedAt?.toJson(),
      if (publishedBy != null) 'publishedBy': publishedBy?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TermsVersionImpl extends TermsVersion {
  _TermsVersionImpl({
    _i1.UuidValue? id,
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required _i1.UuidValue createdBy,
    required DateTime createdAt,
    DateTime? legallyReviewedAt,
    _i1.UuidValue? legallyReviewedBy,
    DateTime? publishedAt,
    _i1.UuidValue? publishedBy,
  }) : super._(
         id: id,
         version: version,
         summary: summary,
         effectiveFrom: effectiveFrom,
         createdBy: createdBy,
         createdAt: createdAt,
         legallyReviewedAt: legallyReviewedAt,
         legallyReviewedBy: legallyReviewedBy,
         publishedAt: publishedAt,
         publishedBy: publishedBy,
       );

  /// Returns a shallow copy of this [TermsVersion]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TermsVersion copyWith({
    Object? id = _Undefined,
    String? version,
    String? summary,
    DateTime? effectiveFrom,
    _i1.UuidValue? createdBy,
    DateTime? createdAt,
    Object? legallyReviewedAt = _Undefined,
    Object? legallyReviewedBy = _Undefined,
    Object? publishedAt = _Undefined,
    Object? publishedBy = _Undefined,
  }) {
    return TermsVersion(
      id: id is _i1.UuidValue? ? id : this.id,
      version: version ?? this.version,
      summary: summary ?? this.summary,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      legallyReviewedAt: legallyReviewedAt is DateTime?
          ? legallyReviewedAt
          : this.legallyReviewedAt,
      legallyReviewedBy: legallyReviewedBy is _i1.UuidValue?
          ? legallyReviewedBy
          : this.legallyReviewedBy,
      publishedAt: publishedAt is DateTime? ? publishedAt : this.publishedAt,
      publishedBy: publishedBy is _i1.UuidValue?
          ? publishedBy
          : this.publishedBy,
    );
  }
}
