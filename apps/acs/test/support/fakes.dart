import 'dart:async';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// UUIDs do seed de desenvolvimento. Dados sintéticos.
const seedAcsId = '00000000-0000-4000-8000-000000000002';
const seedPatientId = '00000000-0000-4000-8000-000000000001';
const seedMicroAreaId = '00000000-0000-4000-8000-000000000003';
const otherMicroAreaId = '00000000-0000-4000-8000-000000000099';

/// UUIDs sintéticos distintos, para os testes que precisam de mais de um
/// paciente. Nome próprio não entra em teste de repositório de saúde.
String syntheticPatientId(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// Célula de teste com centro determinístico (ver
/// `apps/acs/test/location_cell_test.dart`), para exercitar o caminho do
/// mapa com posição sem depender de GPS real de paciente algum.
const testLocationCell = '-1580:-4783';

class FakeAcsBackend implements AcsBackend {
  FakeAcsBackend({this.loginFailure, this.acknowledged = true, this.microAreaId = seedMicroAreaId});

  BackendFailure? loginFailure;
  bool acknowledged;
  String? microAreaId;

  /// Pacientes que `listPatients()` devolve. Vazio por padrão: um teste que
  /// não configurar isto exercita o caminho "sem paciente na microárea".
  List<MicroAreaPatient> patients = const [];

  /// Falha da chamada, como uma queda de rede ao carregar a lista.
  BackendFailure? listPatientsFailure;

  int listPatientsCount = 0;

  final List<String> acknowledgedAlertIds = <String>[];
  int loginCount = 0;

  AuthSession? _session;

  @override
  AuthSession? get session => _session;

  /// Troca a sessão corrente sem passar pelo login (ex.: outro ACS entrou
  /// enquanto o lote de um anterior estava em voo).
  set session(AuthSession? value) => _session = value;

  @override
  bool get isAuthenticated => _session != null;


  /// Credencial que [login] recebeu. `null` enquanto a tela não chamar o
  /// backend — é o que prova tanto "enviou o que foi digitado" quanto "campo em
  /// branco não chamou nada".
  ({String matricula, String senha})? lastCredentials;

  @override
  void Function()? onSessionExpired;

  /// Refresh token "no Keystore". O login por senha grava um novo; a recusa
  /// e o logout apagam; a falta de rede mantém — como o `BackendClient`.
  String? storedRefreshToken;
  int _refreshSeq = 0;

  /// Retomada sem rede: devolve `null` e MANTÉM o token.
  bool resumeOffline = false;

  /// Servidor recusa o refresh token: devolve `null` e APAGA o token.
  bool rejectResume = false;

  int resumeCount = 0;
  int logoutCount = 0;

  /// Ordem das chamadas que importam ao "Sair" e ao "Limpar este aparelho":
  /// `syncVisits`, `syncLegacy`, `syncDeferred`, `revokeUploadToken`, `logout`.
  final List<String> callLog = <String>[];

  @override
  Future<bool> get hasStoredSession async => storedRefreshToken != null;

  @override
  Future<AuthSession?> resumeSession() async {
    resumeCount++;
    if (storedRefreshToken == null || resumeOffline) return null;
    if (rejectResume) {
      storedRefreshToken = null;
      return null;
    }
    storedRefreshToken = 'refresh-${++_refreshSeq}';
    return _issueSession();
  }

  /// Se definido, `logout()` espera por ele (rede lenta).
  Completer<void>? logoutGate;

  @override
  Future<void> logout() async {
    logoutCount++;
    callLog.add('logout');
    await logoutGate?.future;
    storedRefreshToken = null;
    _session = null;
  }

  /// Simula o servidor com MFA ativa: sem [totpCode] igual a [expectedTotpCode], levanta [MfaCodeRequired].
  String? expectedTotpCode;
  bool mfaEnrollmentRequired = false;
  String? lastTotpCode;
  TotpEnrollmentStart enrollmentStart =
      TotpEnrollmentStart(secretBase32: 'GEZDGNBVGY3TQOJQ', otpauthUri: 'otpauth://totp/SinalACS:ACS-001?secret=GEZDGNBVGY3TQOJQ');
  String? confirmedCode;

  @override
  Future<void> confirmTotpEnrollment({required String matricula, required String senha, required String code}) async {
    confirmedCode = code;
  }

  @override
  Future<TotpEnrollmentStart> beginTotpEnrollment({required String matricula, required String senha}) async {
    if (enrollmentFailuresLeft > 0) {
      enrollmentFailuresLeft--;
      throw const BackendFailure('Sem conexão com o servidor.');
    }
    return enrollmentStart;
  }

  /// Quantas chamadas a [beginTotpEnrollment] ainda falham antes de funcionar.
  int enrollmentFailuresLeft = 0;

  @override
  Future<AuthSession> login({
    required String matricula,
    required String senha,
    String? totpCode,
  }) async {
    loginCount++;
    lastCredentials = (matricula: matricula, senha: senha);
    lastTotpCode = totpCode;
    if (sessionExpired && expectedTotpCode != null && totpCode == null) throw const MfaCodeRequired();
    if (mfaEnrollmentRequired) throw const MfaEnrollmentRequired();
    if (expectedTotpCode != null && totpCode != expectedTotpCode) {
      throw totpCode == null ? const MfaCodeRequired() : const BackendFailure('Código de verificação inválido.', isRecoverable: false);
    }
    sessionExpired = false;
    final session = await _issueSession();
    storedRefreshToken = 'refresh-${++_refreshSeq}';
    return session;
  }

  /// Ferramenta de desenvolvimento (`tool/`, `integration_test/`). Sem
  /// credencial, não há o que registrar: quem exercita o caminho do produto
  /// (RF07) é [login].
  @override
  Future<AuthSession> developmentLogin({required String role}) =>
      _issueSession();

  Future<AuthSession> _issueSession() async {
    final failure = loginFailure;
    if (failure != null) throw failure;

    final session = AuthSession(
      accessToken: 'token-de-teste',
      tokenType: 'Bearer',
      userId: nextUserId,
      role: 'acs',
      microAreaId: microAreaId,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
    _session = session;
    return session;
  }

  /// Sessão vencida com MFA: toda chamada autenticada falha como o
  /// `BackendClient` real (não recuperável) e avisa a UI uma única vez.
  bool sessionExpired = false;

  /// `userId` da próxima sessão emitida (padrão: o ACS do seed).
  String nextUserId = seedAcsId;

  /// Vence a sessão agora, como a renovação que recebeu `MfaRequiredException`.
  void expireSession() {
    sessionExpired = true;
    _session = null;
    onSessionExpired?.call();
  }

  @override
  Future<AlertAckResult> acknowledge({required String alertId}) async {
    if (sessionExpired) {
      onSessionExpired?.call();
      throw const BackendFailure(
        'Sua sessão expirou. Entre novamente com o código do autenticador.',
        isRecoverable: false,
      );
    }
    acknowledgedAlertIds.add(alertId);
    return AlertAckResult(
      alertId: alertId,
      acknowledged: acknowledged,
      status: acknowledged ? AlertStatus.acknowledged : null,
    );
  }

  final List<List<VisitSyncEntry>> syncedVisitBatches = <List<VisitSyncEntry>>[];

  /// Falha da chamada inteira, como uma queda de rede.
  BackendFailure? syncFailure;

  /// Resultado por visita; ausente significa `synced`.
  VisitSyncResult Function(VisitSyncEntry entry)? syncResultFor;

  @override
  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits, {String? expectedUserId}) async {
    // Como o BackendClient: a conferência do dono vem antes de qualquer envio.
    if (expectedUserId != null && _session?.userId != expectedUserId) throw sessionOwnerMismatch;
    callLog.add('syncVisits');
    syncedVisitBatches.add(List.of(visits));
    final failure = syncFailure;
    if (failure != null) throw failure;

    final custom = syncResultFor;
    if (custom != null) return [for (final visit in visits) custom(visit)];

    return [
      for (final visit in visits)
        VisitSyncResult(
          localId: visit.localId,
          syncStatus: SyncStatus.synced,
          serverVersion: visit.version + 1,
        ),
    ];
  }

  /// Lotes de `syncLegacyVisits`, com o `userId` da sessão que transportou.
  final List<({String? transportUserId, String deviceId, List<VisitSyncEntry> visits})> legacyBatches = [];

  /// Falha da chamada legada inteira, como uma queda de rede.
  BackendFailure? legacyFailure;

  /// Resultado por visita legada; ausente significa `synced`.
  VisitSyncResult Function(VisitSyncEntry entry)? legacyResultFor;

  @override
  Future<List<VisitSyncResult>> syncLegacyVisits(List<VisitSyncEntry> visits, {required String deviceId}) async {
    // Como o BackendClient: sem sessão não há transporte.
    final transport = _session;
    if (transport == null) throw const BackendFailure('Sessão não iniciada.', isRecoverable: false);
    if (visits.length > 200) throw const BackendFailure('lote acima do limite', isRecoverable: false);
    callLog.add('syncLegacy');
    legacyBatches.add((transportUserId: transport.userId, deviceId: deviceId, visits: List.of(visits)));
    final failure = legacyFailure;
    if (failure != null) throw failure;
    return [for (final visit in visits) legacyResultFor?.call(visit) ?? _synced(visit)];
  }

  /// Lotes de `syncDeferredVisits`, com o token de envio usado em cada um.
  final List<({String uploadToken, String deviceId, List<VisitSyncEntry> visits})> deferredBatches = [];

  /// Falha da chamada diferida inteira, como uma queda de rede.
  BackendFailure? deferredFailure;

  /// Tokens de envio que o "servidor" recusa (vencidos/revogados).
  final Set<String> refusedUploadTokens = <String>{};

  /// Resultado por visita diferida; ausente significa `synced`.
  VisitSyncResult Function(VisitSyncEntry entry)? deferredResultFor;

  /// Se definido, `syncDeferredVisits` espera por ele (lote em voo).
  Completer<void>? deferredGate;

  @override
  Future<List<VisitSyncResult>> syncDeferredVisits({
    required String uploadToken,
    required String deviceId,
    required List<VisitSyncEntry> visits,
  }) async {
    if (visits.length > 200) throw const BackendFailure('lote acima do limite', isRecoverable: false);
    callLog.add('syncDeferred');
    deferredBatches.add((uploadToken: uploadToken, deviceId: deviceId, visits: List.of(visits)));
    // A recusa é decidida quando o servidor responde (depois da espera): o
    // token pode ter sido revogado enquanto o lote estava em voo.
    await deferredGate?.future;
    if (refusedUploadTokens.contains(uploadToken)) throw const UploadTokenRefused();
    final failure = deferredFailure;
    if (failure != null) throw failure;
    return [for (final visit in visits) deferredResultFor?.call(visit) ?? _synced(visit)];
  }

  /// Tokens de envio revogados, na ordem.
  final List<String> revokedUploadTokens = <String>[];

  /// Se definido, `revokeUploadToken` espera por ele (revogação em voo).
  Completer<void>? revokeGate;

  @override
  Future<void> revokeUploadToken(String uploadToken) async {
    callLog.add('revokeUploadToken');
    revokedUploadTokens.add(uploadToken);
    await revokeGate?.future;
  }

  /// Reenvio do mesmo `localId` na mesma versão volta `synced` (idempotente).
  static VisitSyncResult _synced(VisitSyncEntry visit) =>
      VisitSyncResult(localId: visit.localId, syncStatus: SyncStatus.synced, serverVersion: visit.version);

  /// Contato que `ubsContact()` devolve; `UbsContact(name: ...)` sem telefone simula uma UBS sem número.
  UbsContact ubsContactResult = UbsContact(name: 'UBS Teste', phone: '+55 11 5550-0100');

  /// Falha da chamada, como uma queda de rede.
  BackendFailure? ubsContactFailure;

  int ubsContactCount = 0;

  /// Se definido, `ubsContact()` espera por ele (simula rede lenta).
  Completer<void>? ubsContactGate;

  @override
  Future<UbsContact> ubsContact() async {
    ubsContactCount++;
    await ubsContactGate?.future;
    final falha = ubsContactFailure;
    if (falha != null) throw falha;
    return ubsContactResult;
  }

  /// Falha não classificada (não é `BackendFailure`), para exercitar o ramo
  /// `catch (error, ...)` genérico de `_loadMicroAreaPatients` em `app.dart` —
  /// algo que nenhum `BackendFailure` simula. Checada antes de
  /// [listPatientsFailure].
  Object? listPatientsUnclassifiedFailure;

  @override
  Future<List<MicroAreaPatient>> listPatients() async {
    listPatientsCount++;
    final unclassified = listPatientsUnclassifiedFailure;
    if (unclassified != null) throw unclassified;
    final failure = listPatientsFailure;
    if (failure != null) throw failure;
    return patients;
  }

  /// patientIds pedidos em `generateInvite`, na ordem.
  final List<String> inviteCalls = <String>[];

  /// Falha da geração do convite, como paciente fora da microárea.
  BackendFailure? inviteFailure;

  /// Quando definido, `generateInvite` só responde depois que ele completa —
  /// simula a rede lenta de campo.
  Completer<void>? inviteGate;

  /// Validade do convite devolvido por `generateInvite`, contada de agora.
  Duration inviteLifetime = const Duration(minutes: 15);

  @override
  Future<EnrollmentTokenResult> generateInvite({required String patientId}) async {
    inviteCalls.add(patientId);
    await inviteGate?.future;
    final failure = inviteFailure;
    if (failure != null) throw failure;
    return EnrollmentTokenResult(
      token: 'convite-sintetico-${inviteCalls.length}',
      expiresAt: DateTime.now().toUtc().add(inviteLifetime),
    );
  }

  /// Avisos pedidos em `sendNotice`, na ordem: (título, mensagem, só crônicos).
  final List<(String, String, bool)> notices = <(String, String, bool)>[];

  /// Falha do envio, como o relé de push fora do ar.
  BackendFailure? noticeFailure;

  /// Quando definido, `sendNotice` só responde depois que ele completa —
  /// simula a rede lenta de campo.
  Completer<void>? noticeGate;

  /// Resultado devolvido por `sendNotice`.
  NoticeSendResult noticeResult = NoticeSendResult(recipients: 3, accepted: 2);

  @override
  Future<NoticeSendResult> sendNotice({
    required String title,
    required String message,
    required bool chronicOnly,
  }) async {
    notices.add((title, message, chronicOnly));
    await noticeGate?.future;
    final failure = noticeFailure;
    if (failure != null) throw failure;
    return noticeResult;
  }

  /// Entradas que `pullVisits` devolve. Vazio por padrão.
  List<VisitSyncEntry> pullEntries = const [];

  /// Falha da chamada, como uma queda de rede ou sessão expirada.
  BackendFailure? pullFailure;

  /// Falha não classificada (não é `BackendFailure`), para exercitar o ramo
  /// `catch (error, ...)` genérico de `_pullVisits` em `app.dart` — algo que
  /// nenhum `BackendFailure` simula. Checada antes de [pullFailure].
  Object? pullUnclassifiedFailure;

  /// `since` recebido em cada chamada, na ordem em que ocorreram — prova que
  /// o cursor lido é exatamente o que chega ao backend.
  final List<DateTime> pullSinceCalls = <DateTime>[];

  @override
  Future<List<VisitSyncEntry>> pullVisits({required DateTime since}) async {
    pullSinceCalls.add(since);
    final unclassified = pullUnclassifiedFailure;
    if (unclassified != null) throw unclassified;
    final failure = pullFailure;
    if (failure != null) throw failure;
    return pullEntries;
  }

  @override
  void close() {}
}

/// Feed de alertas controlado pelo teste.
///
/// Expõe a [AlertQueue] para que o teste empurre alertas como se tivessem
/// chegado pelo broker, sem precisar de rede nem de emulador.
class FakeAlertFeed implements AlertFeed {
  FakeAlertFeed(this.queue, {this.failOnStart = false, this.failure, this.failuresBeforeSuccess = 0});

  final AlertQueue queue;
  final bool failOnStart;

  /// Falha já classificada, para exercitar cada banner do painel.
  ///
  /// `failOnStart` continua lançando um erro genérico de propósito: é o ramo de
  /// defesa do shell, o que nenhum `AlertFeedFailure` cobre.
  final AlertFeedFailure? failure;

  /// Quantas chamadas a [start] devem falhar antes de uma que conecta.
  ///
  /// É o que prova que a retentativa do shell não só acontece, mas **dá
  /// certo**: sem isto, todo teste de reconexão ficaria preso numa falha para
  /// sempre.
  final int failuresBeforeSuccess;

  bool started = false;
  bool stopped = false;
  String? startedTopicMicroArea;

  /// Quantas vezes [start] foi chamado — inclusive as que falharam.
  int startCount = 0;

  @override
  bool get isConnected => started;

  @override
  void Function(bool connected)? onConnectionChanged;

  @override
  Future<void> start({required String microAreaId, required String acsId}) async {
    startCount++;
    if (startCount <= failuresBeforeSuccess) {
      throw failure ?? const AlertFeedFailure(
        AlertFeedFailureKind.unreachable,
        title: 'Sem conexão com a central de alertas.',
        detail: 'Novos alertas podem não estar chegando.',
        transient: true,
      );
    }
    final classified = failure;
    if (classified != null) throw classified;
    if (failOnStart) throw StateError('broker indisponível');
    started = true;
    startedTopicMicroArea = microAreaId;
    onConnectionChanged?.call(true);
  }

  @override
  void stop() {
    started = false;
    stopped = true;
  }

  /// Simula a chegada de um alerta pelo tópico assinado.
  void deliver(PrioritizedAlert alert) => queue.upsert(alert);
}

/// Armazenamento que recusa gravar, para acender `persistenceFailed`.
///
/// Separar `load` de `save` importa: um banco que abre e depois falha ao gravar
/// é o caso em que o sinalizador precisa acender **depois** do `initState` —
/// exatamente o que um campo congelado ali não enxergava.
class FailingVisitStore implements VisitStore {
  FailingVisitStore({this.failOnLoad = true, this.failOnSave = true});

  final bool failOnLoad;
  final bool failOnSave;

  List<OfflineVisitRecord> _visits = <OfflineVisitRecord>[];

  @override
  Future<List<OfflineVisitRecord>> load() async {
    if (failOnLoad) throw StateError('sem banco');
    return List.of(_visits);
  }

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    if (failOnSave) throw StateError('sem banco');
    _visits = List.of(visits);
  }
}

