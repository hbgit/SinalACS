import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/terms_publication_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// [TermsVersionStore] sobre o Postgres (#46).
///
/// Revisar e publicar são UMA instrução SQL cada, condicionada ao estado, para
/// serem atômicas entre instâncias. As colunas são `timestamp without time
/// zone`: tudo entra e sai em UTC. Um id que não é UUID devolve `null`/`false`
/// em vez de estourar o cast do Postgres.
class OrmTermsVersionStore implements TermsVersionStore {
  OrmTermsVersionStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  static const _columns =
      '"id", "version", "summary", "effectiveFrom", "createdBy", "createdAt", '
      '"legallyReviewedAt", "legallyReviewedBy", "publishedAt", "publishedBy"';

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  Future<String> insertDraft({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required String createdBy,
    required DateTime createdAt,
  }) async {
    final row = await TermsVersion.db.insertRow(
      _session(),
      TermsVersion(
        version: version,
        summary: summary,
        effectiveFrom: effectiveFrom.toUtc(),
        createdBy: UuidValue.fromString(createdBy),
        createdAt: createdAt.toUtc(),
      ),
    );
    return row.id!.toString();
  }

  @override
  Future<TermsVersionSnapshot?> findById(String id) async {
    if (!_uuid.hasMatch(id)) return null;
    final rows = await _session().db.unsafeQuery(
      'SELECT $_columns FROM terms_versions WHERE "id" = @id::uuid',
      parameters: QueryParameters.named({'id': id}),
    );
    return rows.isEmpty ? null : _snapshot(rows.first.toColumnMap());
  }

  @override
  Future<bool> versionExists(String version) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT 1 FROM terms_versions WHERE "version" = @version',
      parameters: QueryParameters.named({'version': version}),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> markReviewed(String id, {required String reviewedBy, required DateTime at}) async {
    if (!_uuid.hasMatch(id) || !_uuid.hasMatch(reviewedBy)) return false;
    final rows = await _session().db.unsafeQuery(
      '''
      UPDATE terms_versions
      SET "legallyReviewedAt" = @at, "legallyReviewedBy" = @by::uuid
      WHERE "id" = @id::uuid AND "legallyReviewedAt" IS NULL AND "publishedAt" IS NULL
      RETURNING "id"
      ''',
      parameters: QueryParameters.named({'id': id, 'by': reviewedBy, 'at': at.toUtc()}),
    );
    return rows.length == 1;
  }

  @override
  Future<bool> markPublished(String id, {required String publishedBy, required DateTime at}) async {
    if (!_uuid.hasMatch(id) || !_uuid.hasMatch(publishedBy)) return false;
    final rows = await _session().db.unsafeQuery(
      '''
      UPDATE terms_versions
      SET "publishedAt" = @at, "publishedBy" = @by::uuid
      WHERE "id" = @id::uuid AND "legallyReviewedAt" IS NOT NULL AND "publishedAt" IS NULL
      RETURNING "id"
      ''',
      parameters: QueryParameters.named({'id': id, 'by': publishedBy, 'at': at.toUtc()}),
    );
    return rows.length == 1;
  }

  @override
  Future<List<TermsVersionSnapshot>> list() async {
    final rows = await _session().db.unsafeQuery(
      'SELECT $_columns FROM terms_versions ORDER BY "effectiveFrom" DESC, "createdAt" DESC',
    );
    return [for (final r in rows) _snapshot(r.toColumnMap())];
  }

  @override
  Future<TermsVersionSnapshot?> currentPublished(DateTime now) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT $_columns FROM terms_versions
      WHERE "publishedAt" IS NOT NULL
        AND "publishedAt" <= @now
        AND "effectiveFrom" > @now
      ORDER BY "publishedAt" DESC, "createdAt" DESC
      LIMIT 1
      ''',
      parameters: QueryParameters.named({'now': now.toUtc()}),
    );
    return rows.isEmpty ? null : _snapshot(rows.first.toColumnMap());
  }

  TermsVersionSnapshot _snapshot(Map<String, dynamic> m) => TermsVersionSnapshot(
        id: m['id'].toString(),
        version: m['version'] as String,
        summary: m['summary'] as String,
        effectiveFrom: _utc(m['effectiveFrom'])!,
        createdAt: _utc(m['createdAt'])!,
        legallyReviewedAt: _utc(m['legallyReviewedAt']),
        legallyReviewedBy: m['legallyReviewedBy']?.toString(),
        publishedAt: _utc(m['publishedAt']),
        publishedBy: m['publishedBy']?.toString(),
      );

  DateTime? _utc(Object? v) {
    if (v == null) return null;
    final d = v as DateTime;
    return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
  }
}
