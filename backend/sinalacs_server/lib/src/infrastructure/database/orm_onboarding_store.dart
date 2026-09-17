import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [OnboardingStore] sobre o ORM do Serverpod.
///
/// Segue o mesmo arranjo de `OrmAlertStore`/`OrmVisitStore`: a sessão é
/// obtida por chamada, e uma [Transaction] opcional permite que o consumo do
/// convite e a gravação dos 3 `consent_logs` participem de uma única
/// transação aberta pelo endpoint — mesmo padrão de `AlertsEndpoint.createRedAlert`.
class OrmOnboardingStore implements OnboardingStore {
  OrmOnboardingStore({
    required Session Function() session,
    Transaction? transaction,
  })  : _session = session,
        _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

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
      transaction: _transaction,
    );
  }

  @override
  Future<StoredEnrollmentToken?> consumeIfValid(String tokenHash, DateTime now) async {
    // UPDATE condicional em vez de "ler depois escrever": o ORM não expõe um
    // `WHERE` em `updateRow`, e duas leituras/escritas separadas (como esta
    // store fazia antes do fix round 1) deixam uma janela onde duas chamadas
    // concorrentes a `completeEnrollment` com o mesmo token passam as duas
    // pela validação antes de qualquer uma consumir. Uma única instrução
    // condicional resolve isso no próprio Postgres: a segunda UPDATE
    // concorrente ou espera a primeira committar (lock de linha) e então
    // reavalia o `WHERE` sob o estado já consumido — 0 linhas afetadas — ou,
    // sob READ COMMITTED, simplesmente não encontra a linha elegível. Mesmo
    // mecanismo de `OrmAlertOutbox.claimDue` (lá com `FOR UPDATE SKIP
    // LOCKED`; aqui basta o `WHERE` condicional porque só uma linha está em
    // disputa, não um lote).
    final rows = await _session().db.unsafeQuery(
      '''
      UPDATE enrollment_tokens
         SET "consumedAt" = @now
       WHERE "tokenHash" = @tokenHash
         AND "consumedAt" IS NULL
         AND "expiresAt" > @now
   RETURNING "patientId", "microAreaId", "createdByAcsId", "expiresAt";
      ''',
      parameters: QueryParameters.named({'tokenHash': tokenHash, 'now': now}),
      transaction: _transaction,
    );
    if (rows.isEmpty) return null;

    final row = rows.single;
    return StoredEnrollmentToken(
      tokenHash: tokenHash,
      patientId: row[0].toString(),
      microAreaId: row[1].toString(),
      createdByAcsId: row[2].toString(),
      expiresAt: row[3] as DateTime,
      consumedAt: now,
    );
  }

  @override
  Future<String?> microAreaOfPatient(String patientId) async {
    final user = await User.db.findFirstRow(
      _session(),
      where: (t) => t.id.equals(UuidValue.fromString(patientId)) & t.role.equals(UserRole.patient),
      transaction: _transaction,
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
      transaction: _transaction,
    );
  }
}
