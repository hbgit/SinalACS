import 'dart:async';

import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

/// Duplo de teste do backend do paciente.
///
/// Mantém os testes de widget herméticos: eles verificam o comportamento da
/// tela (o que é enviado, o que é exibido), não a rede. A conexão real é
/// verificada pelos testes de integração e por `tool/live_check.dart`.
class FakePatientBackend implements PatientBackend {
  FakePatientBackend({
    this.risk = RiskLevel.green,
    this.requestOtpFailure,
    this.verifyOtpFailure,
    this.developmentLoginFailure,
    this.alertFailure,
    this.enrollmentFailure,
  });

  /// Risco que o "servidor" devolve. A tela não pode derivá-lo por conta própria.
  RiskLevel risk;

  /// Recusas injetáveis, uma por caminho. Espelham o que o backend real lança.
  BackendFailure? requestOtpFailure;
  BackendFailure? verifyOtpFailure;
  BackendFailure? developmentLoginFailure;
  BackendFailure? alertFailure;
  BackendFailure? enrollmentFailure;
  AlertStatusResult statusResult = AlertStatusResult(found: false);
  BackendFailure? statusFailure;
  int statusForCallCount = 0;

  /// Estado "gravado no servidor", que [myChronicConditions] devolve e
  /// [updateChronicConditions] substitui — o mesmo papel que [statusResult]
  /// tem para `statusFor`.
  List<String> chronicConditions = const [];
  BackendFailure? myChronicConditionsFailure;
  BackendFailure? updateChronicConditionsFailure;
  int myChronicConditionsCallCount = 0;
  final List<List<String>> updateChronicConditionsCalls = <List<String>>[];

  /// Estado "gravado no servidor" para o painel "Meus Dados", devolvido por
  /// [myData].
  PatientDataOverview myDataResult = PatientDataOverview(
    name: 'Paciente de Teste',
    birthDate: DateTime.utc(1990, 1, 1),
    emergencyContact: 'Contato de teste',
    isChronic: false,
    chronicConditions: const [],
    consents: const [],
    riskHistory: const [],
    requests: const [],
  );
  BackendFailure? myDataFailure;
  int myDataCallCount = 0;

  /// Definido, segura [myData] até ser completado — backend lento ou pendurado.
  Completer<void>? myDataGate;

  /// Acrescenta ao histórico uma decisão sobre [purpose] (`granted` ou
  /// `revoked`), como o servidor faria ao gravar em `consent_logs`.
  void addConsentRecord(String purpose, String action, DateTime timestamp) {
    final record = PatientConsentRecord(
      purpose: purpose,
      action: action,
      version: legalDocumentsVersion,
      timestamp: timestamp,
    );
    myDataResult = myDataResult.copyWith(consents: [...myDataResult.consents, record]);
  }

  /// Atalho: o paciente já concedeu "Avisos da equipe".
  void grantPushConsent() => addConsentRecord('segmentedPush', 'granted', DateTime.utc(2026, 9, 1));

  /// Chamadas a [updateConsent], na ordem.
  final List<({ConsentPurpose purpose, bool granted})> updateConsentCalls =
      <({ConsentPurpose purpose, bool granted})>[];
  BackendFailure? updateConsentFailure;

  /// Chamadas a [registerPushToken], na ordem.
  final List<(String, String)> pushRegistrations = <(String, String)>[];
  BackendFailure? pushRegistrationFailure;

  @override
  Future<void> registerPushToken({required String token, required String platform}) async {
    pushRegistrations.add((token, platform));
    final failure = pushRegistrationFailure;
    if (failure != null) throw failure;
  }

  /// O aviso de mudança dos termos que o servidor devolveria, ou `null`.
  TermsChangeNotice? termsNotice;
  int termsNoticeCalls = 0;
  BackendFailure? termsNoticeFailure;

  /// Quando definido, [termsChangeNotice] só responde depois que ele completa —
  /// simula um backend lento ou pendurado.
  Completer<void>? termsNoticeGate;

  @override
  Future<TermsChangeNotice?> termsChangeNotice() async {
    termsNoticeCalls++;
    await termsNoticeGate?.future;
    final failure = termsNoticeFailure;
    if (failure != null) throw failure;
    return termsNotice;
  }

  /// O que o servidor responderia a [hasAcceptedCurrentTerms].
  bool termsAccepted = true;
  int termsStatusCalls = 0;
  BackendFailure? termsStatusFailure;

  /// Quando definido, [hasAcceptedCurrentTerms] só responde depois que ele
  /// completa — simula um backend lento ou pendurado.
  Completer<void>? termsStatusGate;

  @override
  Future<bool> hasAcceptedCurrentTerms() async {
    termsStatusCalls++;
    await termsStatusGate?.future;
    final failure = termsStatusFailure;
    if (failure != null) throw failure;
    return termsAccepted;
  }

