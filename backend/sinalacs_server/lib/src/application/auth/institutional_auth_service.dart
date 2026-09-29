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

  /// Conta a tentativa falha e aplica o bloqueio resultante.
  ///
  /// A política continua sendo do serviço — as decisões chegam como
  /// parâmetro —, mas o *valor final do contador* não: o store precisa somar
  /// sobre o número que está na linha, não sobre o que o serviço leu antes.
  /// Passar o valor já somado é o que permite duas requisições concorrentes
  /// lerem a mesma base e gravarem `base + 1` as duas, e uma delas se perder
  /// (ver `OrmAcsCredentialStore.registerFailedAttempt`).
  ///
  /// [restartCounter] (`true` quando o bloqueio anterior já venceu) faz a
  /// contagem recomeçar em `1` em vez de somar à anterior; [maxFailedAttempts]
  /// é o limite a partir do qual a falha bloqueia; [lockUntil] é o instante do
  /// vencimento do bloqueio, já calculado pelo serviço ([lockDuration] dele).
  Future<void> registerFailedAttempt(
    String acsId, {
    required bool restartCounter,
    required int maxFailedAttempts,
    required DateTime lockUntil,
    required DateTime at,
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
///    A contagem em si é aplicada pelo store numa única instrução, para não
///    perder atualização sob concorrência.
/// 3. Inatividade, ausência de território e bloqueio só são revelados
///    **depois** de a senha conferir.
/// 4. Cada desfecho de uma tentativa que chegou a identificar uma conta vira
///    uma linha em `audit_logs` (RF17), pela mesma trilha encadeada que os
///    outros serviços usam. A exceção é a recusa por entrada em branco
///    (`Informe matrícula e senha.`), que responde antes de qualquer conta ser
///    identificada — e `audit_logs.userId` é obrigatório com FK para `users`,
///    então não há sujeito a quem atribuir a linha. É o mesmo limite do
///    caminho da matrícula inexistente, registrado no achado F6.
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

  /// Só chega a quem provou conhecer a senha (a ordem do `login` garante isso).
  static const _lockMessage = 'Acesso temporariamente bloqueado por tentativas '
      'inválidas. Tente novamente em alguns minutos.';

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
      //
      // Limite conhecido: `derive` deriva com o custo da **instância** (a
      // configuração do processo), enquanto `matches`, no caminho da matrícula
      // real, deriva com o custo **gravado na linha** — é justamente o que
      // permite subir o custo sem invalidar credencial antiga. Os dois tempos
      // só coincidem enquanto toda linha estiver no default do processo; no
      // dia em que uma linha carregar custo diferente, o caminho da matrícula
      // inexistente fica mensuravelmente mais rápido e o relógio reabre a
      // enumeração que a mensagem idêntica fecha. Não é corrigível aqui: no
      // caminho da inexistente não há linha de onde ler um custo. A saída é
      // arquitetural (o serviço conhecer o custo corrente), não local.
      await hasher.derive(password);
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    // O bloqueio é decidido aqui e **revelado só depois** de a senha conferir.
    // A ordem é a regra, não um detalhe: recusar pelo bloqueio antes de olhar a
    // senha faz cinco chutes contra uma matrícula existente responderem
    // "Acesso temporariamente bloqueado…", enquanto uma matrícula inexistente
    // continua respondendo "Matrícula ou senha inválidos." — cinco requisições
    // anônimas por candidata enumeram quem existe, que é exatamente o que a
    // mensagem única existe para esconder. No caminho da senha errada o
    // bloqueio ativo também não vira mensagem própria: ele só decide que a
    // tentativa **não é contada**.
    final lockedUntil = record.lockedUntil;
    final locked = lockedUntil != null && lockedUntil.isAfter(at);

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
      if (locked) {
        // Bloqueio ativo: a tentativa não é contada nem estende o castigo, e a
        // resposta é a genérica — anunciar o bloqueio a quem não provou
        // conhecer a senha reabriria a enumeração que a ordem acima fecha. A
        // trilha registra o motivo real, que é interno.
        await _recordAudit(record.acsId, 'denied_locked');
        throw AuthenticationFailedException(message: _invalidCredentials);
      }

      // Bloqueio vencido zera o contador. Sem isto, uma única tentativa errada
      // depois de cada expiração tranca de novo por mais `lockDuration`: uma
      // conta pode ficar presa indefinidamente com **uma** tentativa por
      // janela — negação de serviço contra o acesso do ACS, e o ACS que só
      // errou a senha uma vez por dia nunca mais entra. O bloqueio é para
      // frear rajada, não para acumular para sempre.
      //
      // O reinício viaja como decisão (`restartCounter`) porque quem aplica a
      // contagem é o store, numa única instrução: somar aqui, sobre o valor
      // lido acima, perderia tentativas concorrentes.
      final lockExpirou = lockedUntil != null && !lockedUntil.isAfter(at);
      await store.registerFailedAttempt(
        record.acsId,
        restartCounter: lockExpirou,
        maxFailedAttempts: maxFailedAttempts,
        lockUntil: at.add(lockDuration),
        at: at,
      );
      await _recordAudit(record.acsId, 'denied_credentials');
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    if (locked) {
      await _recordAudit(record.acsId, 'denied_locked');
      throw AuthenticationFailedException(message: _lockMessage);
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
