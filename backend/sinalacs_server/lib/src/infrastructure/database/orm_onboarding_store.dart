import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [OnboardingStore] sobre o ORM do Serverpod.
class OrmOnboardingStore implements OnboardingStore {
  OrmOnboardingStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<void> saveToken(StoredEnrollmentToken token) async {
    await EnrollmentToken.db.insertRow(
      _session(),
      EnrollmentToken(
        tokenHash: token.tokenHash,
        patientId: UuidValue.fromString(token.patientId),
        microAreaId: UuidValue.fromString(token.microAreaId),
        createdByAcsId: UuidValue.fromString(token.createdByAcsId),
        createdAt: DateTime.now().toUtc(),
        expiresAt: token.expiresAt,
      ),
    );
  }

  @override
  Future<StoredEnrollmentToken?> findValidToken(String tokenHash, DateTime now) async {
    final row = await EnrollmentToken.db.findFirstRow(
      _session(),
      where: (t) => t.tokenHash.equals(tokenHash) & t.consumedAt.equals(null),
    );
    if (row == null || !row.expiresAt.isAfter(now)) return null;

    return StoredEnrollmentToken(
      tokenHash: row.tokenHash,
      patientId: row.patientId.uuid,
      microAreaId: row.microAreaId.uuid,
      createdByAcsId: row.createdByAcsId.uuid,
      expiresAt: row.expiresAt,
      consumedAt: row.consumedAt,
    );
  }

  @override
  Future<void> consumeToken(String tokenHash, DateTime consumedAt) async {
    final session = _session();
    final row = await EnrollmentToken.db.findFirstRow(
      session,
      where: (t) => t.tokenHash.equals(tokenHash),
    );
    if (row == null) return;
    await EnrollmentToken.db.updateRow(session, row.copyWith(consumedAt: consumedAt));
  }

  @override
  Future<String?> microAreaOfPatient(String patientId) async {
    final user = await User.db.findFirstRow(
      _session(),
      where: (t) => t.id.equals(UuidValue.fromString(patientId)) & t.role.equals(UserRole.patient),
    );
    return user?.microAreaId?.uuid;
  }

  @override
  Future<void> recordConsent(ConsentLogEntry entry) async {
    await ConsentLog.db.insertRow(
      _session(),
      ConsentLog(
        userId: UuidValue.fromString(entry.userId),
        purpose: entry.purpose.name,
        action: entry.action,
        version: entry.version,
        timestamp: entry.timestamp,
        // IP e user agent não se aplicam a este evento de domínio — o
        // request HTTP em si já é auditado em audit_logs por outros
        // caminhos; aqui os campos exigidos pelo schema ficam com um
        // marcador explícito de ausência, não um valor fabricado.
        ipHash: 'nao-aplicavel-onboarding',
        userAgent: 'nao-aplicavel-onboarding',
        signature: '',
      ),
    );
  }
}