  /// Chamadas a [acceptTermsOfUse].
  int acceptTermsCalls = 0;
  BackendFailure? acceptTermsFailure;

  /// Como no servidor: uma linha `termsOfUse` `granted` a mais no histórico.
  @override
  Future<PatientConsentRecord> acceptTermsOfUse() async {
    acceptTermsCalls++;
    final failure = acceptTermsFailure;
    if (failure != null) throw failure;
    final record = PatientConsentRecord(
      purpose: 'termsOfUse',
      action: 'granted',
      version: legalDocumentsVersion,
      timestamp: DateTime.now().toUtc(),
    );
    termsAccepted = true;
    myDataResult = myDataResult.copyWith(consents: [...myDataResult.consents, record]);
    return record;
  }

  int requestDataDeletionCount = 0;
  final List<String> correctionRequests = <String>[];
  BackendFailure? dataRequestFailure;

  /// Definido, segura [requestDataDeletion] até ser completado — é como o teste
  /// observa a tela com o pedido ainda em voo.
  Completer<void>? dataRequestGate;

  /// Código que o "servidor" aceita em [verifyOtp].
  ///
  /// O backend real nunca devolve o código ao app — ele sai por SMS, e o app
  /// só digita o que a pessoa recebeu. O fake precisa de um valor conhecido
  /// para o teste digitar.
  String validCode = '123456';

  /// Argumentos recebidos, para as asserções.
  final List<Map<String, bool>> triageCalls = <Map<String, bool>>[];
  final List<String> idempotencyKeys = <String>[];
  final List<String> locationHashes = <String>[];
  final List<String?> locationCells = <String?>[];
  final List<Map<String, Object>> enrollmentCalls = <Map<String, Object>>[];

  /// Pedidos de código recebidos, na ordem em que chegaram.
  final List<({String cpf, DateTime birthDate})> otpRequests =
      <({String cpf, DateTime birthDate})>[];

  /// Verificações de código recebidas, na ordem em que chegaram.
  final List<({String cpf, String code})> otpVerifications =
      <({String cpf, String code})>[];

  /// Último pedido de código. `null` enquanto nenhum chegou — é o que prova
  /// que a tela **não** chamou o backend.
  ({String cpf, DateTime birthDate})? get lastOtpRequest =>
      otpRequests.isEmpty ? null : otpRequests.last;

  int developmentLoginCount = 0;
  bool closed = false;

  AuthSession? _session;

  @override
  AuthSession? get session => _session;

  @override
  bool get isAuthenticated => _session != null;

  @override
  Future<ServiceHealth> health() async => ServiceHealth(
        status: 'ok',
        mqttConnected: true,
        dbConnected: true,
      );

