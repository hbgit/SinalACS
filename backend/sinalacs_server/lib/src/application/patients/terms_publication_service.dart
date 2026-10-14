import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show consentPolicyVersion;
import 'package:sinalacs_server/src/application/patients/terms_change_schedule.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Tamanho máximo do resumo da mudança dos termos.
const int termsSummaryMaxLength = 280;

/// Linha de `terms_versions` como a camada de aplicação a enxerga.
class TermsVersionSnapshot {
  const TermsVersionSnapshot({
    required this.id,
    required this.version,
    required this.summary,
    required this.effectiveFrom,
    required this.createdAt,
    this.legallyReviewedAt,
    this.legallyReviewedBy,
    this.publishedAt,
    this.publishedBy,
  });

  final String id;
  final String version;
  final String summary;
  final DateTime effectiveFrom;
  final DateTime createdAt;
  final DateTime? legallyReviewedAt;
  final String? legallyReviewedBy;
  final DateTime? publishedAt;
  final String? publishedBy;
}

/// Persistência das versões dos termos. A implementação ORM fica em
/// `infrastructure/` (Tasks 2.3/2.4).
abstract interface class TermsVersionStore {
  Future<String> insertDraft({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
    required String createdBy,
    required DateTime createdAt,
  });

  Future<TermsVersionSnapshot?> findById(String id);

  Future<bool> versionExists(String version);

  /// Atômico: só marca se ainda não revisada nem publicada.
  Future<bool> markReviewed(String id, {required String reviewedBy, required DateTime at});

  /// Atômico: só publica se revisada e ainda não publicada.
  Future<bool> markPublished(String id, {required String publishedBy, required DateTime at});

  Future<List<TermsVersionSnapshot>> list();

  /// A publicada de maior `publishedAt` cuja vigência ainda não começou, ou
  /// `null`. É assim que "uma só agenda ativa" se resolve: a última publicada
  /// substitui a anterior, sem coluna de substituição.
  Future<TermsVersionSnapshot?> currentPublished(DateTime now);
}

/// Rascunho, revisão jurídica e publicação das versões dos termos (LGPD-RF18,
/// #46). Só `admin`. O resumo e o texto nunca entram na auditoria.
class TermsPublicationService {
  TermsPublicationService({
    required TermsVersionStore store,
    required AuditTrail audit,
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _clock = clock ?? DateTime.now;

  final TermsVersionStore _store;
  final AuditTrail _audit;
  final DateTime Function() _clock;

  /// Rascunha uma versão. Não impõe os 15 dias: isso é da publicação.
  Future<TermsVersionSnapshot> draft(
    AuthenticatedUser user, {
    required String version,
    required String summary,
    required DateTime effectiveFrom,
  }) async {
    await _requireAdmin(user, null);
    final cleanVersion = version.trim();
    final cleanSummary = summary.trim();
    if (cleanVersion.isEmpty) {
      throw AdminInvalidRequestException(message: 'Informe o número da versão.');
    }
    if (cleanVersion == consentPolicyVersion) {
      throw AdminInvalidRequestException(message: 'Esta já é a versão vigente dos termos.');
    }
    if (cleanSummary.isEmpty) {
      throw AdminInvalidRequestException(message: 'Informe o resumo da mudança.');
    }
    if (cleanSummary.length > termsSummaryMaxLength) {
      throw AdminInvalidRequestException(
        message: 'O resumo pode ter no máximo $termsSummaryMaxLength caracteres.',
      );
    }
    final now = _clock();
    if (!effectiveFrom.isAfter(now)) {
      throw AdminInvalidRequestException(message: 'A vigência deve estar no futuro.');
    }
    if (await _store.versionExists(cleanVersion)) {
      throw AdminInvalidRequestException(message: 'Já existe uma versão com este número.');
    }
    final id = await _store.insertDraft(
      version: cleanVersion,
      summary: cleanSummary,
      effectiveFrom: effectiveFrom.toUtc(),
      createdBy: user.id,
      createdAt: now.toUtc(),
    );
    await _write(user, id, 'drafted');
    return (await _store.findById(id))!;
  }

  /// Registra a revisão jurídica. Nunca sobrescreve quem/quando.
  Future<TermsVersionSnapshot> markReviewed(AuthenticatedUser user, String id) async {
    await _requireAdmin(user, id);
    final row = await _find(id);
    if (row.publishedAt != null || row.legallyReviewedAt != null) {
      throw AdminInvalidRequestException(message: 'A versão já foi revisada.');
    }
    if (!await _store.markReviewed(id, reviewedBy: user.id, at: _clock().toUtc())) {
      throw AdminInvalidRequestException(message: 'A versão já foi revisada.');
    }
    await _write(user, id, 'reviewed');
    return (await _store.findById(id))!;
  }

  /// Publica uma versão revisada, com vigência a pelo menos 15 dias.
  Future<TermsVersionSnapshot> publish(AuthenticatedUser user, String id) async {
    await _requireAdmin(user, id);
    final row = await _find(id);
    if (row.publishedAt != null) {
      throw AdminInvalidRequestException(message: 'A versão já foi publicada.');
    }
    if (row.legallyReviewedAt == null) {
      await _write(user, id, 'denied_not_reviewed');
      throw AdminInvalidRequestException(
        message: 'A versão ainda não foi revisada juridicamente.',
      );
    }
    final now = _clock().toUtc();
    try {
      // Reaproveita o validador da regra dos 15 dias.
      TermsChangeSchedule(
        version: row.version,
        publishedAt: now,
        effectiveFrom: row.effectiveFrom,
        summary: row.summary,
      );
    } on ArgumentError {
      await _write(user, id, 'denied_notice_period');
      throw AdminInvalidRequestException(message: 'A vigência exige 15 dias de antecedência.');
    }
    if (!await _store.markPublished(id, publishedBy: user.id, at: now)) {
      throw AdminInvalidRequestException(message: 'A versão já foi publicada.');
    }
    await _write(user, id, 'published');
    return (await _store.findById(id))!;
  }

  Future<List<TermsVersionSnapshot>> list(AuthenticatedUser user) async {
    await _requireAdmin(user, null, actionType: 'read');
    final rows = await _store.list();
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'terms_version',
      result: 'granted',
    ));
    return rows;
  }

  Future<TermsVersionSnapshot> _find(String id) async {
    final row = await _store.findById(id);
    if (row == null) {
      throw AdminInvalidRequestException(message: 'Versão não encontrada.');
    }
    return row;
  }

  Future<void> _write(AuthenticatedUser user, String id, String result) =>
      _audit.recordSafely(AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'terms_version',
        resourceId: _uuid.hasMatch(id) ? id : null,
        result: result,
      ));

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Só `admin`. Grava a negação (await) antes de lançar; `resourceId` só se UUID.
  Future<void> _requireAdmin(
    AuthenticatedUser user,
    String? id, {
    String actionType = 'write',
  }) async {
    if (user.role == UserRole.admin) return;
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: actionType,
      resourceType: 'terms_version',
      resourceId: id != null && _uuid.hasMatch(id) ? id : null,
      result: 'denied_role',
    ));
    throw StateError('Sem permissão para esta operação dos termos.');
  }
}