/// Sincronizador que devolve o resultado programado pelo teste.
class FakeVisitSynchronizer implements VisitSynchronizer {
  FakeVisitSynchronizer({this.statusFor, this.messageFor, this.throwOnPush = false});

  /// Status por localId; ausente significa `synced`.
  String Function(OfflineVisitRecord visit)? statusFor;

  /// Motivo devolvido pelo servidor, como em `VisitSyncResult.message`.
  String? Function(OfflineVisitRecord visit)? messageFor;
  bool throwOnPush;

  final List<List<OfflineVisitRecord>> batches = <List<OfflineVisitRecord>>[];

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    batches.add(List.of(visits));
    if (throwOnPush) throw StateError('sem rede');

    return [
      for (final visit in visits)
        VisitSyncOutcome(
          localId: visit.localId,
          status: statusFor?.call(visit) ?? 'synced',
          serverVersion: visit.version + 1,
          message: messageFor?.call(visit),
        ),
    ];
  }
}

PrioritizedAlert testAlert({
  required String alertId,
  String riskLevel = 'red',
  String microAreaId = seedMicroAreaId,
  DateTime? triggeredAt,
  // Ausente por padrão: um teste que não passar isto exercita o caminho
  // "sem GPS no paciente", que é o estado mais comum e não deve fabricar
  // marcador nenhum no mapa.
  String? locationCell,
}) {
  return PrioritizedAlert(
    alertId: alertId,
    patientId: seedPatientId,
    microAreaId: microAreaId,
    riskLevel: riskLevel,
    locationHash: 'sem-local-00',
    locationCell: locationCell,
    triggeredAt: triggeredAt ?? DateTime.utc(2026, 9, 11, 12),
  );
}

/// Desbloqueio local controlado pelo teste.
class FakeBiometricGate implements BiometricGate {
  FakeBiometricGate({this.available = true, this.result = UnlockResult.unlocked});

  bool available;
  UnlockResult result;
  int calls = 0;
  final List<String> reasons = <String>[];

  /// Se definido, `authenticate` só responde quando ele completar.
  Completer<UnlockResult>? pending;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<UnlockResult> authenticate({required String reason}) async {
    calls++;
    reasons.add(reason);
    final wait = pending;
    if (wait != null) return wait.future;
    return result;
  }
}
