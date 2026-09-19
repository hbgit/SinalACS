import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// O que o login precisa saber sobre uma credencial, sem `application/`
/// conhecer o ORM.
class AcsCredentialRecord {
  const AcsCredentialRecord({
    required this.acsId,
    required this.microAreaId,
    required this.active,
    required this.digest,
    required this.failedAttempts,
    required this.lockedUntil,
  });

  final String acsId;

  /// `users.microAreaId` do ACS. `null` = não territorializado, e sem
  /// território não há fila (INV-01).
  final String? microAreaId;

  final bool active;
  final PasswordDigest digest;
  final int failedAttempts;
  final DateTime? lockedUntil;
}

/// Acesso à credencial do ACS e ao estado de bloqueio.
abstract interface class AcsCredentialStore {
  /// Credencial do ACS dono desta matrícula, ou `null` se não existir.
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId);

  /// Grava a tentativa falha e o bloqueio resultante. A política (quantas
  /// tentativas, quanto tempo) é do serviço; o store só persiste.
  Future<void> registerFailedAttempt(
    String acsId, {
    required int failedAttempts,
    required DateTime? lockedUntil,
  });

  /// Zera o contador e o bloqueio depois de um login válido.
  Future<void> registerSuccessfulLogin(String acsId, DateTime at);

  /// Cria ou substitui a credencial (usado pelo seed e por uma futura troca de
  /// senha).
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at);
}

/// Login institucional do ACS (RF07): matrícula + senha.
///
/// Substitui `auth.developmentLogin` no caminho real. O que este serviço
/// garante, e que os testes verificam um a um:
///
/// 1. Matrícula inexistente e senha errada produzem a **mesma** exceção e a
///    **mesma** mensagem; o caminho da inexistente ainda deriva um hash
///    descartado, para o tempo de resposta não dizer o que a mensagem cala.
/// 2. A conta bloqueia depois de [maxFailedAttempts] falhas, por
///    [lockDuration] — a exigência de "registro de tentativas de acesso" de
///    `spec/lgpd_design.md` e o achado F6 de `spec/security_assessment.md`.
/// 3. Inatividade e ausência de território só são reveladas **depois** de a
///    senha conferir.
/// 4. Cada desfecho vira uma linha em `audit_logs` (RF17), pela mesma trilha
///    encadeada que os outros serviços usam.
class InstitutionalAuthService {
  InstitutionalAuthService({
    required this.store,
    required this.hasher,
    required this.audit,
  });

  final AcsCredentialStore store;
  final PasswordHasher hasher;
  final AuditTrail audit;

  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 15);

  /// Marcador de ausência de identificador de aparelho — mesma convenção de
  /// `orm_onboarding_store.dart` ('nao-aplicavel-onboarding').
  static const deviceIdAbsent = 'nao-aplicavel-login-institucional';

  static const _invalidCredentials = 'Matrícula ou senha inválidos.';

  Future<AuthenticatedUser> login({
    required String matricula,
    required String password,
    String? deviceId,
    DateTime? now,
  }) async {
    final enrollmentId = matricula.trim();
    if (enrollmentId.isEmpty || password.isEmpty) {
      throw AuthenticationFailedException(
        message: 'Informe matrícula e senha.',
      );
    }

    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByEnrollmentId(enrollmentId);

    if (record == null) {
      // Derivação descartada de propósito: sem ela a resposta para uma
      // matrícula inexistente volta em microssegundos enquanto a de uma
      // matrícula real demora o tempo do Argon2id — o relógio entregaria a
      // lista de matrículas que a mensagem única existe para esconder.
      await hasher.derive(password);
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    final lockedUntil = record.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(at)) {
      await _recordAudit(record.acsId, 'denied_locked');
      throw AuthenticationFailedException(
        message: 'Acesso temporariamente bloqueado por tentativas inválidas. '
            'Tente novamente em alguns minutos.',
      );
    }

    // `matches` fica FORA de qualquer try/catch de propósito: uma linha de
    // credencial corrompida (salt curto → `ArgumentError`, base64 inválido →
    // `FormatException`) é **erro de servidor**, não senha errada. Transformar
    // a corrupção em "senha errada" gastaria uma tentativa, e cinco linhas
    // corrompidas bloqueariam um ACS por um defeito de dado — um ataque ao
    // acesso que não veio de atacante nenhum. A exceção sobe e vira erro 500.
    //
    // Limite conhecido, e ele fica aqui de propósito: se `hashBase64`
    // decodificar para um comprimento diferente de 32 bytes, `matches` devolve
    // `false` sem lançar, e essa é a única forma de corrupção que conta como
    // tentativa em vez de estourar. Quem consegue distinguir as duas coisas é
    // a camada que carrega a linha (o store do ORM), onde a validação de
    // comprimento deve morar — corrigir isso aqui exigiria adivinhar o
    // comprimento do hash por dentro do serviço de login.
    if (!await hasher.matches(password, record.digest)) {
      final attempts = record.failedAttempts + 1;
      await store.registerFailedAttempt(
        record.acsId,
        failedAttempts: attempts,
        lockedUntil:
            attempts >= maxFailedAttempts ? at.add(lockDuration) : null,
      );
      await _recordAudit(record.acsId, 'denied_credentials');
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    // Daqui para baixo a senha já conferiu: distinguir os motivos deixa de
    // entregar informação a quem sonda.
    if (!record.active) {
      await _recordAudit(record.acsId, 'denied_inactive');
      throw AuthenticationFailedException(message: 'Este acesso está inativo.');
    }

    final microAreaId = record.microAreaId;
    if (microAreaId == null) {
      await _recordAudit(record.acsId, 'denied_no_territory');
      throw AuthenticationFailedException(
        message: 'Este acesso não está vinculado a uma microárea.',
      );
    }

    await store.registerSuccessfulLogin(record.acsId, at);
    await _recordAudit(record.acsId, 'granted');

    return AuthenticatedUser(
      id: record.acsId,
      role: UserRole.acs,
      microAreaId: microAreaId,
      deviceId: deviceId ?? deviceIdAbsent,
    );
  }

  /// Best-effort, como toda auditoria deste repositório: uma trilha fora do ar
  /// não pode impedir um ACS de entrar.
  Future<void> _recordAudit(String userId, String result) => audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'session',
          result: result,
        ),
      );
}