  /// Só registra o pedido: o backend real responde igual para CPF que existe e
  /// para CPF que não existe, e é isso que o fake reproduz — nenhuma sessão,
  /// nenhum código devolvido, nenhum erro.
  @override
  Future<void> requestOtp({
    required String cpf,
    required DateTime birthDate,
  }) async {
    otpRequests.add((cpf: cpf, birthDate: birthDate));
    final failure = requestOtpFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<AuthSession> verifyOtp({
    required String cpf,
    required String code,
  }) async {
    otpVerifications.add((cpf: cpf, code: code));
    final failure = verifyOtpFailure;
    if (failure != null) throw failure;
    if (code != validCode) {
      throw const BackendFailure(
        'Código inválido ou expirado. Peça um novo.',
        isRecoverable: false,
      );
    }

    _session = _patientSession(
      userId: '00000000-0000-4000-8000-000000000001',
      accessToken: 'token-de-otp',
      // 1 hora: o TTL do paciente (LGPD-RT06), como no servidor.
      lifetime: const Duration(hours: 1),
    );
    return _session!;
  }

  @override
  Future<AuthSession> developmentLogin({required String role}) async {
    developmentLoginCount++;
    final failure = developmentLoginFailure;
    if (failure != null) throw failure;

    _session = _patientSession(
      userId: '00000000-0000-4000-8000-000000000001',
      accessToken: 'token-de-teste',
      // 15 minutos: é o padrão de `issueToken`, que `developmentLogin` usa.
      lifetime: const Duration(minutes: 15),
    );
    return _session!;
  }

  AuthSession _patientSession({
    required String userId,
    required String accessToken,
    required Duration lifetime,
  }) =>
      AuthSession(
        accessToken: accessToken,
        tokenType: 'Bearer',
        userId: userId,
        role: 'patient',
        microAreaId: '00000000-0000-4000-8000-000000000003',
        expiresAt: DateTime.now().toUtc().add(lifetime),
      );

  /// Substitui a sessão corrente por uma já expirada.
  ///
  /// Existe para exercitar o caminho "a sessão acabou com o app aberto" sem
  /// esperar a hora real — e porque o app do paciente **não** renova sozinho:
  /// é justamente esse o comportamento que precisa de teste.
  void expireSession() {
    final current = _session;
    if (current == null) return;
    _session = AuthSession(
      accessToken: current.accessToken,
      tokenType: current.tokenType,
      userId: current.userId,
      role: current.role,
      microAreaId: current.microAreaId,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
  }

  @override
  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    triageCalls.add(<String, bool>{
      'chestPain': chestPain,
      'difficultyBreathing': difficultyBreathing,
      'fever': fever,
      'persistentVomiting': persistentVomiting,
      'bleeding': bleeding,
      'severeWeakness': severeWeakness,
    });
    return risk;
  }

  @override
  Future<AlertStatusResult> statusFor() async {
    statusForCallCount++;
    final failure = statusFailure;
    if (failure != null) throw failure;
    return statusResult;
  }

  @override
  Future<RedAlertResult> createRedAlert({
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    locationHashes.add(locationHash);
    locationCells.add(locationCell);
    final failure = alertFailure;
    if (failure != null) throw failure;

    return RedAlertResult(
      alertId: 'alerta-de-teste',
      status: AlertStatus.pending,
      published: true,
    );
  }

  @override
  Future<AuthSession> completeEnrollment({
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
    required bool termsAccepted,
  }) async {
    enrollmentCalls.add(<String, Object>{
      'token': token,
      'healthDataConsent': healthDataConsent,
      'remindersConsent': remindersConsent,
      'pushConsent': pushConsent,
      'termsAccepted': termsAccepted,
    });
    final failure = enrollmentFailure;
    if (failure != null) throw failure;

    final session = AuthSession(
      accessToken: 'token-de-onboarding',
      tokenType: 'Bearer',
      userId: '00000000-0000-4000-8000-000000000002',
      role: 'patient',
      microAreaId: '00000000-0000-4000-8000-000000000003',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
    _session = session;
    return session;
  }

  @override
  Future<List<String>> myChronicConditions() async {
    myChronicConditionsCallCount++;
    final failure = myChronicConditionsFailure;
    if (failure != null) throw failure;
    return chronicConditions;
  }

  @override
  Future<void> updateChronicConditions(List<String> conditions) async {
    final failure = updateChronicConditionsFailure;
    if (failure != null) throw failure;
    updateChronicConditionsCalls.add(conditions);
    chronicConditions = conditions;
  }

  @override
  Future<PatientDataOverview> myData() async {
    myDataCallCount++;
    await myDataGate?.future;
    final failure = myDataFailure;
    if (failure != null) throw failure;
    return myDataResult;
  }

  /// Como no servidor: uma linha nova no histórico, que o próximo [myData]
  /// devolve.
  @override
  Future<PatientConsentRecord> updateConsent({
    required ConsentPurpose purpose,
    required bool granted,
  }) async {
    updateConsentCalls.add((purpose: purpose, granted: granted));
    final failure = updateConsentFailure;
    if (failure != null) throw failure;
    final record = PatientConsentRecord(
      purpose: purpose.name,
      action: granted ? 'granted' : 'denied',
      version: legalDocumentsVersion,
      timestamp: DateTime.now().toUtc(),
    );
    myDataResult = myDataResult.copyWith(consents: [...myDataResult.consents, record]);
    return record;
  }

  /// Idempotente enquanto houver exclusão aberta, como o servidor.
  @override
  Future<PatientDataSubjectRequestRecord> requestDataDeletion() async {
    requestDataDeletionCount++;
    await dataRequestGate?.future;
    final failure = dataRequestFailure;
    if (failure != null) throw failure;
    for (final request in myDataResult.requests) {
      if (request.type == DataSubjectRequestType.deletion &&
          request.status == DataSubjectRequestStatus.open) {
        return request;
      }
    }
    return _appendRequest(DataSubjectRequestType.deletion, null);
  }

  @override
  Future<PatientDataSubjectRequestRecord> requestDataCorrection(String details) async {
    correctionRequests.add(details);
    final failure = dataRequestFailure;
    if (failure != null) throw failure;
    return _appendRequest(DataSubjectRequestType.correction, details);
  }

  PatientDataSubjectRequestRecord _appendRequest(DataSubjectRequestType type, String? details) {
    final now = DateTime.now().toUtc();
    final record = PatientDataSubjectRequestRecord(
      type: type,
      status: DataSubjectRequestStatus.open,
      details: details,
      createdAt: now,
      dueAt: now.add(const Duration(days: 15)),
    );
    myDataResult = myDataResult.copyWith(requests: [...myDataResult.requests, record]);
    return record;
  }

  @override
  void close() => closed = true;
}
