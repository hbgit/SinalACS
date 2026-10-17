import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Duplo de teste que permite forçar falha em qualquer método, uma vez.
///
/// Existe para provar o comportamento de erro/retry das telas (achado da
/// revisão do PR: `FutureBuilder` sem `hasError` deixava erro parecer "vazio"
/// ou spinner infinito). Cada campo `failNext*` é consumido uma única vez, o
/// que permite testar "falha, depois usuário tenta de novo e funciona".
class FailingAdminDataSource implements AdminDataSource {
  FailingAdminDataSource({required this.inner});

  final AdminDataSource inner;

  // Avisos e termos (#46): repassados ao `inner`.
  @override
  Future<List<NoticeHistoryItem>> fetchNoticeHistory({String? microAreaId, int limit = 50, int offset = 0}) =>
      inner.fetchNoticeHistory(microAreaId: microAreaId, limit: limit, offset: offset);

  @override
  Future<String> scheduleNotice({
    required String microAreaId,
    required NoticeAudience audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
  }) => inner.scheduleNotice(
      microAreaId: microAreaId, audience: audience, title: title, message: message, scheduledFor: scheduledFor);

  @override
  Future<void> cancelScheduledNotice(String id) => inner.cancelScheduledNotice(id);

  @override
  Future<List<TermsVersionSummary>> fetchTermsVersions() => inner.fetchTermsVersions();

  @override
  Future<TermsVersionSummary> draftTermsVersion({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
  }) => inner.draftTermsVersion(version: version, summary: summary, effectiveFrom: effectiveFrom);

  @override
  Future<TermsVersionSummary> markTermsReviewed(String id) => inner.markTermsReviewed(id);

  @override
  Future<TermsVersionSummary> publishTermsVersion(String id) => inner.publishTermsVersion(id);

  // Escalonamento, pulso e fim de sessão (#44): repassados ao `inner`.
  @override
  Future<EscalationOutcome> escalateAlert(String alertId, EscalationReasonCode reason) =>
      inner.escalateAlert(alertId, reason);

  @override
  Future<AlertsPulse> alertsPulse() => inner.alertsPulse();

  @override
  Future<void> endMonitoringSession() => inner.endMonitoringSession();

  bool failNextIndicators = false;
  bool failNextMicroAreas = false;
  bool failNextAcs = false;
  bool failNextStaff = false;
  bool failNextAlerts = false;
  bool failNextAuditLogs = false;
  bool failNextRecordAccess = false;

  int recordAccessCalls = 0;

  /// Exceção específica lançada (uma vez) pela próxima leitura de dados, no
  /// lugar do `StateError` genérico: prova o tratamento de `AdminDataFailure` e
  /// `AdminSessionExpired` nas telas.
  Object? nextError;

  /// Falha depois do próximo frame (o pump avança o relógio antes de montar), como uma chamada de rede de
  /// verdade: um erro síncrono antes de o `FutureBuilder` assinar o `Future` é
  /// reportado como não tratado.
  Future<void> _lancaSeProgramado() async {
    final erro = nextError;
    if (erro == null) return;
    nextError = null;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    throw erro;
  }

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async {
    await _lancaSeProgramado();
    if (failNextIndicators) {
      failNextIndicators = false;
      throw StateError('falha simulada: indicadores');
    }
    return inner.fetchDashboardIndicators();
  }

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() async {
    await _lancaSeProgramado();
    if (failNextMicroAreas) {
      failNextMicroAreas = false;
      throw StateError('falha simulada: microáreas');
    }
    return inner.fetchMicroAreas();
  }

  @override
  Future<List<AcsSummary>> fetchAcs() async {
    await _lancaSeProgramado();
    if (failNextAcs) {
      failNextAcs = false;
      throw StateError('falha simulada: ACS');
    }
    return inner.fetchAcs();
  }

  @override
  Future<List<StaffSummary>> fetchStaff() async {
    await _lancaSeProgramado();
    if (failNextStaff) {
      failNextStaff = false;
      throw StateError('falha simulada: equipe do backoffice');
    }
    return inner.fetchStaff();
  }

