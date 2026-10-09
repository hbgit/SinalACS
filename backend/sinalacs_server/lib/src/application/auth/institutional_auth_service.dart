import 'dart:math';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Estado da MFA de um ACS, como está gravado.
class TotpEnrollment {
  const TotpEnrollment({required this.sealed, required this.enabled, required this.lastStep});

  final SealedSecret sealed;

  /// `false` = a ativação começou e não foi confirmada: a MFA ainda NÃO vale.
  final bool enabled;
  final int? lastStep;
}

/// Escrita do estado da MFA. Interface à parte de [AcsCredentialStore] de
/// propósito: quem só lê credencial (e os fakes que já existem) não muda.
abstract interface class TotpStore {
  /// Grava um segredo **pendente**. Devolve `false` sem escrever quando a MFA
  /// já está ativa na linha: uma ativação concorrente que confirmou antes não
  /// pode ser sobrescrita por quem só conhece a senha.
  Future<bool> saveSecret(String acsId, SealedSecret secret, DateTime at);

  /// Ativa a MFA com [pending], o segredo que o código conferiu. Devolve
  /// `false` sem escrever quando a linha já não está pendente com esse mesmo
  /// segredo (outra confirmação ganhou, ou um novo início trocou o segredo).
  Future<bool> enable(String acsId, SealedSecret pending, int step, DateTime at);

  /// Avança o último passo aceito para [step]. Devolve `true` só se a linha
  /// avançou; `false` = outra requisição já gravou este passo (ou um maior):
  /// o código é um replay e a sessão **não** pode ser emitida.
  Future<bool> registerStep(String acsId, int step);

  /// Apaga o estado da MFA da conta — as **quatro** colunas `totp*` voltam a
  /// NULL — e carimba `updatedAt` com [at]. É a redefinição pela coordenação
  /// (issue #43): o caminho que a recusa "Peça a redefinição à coordenação"
  /// não tinha.
  ///
  /// As quatro juntas, numa instrução: apagar só o segredo deixaria
  /// `totpEnabledAt` para trás e a conta continuaria com MFA **ativa**
  /// apontando para um segredo que não existe (o login passaria a exigir um
  /// código que ninguém consegue gerar); apagar só a ativação deixaria um
  /// segredo órfão na linha. Nenhuma política mora aqui: como nas outras
  /// escritas do estado, quem decide *quando* redefinir é o serviço.
  Future<void> clearTotp(String acsId, DateTime at);
}

/// Código de ativação vigente de uma conta de staff (#48).
class StaffActivationRecord {
  const StaffActivationRecord({required this.codeHash, required this.expiresAt});

  final String codeHash;
  final DateTime expiresAt;
}

/// Código de ativação de uso único da MFA do staff. Interface à parte, como
/// [TotpStore]: só a audiência `staff` a usa.
abstract interface class StaffActivationStore {
  /// Grava o hash do código e a validade, substituindo qualquer código anterior.
  Future<void> issue(
    String staffId, {
    required String codeHash,
    required DateTime expiresAt,
    required String issuedBy,
    required DateTime at,
  });

  /// Código vigente da conta, ou `null` (nunca emitido ou já consumido).
  Future<StaffActivationRecord?> find(String staffId);

  /// Apaga hash e validade; `issuedBy`/`issuedAt` ficam como último registro.
  Future<void> clear(String staffId);
}

/// Quem está entrando: o ACS (com território) ou o staff do backoffice.
enum CredentialAudience { acs, staff }

/// O que o login precisa saber sobre uma credencial, sem `application/`
/// conhecer o ORM.
class AcsCredentialRecord {
  const AcsCredentialRecord({
    required this.acsId,
    required this.microAreaId,
    required this.active,
    this.role = UserRole.acs,
    required this.digest,
    required this.failedAttempts,
    required this.lockedUntil,
    this.lockStreak = 0,
    this.totp,
  });

  final String acsId;

  /// `users.microAreaId` do ACS. `null` = não territorializado, e sem
  /// território não há fila (INV-01).
  final String? microAreaId;

  final bool active;

  /// `users.role` da conta. Na audiência `staff` decide quem entra
  /// (`coordinator` ou `admin`) e é o papel que vai no token; na audiência
  /// `acs` o store já só devolve linha de papel `acs`.
  final UserRole role;