  // As escritas da gestão de contas (#43) passam direto: as telas que este duplo
  // exercita medem falha de **leitura**.
  @override
  Future<NewAcsCredential> createAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) => inner.createAcs(name: name, enrollmentId: enrollmentId, microAreaId: microAreaId);

  @override
  Future<AcsSummary> setAcsMicroArea({required String acsId, required String microAreaId}) =>
      inner.setAcsMicroArea(acsId: acsId, microAreaId: microAreaId);

  @override
  Future<AcsSummary> setAcsActive({required String acsId, required bool active}) =>
      inner.setAcsActive(acsId: acsId, active: active);

  @override
  Future<String> resetAcsPassword({required String acsId}) => inner.resetAcsPassword(acsId: acsId);

  @override
  Future<List<AcsDevice>> fetchAcsDevices(String acsId) => inner.fetchAcsDevices(acsId);

  @override
  Future<DeviceWipeOrderResult> orderDeviceWipe({
    required String acsId,
    required String deviceId,
    required DeviceWipeReason reason,
  }) => inner.orderDeviceWipe(acsId: acsId, deviceId: deviceId, reason: reason);

  @override
  Future<void> resetAcsMfa({required String acsId}) => inner.resetAcsMfa(acsId: acsId);

  @override
  Future<NewStaffActivation> resetStaffMfa({required String staffId}) => inner.resetStaffMfa(staffId: staffId);

  @override
  Future<List<AlertSummary>> fetchAlerts({String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0}) async {
    await _lancaSeProgramado();
    if (failNextAlerts) {
      failNextAlerts = false;
      throw StateError('falha simulada: alertas');
    }
    return inner.fetchAlerts(microAreaId: microAreaId, status: status, limit: limit, offset: offset);
  }

  @override
  Future<AuditLogPage> fetchAuditLogs({
    AuditLogFilter filter = const AuditLogFilter(),
    int limit = 50,
    int? beforeSequence,
  }) async {
    await _lancaSeProgramado();
    if (failNextAuditLogs) {
      failNextAuditLogs = false;
      throw StateError('falha simulada: auditoria');
    }
    return inner.fetchAuditLogs(filter: filter, limit: limit, beforeSequence: beforeSequence);
  }

  /// Erro lançado (uma vez) pela próxima verificação da cadeia, depois do
  /// próximo frame — como [nextError], mas só para esta chamada.
  Object? failNextChainStatusWith;

  @override
  Future<ChainStatus> verifyAuditChain() async {
    await _lancaSeProgramado();
    final erro = failNextChainStatusWith;
    if (erro != null) {
      failNextChainStatusWith = null;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      throw erro;
    }
    return inner.verifyAuditChain();
  }

  @override
  Future<AuditExportResult> exportAuditLogs(AuditLogFilter filter) async {
    await _lancaSeProgramado();
    return inner.exportAuditLogs(filter);
  }

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {
    recordAccessCalls++;
    if (failNextRecordAccess) {
      failNextRecordAccess = false;
      throw StateError('falha simulada: recordAccess');
    }
    return inner.recordAccess(actionType: actionType, resourceType: resourceType);
  }

  @override
  Future<List<DataRequestSummary>> fetchDataRequests({DataRequestStatus? status, int limit = 50, int offset = 0}) async {
    await _lancaSeProgramado();
    return inner.fetchDataRequests(status: status, limit: limit, offset: offset);
  }

  @override
  Future<DataRequestDetail> fetchDataRequest(String id) async {
    await _lancaSeProgramado();
    return inner.fetchDataRequest(id);
  }

  @override
  Future<void> startDataRequestReview(String id) async {
    await _lancaSeProgramado();
    return inner.startDataRequestReview(id);
  }

  @override
  Future<void> completeDataRequest(String id, {String? note}) async {
    await _lancaSeProgramado();
    return inner.completeDataRequest(id, note: note);
  }

  @override
  Future<void> rejectDataRequest(String id, {required String reason}) async {
    await _lancaSeProgramado();
    return inner.rejectDataRequest(id, reason: reason);
  }
}