  final PasswordDigest digest;
  final int failedAttempts;
  final DateTime? lockedUntil;

  /// Quantas vezes seguidas a conta bloqueou sem um login válido no meio.
  final int lockStreak;

  /// Estado da MFA. `null` = nenhum segredo gravado (sem MFA).
  final TotpEnrollment? totp;
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
///    [lockDuration] na primeira rodada e o dobro a cada rodada seguinte sem um
///    login válido no meio (até [maxLockDuration]; ver [lockDurationFor]) — a exigência de "registro de tentativas de acesso" de
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
    this.totpStore,
    this.activationStore,
    this.vault,
    this.requireMfa = false,
    this.audience = CredentialAudience.acs,
    Random? random,
  }) : _random = random ?? Random.secure();

  final AcsCredentialStore store;
  final PasswordHasher hasher;
  final AuditTrail audit;

  /// Escrita do estado da MFA. Obrigatório quando algum ACS tem MFA (ou para
  /// ativá-la); a falta dele com MFA ativa é erro de montagem ([StateError]).
  final TotpStore? totpStore;

  /// Código de ativação de uso único da MFA do staff (#48). Obrigatório na
  /// audiência `staff`; ignorado na `acs`.
  final StaffActivationStore? activationStore;

  /// Cofre do segredo TOTP. Mesma regra de [totpStore].
  final TotpSecretVault? vault;

  /// `REQUIRE_ACS_MFA`: ACS sem MFA ativa não entra; precisa ativá-la antes.
  final bool requireMfa;

  /// Para quem este serviço abre sessão. `staff` (backoffice) não tem
  /// território e tem MFA sempre obrigatória, independente de [requireMfa].
  final CredentialAudience audience;

  bool get _mfaObrigatoria => audience == CredentialAudience.staff || requireMfa;

  /// Sorteia o segredo TOTP. `Random.secure()` fora dos testes.
  final Random _random;

  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 15);

  /// Teto do bloqueio progressivo: bloquear para sempre transformaria o limite
  /// num ataque ao acesso do próprio ACS.
  static const maxLockDuration = Duration(hours: 24);

  /// Bloqueio da [streak]-ésima rodada seguida (0 = a primeira): `15 min × 2^streak`,
  /// no máximo [maxLockDuration]. Sequência negativa vale como zero.
  static Duration lockDurationFor(int streak) {
    final n = streak < 0 ? 0 : streak;
    // 2^7 × 15 min já passa de 24 h; limitar o expoente evita estouro em `<<`.
    if (n >= 7) return maxLockDuration;
    final d = lockDuration * (1 << n);
    return d > maxLockDuration ? maxLockDuration : d;
  }

  /// Marcador de ausência de identificador de aparelho — mesma convenção de
  /// `orm_onboarding_store.dart` ('nao-aplicavel-onboarding').
  static const deviceIdAbsent = 'nao-aplicavel-login-institucional';

  static const _invalidCredentials = 'Matrícula ou senha inválidos.';

  static const _invalidCode = 'Código de verificação inválido.';

  static const _invalidActivation = 'Código de ativação inválido ou expirado.';

  /// Só chega a quem provou conhecer a senha (a ordem do `login` garante isso).
  static const _lockMessage =
      'Acesso temporariamente bloqueado por tentativas '
      'inválidas. Tente novamente em alguns minutos.';

  Future<AuthenticatedUser> login({
    required String matricula,
    required String password,
    String? deviceId,
    String? totpCode,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await _authenticatePassword(
      matricula: matricula,
      password: password,
      at: at,
    );

    // Só depois da senha: quem não a conhece recebe a mensagem única e nunca
    // fica sabendo se a conta tem MFA.
    final totp = record.totp;
    if (totp != null && totp.enabled) {
      final codigo = totpCode?.trim() ?? '';
      if (codigo.isEmpty) {
        // A senha conferiu; falta o código. Não é falha: não conta tentativa.
        throw MfaRequiredException(message: 'Informe o código do aplicativo autenticador.');
      }
      final segredo = await _vault().open(totp.sealed);
      final passo = Totp.verify(segredo, codigo, at, lastStep: totp.lastStep);
      if (passo == null) {
        await _registrarFalha(record, at);
        await _recordAudit(record.acsId, 'denied_totp');
        throw AuthenticationFailedException(message: _invalidCode);
      }
      // O `verify` acima leu `lastStep` antes; duas requisições com o mesmo
      // código passam as duas por ele. Quem decide é o `UPDATE` condicional:
      // só uma avança a linha, e a outra é replay (RFC 6238 §5.2).
      if (!await _totpStore().registerStep(record.acsId, passo)) {
        await _registrarFalha(record, at);
        await _recordAudit(record.acsId, 'denied_totp_replay');
        throw AuthenticationFailedException(message: _invalidCode);
      }
    } else if (_mfaObrigatoria) {
      await _recordAudit(record.acsId, 'denied_mfa_not_enrolled');
      throw MfaEnrollmentRequiredException(
        message: 'Ative a verificação em duas etapas antes de entrar.',
      );
    }

    await store.registerSuccessfulLogin(record.acsId, at);
    await _recordAudit(record.acsId, 'granted');

    final staff = audience == CredentialAudience.staff;
    return AuthenticatedUser(
      id: record.acsId,
      // `_authenticatePassword` só devolve staff com papel `coordinator` ou
      // `admin`.
      role: staff ? record.role : UserRole.acs,
      // Staff não tem território: a sessão dele nunca carrega microárea, nem
      // se a linha de `users` tiver uma. Para o ACS, `_authenticatePassword`
      // só devolve linha com território.
      microAreaId: staff ? null : record.microAreaId!,
      deviceId: deviceId ?? deviceIdAbsent,
    );
  }

  /// Começa a ativação da MFA. Exige matrícula **e senha** (o ACS ainda não tem
  /// token) e conta tentativa errada como o login. Só grava o segredo como
  /// "pendente": a MFA vale depois de [confirmTotpEnrollment].
  Future<TotpEnrollmentStart> beginTotpEnrollment({
    required String matricula,
    required String password,
    String? activationCode,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await _authenticatePassword(matricula: matricula, password: password, at: at);
    if (record.totp?.enabled ?? false) {
      throw AuthenticationFailedException(
        message: 'A verificação em duas etapas já está ativa. Peça a redefinição à coordenação.',
      );
    }
    await _exigirCodigoDeAtivacao(record, activationCode, at);
    final bytes = Uint8List.fromList(List<int>.generate(20, (_) => _random.nextInt(256)));
    if (!await _totpStore().saveSecret(record.acsId, await _vault().seal(bytes), at)) {
      // Uma confirmação concorrente ativou a MFA entre a leitura e a escrita.
      throw AuthenticationFailedException(
        message: 'A verificação em duas etapas já está ativa. Peça a redefinição à coordenação.',
      );
    }
    // Sobrescreve qualquer segredo pendente anterior: fica na trilha.
    await _recordAudit(record.acsId, 'mfa_enrollment_started');
    final base32 = Totp.base32(bytes);
    return TotpEnrollmentStart(
      secretBase32: base32,
      otpauthUri: Totp.otpauthUri(secretBase32: base32, account: matricula.trim()),
    );
  }

  /// Confirma a ativação com um código válido do segredo pendente.
  Future<void> confirmTotpEnrollment({
    required String matricula,
    required String password,
    required String code,
    String? activationCode,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await _authenticatePassword(matricula: matricula, password: password, at: at);
    final totp = record.totp;
    if (totp == null || totp.enabled) {
      throw AuthenticationFailedException(message: 'Não há ativação pendente para esta matrícula.');
    }
    await _exigirCodigoDeAtivacao(record, activationCode, at);
    final passo = Totp.verify(await _vault().open(totp.sealed), code, at);
    if (passo == null) {
      await _registrarFalha(record, at);
      await _recordAudit(record.acsId, 'denied_totp_enrollment');
      throw AuthenticationFailedException(message: _invalidCode);
    }
    if (!await _totpStore().enable(record.acsId, totp.sealed, passo, at)) {
      await _registrarFalha(record, at);
      await _recordAudit(record.acsId, 'denied_totp_enrollment_race');
      throw AuthenticationFailedException(message: 'Não há ativação pendente para esta matrícula.');
    }
    await activationStore?.clear(record.acsId);
    await _recordAudit(record.acsId, 'mfa_enabled');
  }

  /// Só a audiência staff exige o código. Erro conta como falha de login e vira
  /// auditoria; o texto é um só para não dizer se o código existiu, expirou ou
  /// já foi usado.
  Future<void> _exigirCodigoDeAtivacao(
    AcsCredentialRecord record,
    String? code,
    DateTime at,
  ) async {
    if (audience != CredentialAudience.staff) return;
    final store = activationStore ?? (throw StateError('staff sem store de código de ativação'));
    final vigente = await store.find(record.acsId);
    final ok = vigente != null &&
        code != null &&
        at.isBefore(vigente.expiresAt) &&
        StaffActivationCode.matches(code, vigente.codeHash);
    if (ok) return;
    await _registrarFalha(record, at);
    await _recordAudit(record.acsId, 'denied_staff_activation_code');
    throw AuthenticationFailedException(message: _invalidActivation);
  }

  TotpSecretVault _vault() => vault ?? (throw StateError('MFA ativa sem cofre configurado'));

  TotpStore _totpStore() =>
      totpStore ?? (throw StateError('MFA ativa sem store de TOTP configurado'));

  /// Tudo o que o login decide antes de abrir a sessão: entrada em branco,
  /// matrícula inexistente, senha errada (com a contagem e o bloqueio),
  /// bloqueio ativo, acesso inativo, papel que não é de staff (audiência
  /// `staff`) e ausência de território (audiência `acs`). Devolve a linha
  /// só quando a senha confere e nada disso recusa; nos outros casos lança
  /// exatamente o que o `login` sempre lançou. A ativação da MFA reaproveita
  /// este caminho: provar a senha ali custa o mesmo que no login.
  Future<AcsCredentialRecord> _authenticatePassword({
    required String matricula,
    required String password,
    required DateTime at,
  }) async {
    final enrollmentId = matricula.trim();
    if (enrollmentId.isEmpty || password.isEmpty) {
      throw AuthenticationFailedException(
        message: 'Informe matrícula e senha.',
      );
    }

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
      await _registrarFalha(record, at);
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

    // Só o coordenador e o administrador entram no backoffice. A recusa usa a
    // mensagem genérica de propósito, mesmo com a senha certa: dizer "papel
    // errado" confirmaria a quem tem a senha de um ACS que aquela matrícula
    // existe numa tabela que não é a dele. A trilha guarda o motivo real.
    if (audience == CredentialAudience.staff &&
        record.role != UserRole.coordinator &&
        record.role != UserRole.admin) {
      await _recordAudit(record.acsId, 'denied_role');
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    // Território é exigência do ACS (INV-01); o staff não tem microárea.
    if (audience == CredentialAudience.acs) {
      final microAreaId = record.microAreaId;
      if (microAreaId == null) {
        await _recordAudit(record.acsId, 'denied_no_territory');
        throw AuthenticationFailedException(
          message: 'Este acesso não está vinculado a uma microárea.',
        );
      }
    }

    return record;
  }

  /// Conta uma tentativa falha (senha errada ou código TOTP errado).
  /// Bloqueio vencido recomeça o contador — a mesma regra do ramo da senha
  /// errada, num lugar só.
  Future<void> _registrarFalha(AcsCredentialRecord record, DateTime at) {
    final lockedUntil = record.lockedUntil;
    final lockExpirou = lockedUntil != null && !lockedUntil.isAfter(at);
    return store.registerFailedAttempt(
      record.acsId,
      restartCounter: lockExpirou,
      maxFailedAttempts: maxFailedAttempts,
      lockUntil: at.add(lockDurationFor(record.lockStreak)),
      at: at,
    );
  }

  /// Distingue a audiência na trilha: revisar a atividade do backoffice não
  /// pode exigir juntar `userId` com `staff_accounts` à mão. Vale para todo
  /// evento deste serviço (login e ativação da MFA); o ACS continua `session`.
  String get _recursoDeAuditoria =>
      audience == CredentialAudience.staff ? 'staff_session' : 'session';

  /// Best-effort, como toda auditoria deste repositório: uma trilha fora do ar
  /// não pode impedir um ACS de entrar.
  Future<void> _recordAudit(String userId, String result) => audit.recordSafely(
    AuditEvent(
      userId: userId,
      actionType: 'login',
      resourceType: _recursoDeAuditoria,
      result: result,
    ),
  );
}
