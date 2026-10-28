import 'dart:async';

import 'admin_data_source.dart';

/// Implementação mock de [AdminDataSource]. Todos os dados são fictícios
/// (nenhum dado real de paciente/UBS/ACS), no espírito do `AlertStore`/
/// `AlertPublisher` fake usados nos testes do backend.
class MockAdminDataSource implements AdminDataSource {
  /// [auditSeed] semeia a trilha (#45) com linhas sintéticas e selos
  /// escolhidos pelo teste; [chainStatus] fixa o estado da cadeia. O mock só
  /// devolve o que foi semeado: nunca calcula integridade.
  /// [alertSeed] substitui os alertas do mock (por padrão, [_seedAlerts]):
  /// para um teste montar um estado que o seed não tem, como um vermelho
  /// `escalated` legado ou um vermelho concluído.
  MockAdminDataSource({
    DateTime Function()? now,
    List<AuditLogEntry>? auditSeed,
    List<AlertSummary>? alertSeed,
    this.chainStatus,
  })  : _microAreas = List.unmodifiable(_seedMicroAreas),
        _alerts = List.unmodifiable(alertSeed ?? _seedAlerts),
        _acs = [..._seedAcs],
        _staff = [..._seedStaff],
        _now = now ?? DateTime.now {
    _pedidos.addAll(_seedPedidos(_now()));
    if (auditSeed != null) {
      _auditLog.addAll([...auditSeed]..sort((a, b) => a.sequence.compareTo(b.sequence)));
      for (final e in auditSeed) {
        if (e.sequence > _auditSeq) _auditSeq = e.sequence;
      }
    }
  }

  /// Estado devolvido por [verifyAuditChain]; `null` = cadeia íntegra.
  ChainStatus? chainStatus;

  /// Quando não nulo, [verifyAuditChain] lança este erro.
  Object? chainStatusError;

  /// Chamadas a [verifyAuditChain] e consultas à trilha, para os testes.
  int verifyChainCalls = 0;
  final List<AuditQuery> auditQueries = [];

  /// Exportação (#45, Task 11). [exportResult] fixa o resultado (sem ele, o
  /// mock monta um a partir do recorte semeado); [exportError], quando não
  /// nulo, é lançado; [exportGate] segura a resposta até o teste completá-lo.
  /// [exportCalls] conta toda chamada, inclusive as que falham.
  AuditExportResult? exportResult;
  Object? exportError;
  Completer<void>? exportGate;
  int exportCalls = 0;
  AuditLogFilter? lastExportFilter;

  final DateTime Function() _now;

  /// Pedidos do titular (#42), mutáveis para as decisões do mock. Textos
  /// fictícios; nenhum dado real de paciente.
  final List<DataRequestDetail> _pedidos = [];

  final List<MicroAreaSummary> _microAreas;
  final List<AlertSummary> _alerts;
  final List<AcsSummary> _acs;
  final List<StaffSummary> _staff;
  final List<AuditLogEntry> _auditLog = [];

  /// Escalonamentos (#44): id -> instante. O alerta segue pendente e listado.
  final Map<String, DateTime> _escalados = {};

  /// Mesmo prazo do servidor (`redAlertEscalationSeconds`).
  static const _prazoDoVermelho = Duration(seconds: 300);

  /// Chamadas a `endMonitoringSession`, para os testes.
  int monitoringSessionEnds = 0;
  int _auditSeq = 0;
  int _acsSeq = _seedAcs.length;

  /// Chamadas de escrita registradas para os testes de tela (Tarefa 10): o que
  /// se prova não é só o estado final, e sim que a chamada aconteceu — e que
  /// **não** aconteceu quando a ação foi cancelada.
  final List<String> desativados = [];
  final List<String> vinculados = [];
  final List<String> senhasRedefinidas = [];
  final List<String> mfasRedefinidas = [];

  /// Pedidos de limpeza remota recebidos (#81): `acsId/deviceId` e o motivo.
  final List<({String acsId, String deviceId, DeviceWipeReason reason})> limpezasPedidas = [];

  /// Aparelhos sintéticos por ACS. `acs-1` tem um sem pedido e um já limpo.
  final Map<String, List<AcsDevice>> _aparelhos = {
    'acs-1': [
      AcsDevice(deviceId: 'dev-aaaa1111', label: 'Aparelho dev-aaaa', lastSeenAt: DateTime.utc(2026, 10, 16, 14, 5)),
      AcsDevice(
        deviceId: 'dev-bbbb2222',
        label: 'Aparelho dev-bbbb',
        lastSeenAt: DateTime.utc(2026, 10, 10, 9, 30),
        wipeState: DeviceWipeState.confirmed,
        wipeRequestedAt: DateTime.utc(2026, 10, 10, 10, 0),
        wipeConfirmedAt: DateTime.utc(2026, 10, 10, 10, 20),
      ),
    ],
  };

  /// Credenciais determinísticas: o teste de tela procura por este texto.
  static const _senhaDeTeste = 'SENHA-INICIAL-DE-TESTE';
  static const _codigoDeAtivacao = 'ABCD-EFGH-JKLM-NPQR-STUV';

  /// Validade fixa do código de ativação: o mock não tem relógio, e uma data
  /// que muda a cada execução tornaria o teste instável.
  static final _codigoExpiraEm = DateTime(2026, 10, 9, 12);

  /// UBS sintética das linhas criadas pelo mock (nenhuma UBS real).
  static const _ubsSintetica = 'UBS Vila Nova';

  static final _seedMicroAreas = [
    const MicroAreaSummary(
      id: 'ma-12',
      name: 'Microárea 12 — Zona Rural',
      acsName: 'Carla Nogueira',
      acsEnrollmentId: 'ACS-001',
      acsActive: true,
    ),
    const MicroAreaSummary(
      id: 'ma-07',
      name: 'Microárea 07 — Centro',
      acsName: 'Bruno Faria',
      acsEnrollmentId: 'ACS-014',
      acsActive: true,
    ),
    const MicroAreaSummary(
      id: 'ma-03',
      name: 'Microárea 03 — Vila Esperança',
      acsName: 'Sem ACS vinculado',
      acsEnrollmentId: '—',
      acsActive: false,
    ),
  ];

  static final _seedAlerts = [
    AlertSummary(
      id: 'alert-1',
      patientLabel: 'Paciente #A18F',
      microAreaName: 'Microárea 12 — Zona Rural',
      riskLevel: RiskLevel.red,
      status: AlertStatus.pending,
      triggeredAt: DateTime(2026, 9, 11, 8, 12),
    ),
    AlertSummary(
      id: 'alert-2',
      patientLabel: 'Paciente #7C2E',
      microAreaName: 'Microárea 12 — Zona Rural',
      riskLevel: RiskLevel.red,
      status: AlertStatus.acknowledged,
      triggeredAt: DateTime(2026, 9, 11, 7, 40),
    ),
    AlertSummary(
      id: 'alert-3',
      patientLabel: 'Paciente #4D91',
      microAreaName: 'Microárea 07 — Centro',
      riskLevel: RiskLevel.yellow,
      status: AlertStatus.acknowledged,
      triggeredAt: DateTime(2026, 9, 11, 6, 55),
    ),
    AlertSummary(
      id: 'alert-4',
      patientLabel: 'Paciente #B6A0',
      microAreaName: 'Microárea 07 — Centro',
      riskLevel: RiskLevel.green,
      status: AlertStatus.resolved,
      triggeredAt: DateTime(2026, 9, 10, 19, 5),
      resolvedAt: DateTime(2026, 9, 10, 19, 40),
    ),
    AlertSummary(
      id: 'alert-5',
      patientLabel: 'Paciente #E33C',
      microAreaName: 'Microárea 03 — Vila Esperança',
      riskLevel: RiskLevel.yellow,
      status: AlertStatus.escalated,
      triggeredAt: DateTime(2026, 9, 10, 15, 22),
    ),
    AlertSummary(
      id: 'alert-6',
      patientLabel: 'Paciente #19FA',
      microAreaName: 'Microárea 03 — Vila Esperança',
      riskLevel: RiskLevel.green,
      status: AlertStatus.resolved,
      triggeredAt: DateTime(2026, 9, 9, 11, 2),
      resolvedAt: DateTime(2026, 9, 9, 11, 30),
    ),
  ];

  /// Prazos relativos ao relógio: um vencido, os outros no prazo, e um já
  /// decidido. Já em ordem de prazo, como o servidor devolve.
  static List<DataRequestDetail> _seedPedidos(DateTime agora) {
    DataRequestDetail pedido(
      String id,
      DataRequestType type,
      DataRequestStatus status,
      Duration prazo, {
      String? details,
      String? resolution,
    }) {
      final dueAt = agora.add(prazo);
      final decidido = status == DataRequestStatus.completed || status == DataRequestStatus.rejected;
      return DataRequestDetail(
        id: id,
        type: type,
        status: status,
        createdAt: dueAt.subtract(const Duration(days: 15)),
        dueAt: dueAt,
        overdue: !decidido && agora.isAfter(dueAt),
        patientLabel: 'Paciente #${id.substring(4).toUpperCase()}',
        details: details,
        resolution: resolution,
        decidedAt: decidido ? agora.subtract(const Duration(days: 1)) : null,
      );
    }

    return [
      pedido('req-a18f', DataRequestType.correction, DataRequestStatus.open, const Duration(days: -4, hours: -3),
          details: 'Texto fictício: o nome social cadastrado está desatualizado.'),
      pedido('req-7c2e', DataRequestType.deletion, DataRequestStatus.open, const Duration(days: 5)),
      pedido('req-4d91', DataRequestType.correction, DataRequestStatus.inReview, const Duration(days: 10),
          details: 'Texto fictício: a data de nascimento está trocada.'),
      pedido('req-b6a0', DataRequestType.deletion, DataRequestStatus.rejected, const Duration(days: 12),
          resolution: 'Texto fictício: há atendimento em curso que exige o registro.'),
    ];
  }

  /// ACS sintéticos. `acs-1` e `acs-2` espelham as duas primeiras microáreas da
  /// listagem (mesmo vínculo e mesma matrícula), para as duas metades da tela
  /// contarem a mesma história; `acs-1` é a chave fixada pelos testes (Tarefa 10).
  static final _seedAcs = [
    const AcsSummary(
      id: 'acs-1',
      name: 'Carla Nogueira',
      enrollmentId: 'ACS-001',
      ubsName: _ubsSintetica,
      microAreaId: 'ma-12',
      microAreaName: 'Microárea 12 — Zona Rural',
      active: true,
      mfaActive: false,
    ),
    const AcsSummary(
      id: 'acs-2',
      name: 'Bruno Faria',
      enrollmentId: 'ACS-014',
      ubsName: _ubsSintetica,
      microAreaId: 'ma-07',
      microAreaName: 'Microárea 07 — Centro',
      active: true,
      mfaActive: true,
    ),
  ];

  /// Conta de equipe sintética: a coordenadora da UBS (o administrador não tem
  /// UBS e a listagem dele fica para quando houver mais de um papel em teste).
  static final _seedStaff = [
    const StaffSummary(
      id: 'staff-1',
      name: 'Débora Lima',
      enrollmentId: 'COO-001',
      role: 'coordinator',
      ubsName: _ubsSintetica,
      active: true,
      mfaActive: true,
    ),
  ];

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async {
    final counts = <RiskLevel, int>{
      for (final level in RiskLevel.values)
        level: _alerts.where((alert) => alert.riskLevel == level).length,
    };
    // A mesma partição do servidor (`RedAlertBucket`, #87): o `escalated`
    // legado é um aberto sem confirmação.
    final openRed = _alerts
        .where((alert) =>
            alert.riskLevel == RiskLevel.red &&
            (alert.status == AlertStatus.pending || alert.status == AlertStatus.escalated))
        .length;
    final acknowledgedRed = _alerts
        .where((alert) => alert.riskLevel == RiskLevel.red && alert.status == AlertStatus.acknowledged)
        .length;
    final resolvedRed = _alerts
        .where((alert) => alert.riskLevel == RiskLevel.red && alert.status == AlertStatus.resolved)
        .length;
    return DashboardIndicators(
      countsByRisk: counts,
      openRedAlerts: openRed,
      acknowledgedRedAlerts: acknowledgedRed,
      resolvedRedAlerts: resolvedRed,
      tmravSeconds: 78,
    );
  }

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() async => _microAreas;

  @override
  Future<List<AlertSummary>> fetchAlerts({
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final nome = microAreaId == null
        ? null
        : _microAreas.where((area) => area.id == microAreaId).map((area) => area.name).firstOrNull;
    return _alerts.where((alert) {
      if (microAreaId != null && alert.microAreaName != nome) return false;
      if (status != null && alert.status != status) return false;
      return true;
    }).skip(offset).take(limit).map(_comEscalonamento).toList();
  }

  bool _venceu(AlertSummary a) => _now().difference(a.triggeredAt) > _prazoDoVermelho;

  /// Regra do servidor: vermelho pendente, não escalonado e além do prazo.
  AlertSummary _comEscalonamento(AlertSummary a) {
    final em = _escalados[a.id];
    return AlertSummary(
      id: a.id,
      patientLabel: a.patientLabel,
      microAreaName: a.microAreaName,
      riskLevel: a.riskLevel,
      status: a.status,
      triggeredAt: a.triggeredAt,
      escalatedAt: em,
      resolvedAt: a.resolvedAt,
      overdue: em == null && a.riskLevel == RiskLevel.red && a.status == AlertStatus.pending && _venceu(a),
    );
  }

  // Avisos e termos (#46): mesmas regras e textos do servidor. O papel é
  // imposto pelo servidor, não pelo mock. A mensagem fica só aqui dentro.
  final List<NoticeHistoryItem> _avisos = [];
  final Map<String, String> _mensagensDosAvisos = {};
  final List<TermsVersionSummary> _termos = [];
  int _seqAviso = 0;
  int _seqTermo = 0;

  @override
  Future<List<NoticeHistoryItem>> fetchNoticeHistory({String? microAreaId, int limit = 50, int offset = 0}) async {
    final l = _avisos.where((a) => microAreaId == null || a.microAreaId == microAreaId).toList()
      ..sort((a, b) => b.scheduledFor.compareTo(a.scheduledFor));
    return l.skip(offset).take(limit).toList();
  }

  @override
  Future<String> scheduleNotice({
    required String microAreaId,
    required NoticeAudience audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
  }) async {
    final t = title.trim();
    final m = message.trim();
    if (t.isEmpty || m.isEmpty) throw const AdminValidationFailure('Informe o título e a mensagem do aviso.');
    if (t.length > 60) throw const AdminValidationFailure('O título pode ter no máximo 60 caracteres.');
    if (m.length > 240) throw const AdminValidationFailure('A mensagem pode ter no máximo 240 caracteres.');
    final area = _microAreas.where((x) => x.id == microAreaId).firstOrNull;
    if (area == null) throw const AdminValidationFailure('Microárea não encontrada.');
    if (scheduledFor.isBefore(_now().add(const Duration(minutes: 1)))) {
      throw const AdminValidationFailure('O horário do aviso deve ser pelo menos 1 minuto à frente.');
    }
    final id = 'aviso-${++_seqAviso}';
    _mensagensDosAvisos[id] = m;
    _avisos.add(NoticeHistoryItem(
      id: id,
      microAreaId: area.id,
      microAreaName: area.name,
      audience: audience,
      title: t,
      status: NoticeStatus.pending,
      scheduledFor: scheduledFor,
      createdByLabel: 'ADM-001',
    ));
    return id;
  }

  @override
  Future<void> cancelScheduledNotice(String id) async {
    final i = _avisos.indexWhere((a) => a.id == id);
    if (i < 0) throw const AdminValidationFailure('Aviso não encontrado.');
    final a = _avisos[i];
    if (a.status != NoticeStatus.pending) {
      throw const AdminValidationFailure('Só avisos pendentes podem ser cancelados.');
    }
    _avisos[i] = NoticeHistoryItem(
      id: a.id,
      microAreaId: a.microAreaId,
      microAreaName: a.microAreaName,
      audience: a.audience,
      title: a.title,
      status: NoticeStatus.cancelled,
      scheduledFor: a.scheduledFor,
      createdByLabel: a.createdByLabel,
    );
  }

  @override
  Future<List<TermsVersionSummary>> fetchTermsVersions() async =>
      (List.of(_termos)..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom)));

  @override
  Future<TermsVersionSummary> draftTermsVersion({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
  }) async {
    final v = version.trim();
    final s = summary.trim();
    if (v.isEmpty) throw const AdminValidationFailure('Informe o número da versão.');
    if (s.isEmpty || s.length > 280) throw const AdminValidationFailure('O resumo deve ter de 1 a 280 caracteres.');
    if (_termos.any((t) => t.version == v)) {
      throw const AdminValidationFailure('Já existe uma versão com este número.');
    }
    if (!effectiveFrom.isAfter(_now())) throw const AdminValidationFailure('A vigência deve ser futura.');
    final t = TermsVersionSummary(
      id: 'termo-${++_seqTermo}',
      version: v,
      summary: s,
      effectiveFrom: effectiveFrom,
      createdAt: _now(),
    );
    _termos.add(t);
    return t;
  }

  TermsVersionSummary _substituiTermo(TermsVersionSummary t, {DateTime? reviewed, DateTime? published}) {
    final n = TermsVersionSummary(
      id: t.id,
      version: t.version,
      summary: t.summary,
      effectiveFrom: t.effectiveFrom,
      createdAt: t.createdAt,
      legallyReviewedAt: reviewed ?? t.legallyReviewedAt,
      publishedAt: published ?? t.publishedAt,
    );
    _termos[_termos.indexWhere((x) => x.id == t.id)] = n;
    return n;
  }

  TermsVersionSummary _termo(String id) {
    final t = _termos.where((x) => x.id == id).firstOrNull;
    if (t == null) throw const AdminValidationFailure('Versão não encontrada.');
    return t;
  }

  @override
  Future<TermsVersionSummary> markTermsReviewed(String id) async {
    final t = _termo(id);
    if (t.legallyReviewedAt != null) throw const AdminValidationFailure('A versão já foi revisada.');
    return _substituiTermo(t, reviewed: _now());
  }

  @override
  Future<TermsVersionSummary> publishTermsVersion(String id) async {
    final t = _termo(id);
    if (t.publishedAt != null) throw const AdminValidationFailure('A versão já foi publicada.');
    if (t.legallyReviewedAt == null) {
      throw const AdminValidationFailure('A versão ainda não foi revisada juridicamente.');
    }
    if (t.effectiveFrom.isBefore(_now().add(const Duration(days: 15)))) {
      throw const AdminValidationFailure('A vigência exige 15 dias de antecedência.');
    }
    return _substituiTermo(t, published: _now());
  }

  @override
  Future<EscalationOutcome> escalateAlert(String alertId, EscalationReasonCode reason) async {
    final a = _alerts.where((x) => x.id == alertId).firstOrNull;
    // Mesma precedência e textos do servidor (AlertEscalationService).
    if (a == null) throw const AdminValidationFailure('Alerta não encontrado.');
    if (a.riskLevel != RiskLevel.red) {
      throw const AdminValidationFailure('Só alertas vermelhos podem ser escalonados.');
    }
    if (a.status != AlertStatus.pending) throw const AdminValidationFailure('Alerta já confirmado.');
    final anterior = _escalados[alertId];
    if (anterior != null) return EscalationOutcome(escalatedAt: anterior, alreadyEscalated: true);
    if (!_venceu(a)) {
      throw const AdminValidationFailure('O prazo para escalonar este alerta ainda não venceu.');
    }
    final agora = _now();
    _escalados[alertId] = agora;
    return EscalationOutcome(escalatedAt: agora, alreadyEscalated: false);
  }

  @override
  Future<AlertsPulse> alertsPulse() async {
    final lista = _alerts.map(_comEscalonamento).toList();
    DateTime? maior;
    for (final a in lista) {
      // A conclusão também move a marca, como no servidor (#76, `fa549b2`).
      for (final t in [a.triggeredAt, a.escalatedAt, a.resolvedAt]) {
        if (t != null && (maior == null || t.isAfter(maior))) maior = t;
      }
    }
    return AlertsPulse(
      indicators: await fetchDashboardIndicators(),
      overdueRed: lista.where((a) => a.overdue).length,
      maxChangedAt: maior,
      serverNow: _now(),
    );
  }

  @override
  Future<void> endMonitoringSession() async {
    monitoringSessionEnds++;
  }

  @override
  Future<AuditLogPage> fetchAuditLogs({
    AuditLogFilter filter = const AuditLogFilter(),
    int limit = 50,
    int? beforeSequence,
  }) async {
    final candidatas = [
      for (final e in _auditLog.reversed)
        if ((beforeSequence == null || e.sequence < beforeSequence) && _casa(e, filter)) e,
    ];
    final itens = List<AuditLogEntry>.unmodifiable(candidatas.take(limit));
    final proximo = candidatas.length > limit ? itens.last.sequence : null;
    auditQueries.add(AuditQuery(
      filter: filter,
      limit: limit,
      beforeSequence: beforeSequence,
      nextBeforeSequence: proximo,
    ));
    return AuditLogPage(items: itens, nextBeforeSequence: proximo);
  }

  /// Mesmas regras do servidor (D1/D2), sobre o rótulo do autor: matrícula
  /// é o que vem antes de " (", o papel sai do rótulo.
  static bool _casa(AuditLogEntry e, AuditLogFilter f) {
    final rotulo = e.userLabel;
    final matricula = rotulo.contains(' (') ? rotulo.substring(0, rotulo.indexOf(' (')) : rotulo;
    if (f.actorEnrollmentId != null && matricula.toLowerCase() != f.actorEnrollmentId!.toLowerCase()) return false;
    if (f.actorRole != null && _papelDoRotulo(rotulo) != f.actorRole) return false;
    if (f.actionType != null && e.actionType != f.actionType) return false;
    if (f.resourceType != null && e.resourceType != f.resourceType) return false;
    if (f.result != null && e.result != f.result) return false;
    if (f.from != null && e.timestamp.isBefore(f.from!)) return false;
    if (f.to != null && !e.timestamp.isBefore(f.to!)) return false;
    final busca = f.search?.toLowerCase();
    if (busca != null &&
        !matricula.toLowerCase().startsWith(busca) &&
        !e.resourceType.toLowerCase().contains(busca) &&
        !e.result.toLowerCase().contains(busca)) {
      return false;
    }
    return true;
  }

  static AuditActorRole? _papelDoRotulo(String rotulo) {
    if (rotulo.startsWith('Paciente')) return AuditActorRole.patient;
    if (rotulo.endsWith('(ACS)')) return AuditActorRole.acs;
    if (rotulo.endsWith('(Coordenador)')) return AuditActorRole.coordinator;
    if (rotulo.endsWith('(Administrador)')) return AuditActorRole.admin;
    return null;
  }

  @override
  Future<ChainStatus> verifyAuditChain() async {
    verifyChainCalls++;
    final erro = chainStatusError;
    if (erro != null) throw erro;
    return chainStatus ??
        ChainStatus(
          state: AuditIntegrityState.verified,
          checkedRows: _auditLog.length,
          headSequence: _auditSeq,
          verifiedAt: _now(),
        );
  }

  @override
  Future<AuditExportResult> exportAuditLogs(AuditLogFilter filter) async {
    exportCalls++;
    lastExportFilter = filter;
    if (filter.from == null || filter.to == null) {
      // O servidor recusaria; a tela nunca pede assim (botão desabilitado).
      throw ArgumentError('exportação exige início e fim do período');
    }
    final portao = exportGate;
    if (portao != null) await portao.future;
    final erro = exportError;
    if (erro != null) throw erro;
    final pronto = exportResult;
    if (pronto != null) return pronto;

    final recorte = [for (final e in _auditLog) if (_casa(e, filter)) e];
    final csv = StringBuffer('sequence,timestamp_utc,autor,papel_autor,acao,recurso,rotulo_recurso,resultado,selo\r\n');
    for (final e in recorte) {
      csv.write('${e.sequence},${e.timestamp.toUtc().toIso8601String()},${e.userLabel},,'
          '${e.actionType},${e.resourceType},,${e.result},${e.seal.name}\r\n');
    }
    return AuditExportResult(
      fileName: 'auditoria_mock.csv',
      csv: csv.toString(),
      rowCount: recorte.length,
      firstSequence: recorte.isEmpty ? null : recorte.first.sequence,
      lastSequence: recorte.isEmpty ? null : recorte.last.sequence,
      // Fictício: o mock não calcula hash (sem pacote de criptografia no app).
      contentSha256: '0' * 64,
      chainState: AuditIntegrityState.verified,
      generatedAt: _now().toUtc(),
    );
  }

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {
    _auditSeq++;
    _auditLog.add(AuditLogEntry(
      id: 'audit-$_auditSeq',
      sequence: _auditSeq,
      userLabel: 'admin.dev (Administrador)',
      actionType: actionType,
      resourceType: resourceType,
      timestamp: DateTime.now(),
      result: 'success',
      seal: AuditRowSeal.verified,
    ));
  }

  @override
  Future<List<DataRequestSummary>> fetchDataRequests({DataRequestStatus? status, int limit = 50, int offset = 0}) async =>
      _pedidos.where((p) => status == null || p.status == status).skip(offset).take(limit).toList();

  @override
  Future<DataRequestDetail> fetchDataRequest(String id) async =>
      _pedidos.firstWhere((p) => p.id == id, orElse: () => throw const AdminDataFailure(dataRequestUnavailable));

  @override
  Future<void> startDataRequestReview(String id) async =>
      _decidir(id, const {DataRequestStatus.open}, DataRequestStatus.inReview, null);

  @override
  Future<void> completeDataRequest(String id, {String? note}) async {
    if (note != null && !dataRequestTextIsValid(note)) throw const AdminDataFailure(dataRequestTextInvalid);
    _decidir(id, _abertos, DataRequestStatus.completed, note?.trim());
  }

  @override
  Future<void> rejectDataRequest(String id, {required String reason}) async {
    if (!dataRequestTextIsValid(reason)) throw const AdminDataFailure(dataRequestTextInvalid);
    _decidir(id, _abertos, DataRequestStatus.rejected, reason.trim());
  }

  static const _abertos = {DataRequestStatus.open, DataRequestStatus.inReview};

  void _decidir(String id, Set<DataRequestStatus> de, DataRequestStatus para, String? resolution) {
    final i = _pedidos.indexWhere((p) => p.id == id);
    if (i < 0 || !de.contains(_pedidos[i].status)) throw const AdminDataFailure(dataRequestUnavailable);
    final p = _pedidos[i];
    final finalizado = para != DataRequestStatus.inReview;
    _pedidos[i] = DataRequestDetail(
      id: p.id,
      type: p.type,
      status: para,
      createdAt: p.createdAt,
      dueAt: p.dueAt,
      overdue: !finalizado && _now().isAfter(p.dueAt),
      patientLabel: p.patientLabel,
      details: p.details,
      resolution: resolution,
      decidedAt: finalizado ? _now() : null,
    );
  }

  @override
  Future<List<AcsSummary>> fetchAcs() async => List.unmodifiable(_acs);

  @override
  Future<List<StaffSummary>> fetchStaff() async => List.unmodifiable(_staff);

  @override
  Future<NewAcsCredential> createAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) async {
    _acsSeq++;
    final acs = AcsSummary(
      id: 'acs-$_acsSeq',
      name: name,
      enrollmentId: enrollmentId,
      ubsName: _ubsSintetica,
      microAreaId: microAreaId,
      microAreaName: _nomeDaMicroArea(microAreaId),
      active: true,
      mfaActive: false,
    );
    _acs.add(acs);
    return NewAcsCredential(acs: acs, initialPassword: _senhaDeTeste);
  }

  @override
  Future<AcsSummary> setAcsMicroArea({
    required String acsId,
    required String microAreaId,
  }) async {
    final i = _indiceAcs(acsId);
    final novo = _comAcs(
      _acs[i],
      microAreaId: microAreaId,
      microAreaName: _nomeDaMicroArea(microAreaId),
    );
    _acs[i] = novo;
    vinculados.add(acsId);
    return novo;
  }

  @override
  Future<AcsSummary> setAcsActive({required String acsId, required bool active}) async {
    final i = _indiceAcs(acsId);
    final novo = _comAcs(_acs[i], active: active);
    _acs[i] = novo;
    if (!active) desativados.add(acsId);
    return novo;
  }

  @override
  Future<String> resetAcsPassword({required String acsId}) async {
    _indiceAcs(acsId);
    senhasRedefinidas.add(acsId);
    return _senhaDeTeste;
  }

  @override
  Future<void> resetAcsMfa({required String acsId}) async {
    final i = _indiceAcs(acsId);
    _acs[i] = _comAcs(_acs[i], mfaActive: false);
    mfasRedefinidas.add(acsId);
  }

  @override
  Future<List<AcsDevice>> fetchAcsDevices(String acsId) async {
    _indiceAcs(acsId);
    return List.of(_aparelhos[acsId] ?? const []);
  }

  @override
  Future<DeviceWipeOrderResult> orderDeviceWipe({
    required String acsId,
    required String deviceId,
    required DeviceWipeReason reason,
  }) async {
    final lista = _aparelhos[acsId] ?? const <AcsDevice>[];
    final i = lista.indexWhere((d) => d.deviceId == deviceId);
    if (i < 0) throw const AdminDataFailure('Aparelho não encontrado.');
    final d = lista[i];
    if (d.wipeState != null) {
      return DeviceWipeOrderResult(
        orderId: 'ord-$deviceId',
        requestedAt: d.wipeRequestedAt!,
        alreadyOrdered: true,
      );
    }
    limpezasPedidas.add((acsId: acsId, deviceId: deviceId, reason: reason));
    final agora = DateTime.now().toUtc();
    lista[i] = AcsDevice(
      deviceId: d.deviceId,
      label: d.label,
      lastSeenAt: d.lastSeenAt,
      wipeState: DeviceWipeState.pending,
      wipeRequestedAt: agora,
    );
    return DeviceWipeOrderResult(orderId: 'ord-$deviceId', requestedAt: agora, alreadyOrdered: false);
  }

  @override
  Future<NewStaffActivation> resetStaffMfa({required String staffId}) async {
    final i = _indiceStaff(staffId);
    final conta = _staff[i];
    _staff[i] = StaffSummary(
      id: conta.id,
      name: conta.name,
      enrollmentId: conta.enrollmentId,
      role: conta.role,
      ubsName: conta.ubsName,
      active: conta.active,
      mfaActive: false,
    );
    mfasRedefinidas.add(staffId);
    return NewStaffActivation(code: _codigoDeAtivacao, expiresAt: _codigoExpiraEm);
  }

  /// O modelo é imutável, como o do servidor: alterar uma linha é substituí-la.
  /// Campo não informado mantém o valor atual.
  static AcsSummary _comAcs(
    AcsSummary atual, {
    String? microAreaId,
    String? microAreaName,
    bool? active,
    bool? mfaActive,
  }) => AcsSummary(
    id: atual.id,
    name: atual.name,
    enrollmentId: atual.enrollmentId,
    ubsName: atual.ubsName,
    microAreaId: microAreaId ?? atual.microAreaId,
    microAreaName: microAreaName ?? atual.microAreaName,
    active: active ?? atual.active,
    mfaActive: mfaActive ?? atual.mfaActive,
  );

  String? _nomeDaMicroArea(String id) =>
      _microAreas.where((area) => area.id == id).map((area) => area.name).firstOrNull;

  int _indiceAcs(String id) {
    final i = _acs.indexWhere((a) => a.id == id);
    if (i < 0) throw StateError('ACS desconhecido no mock: $id');
    return i;
  }

  int _indiceStaff(String id) {
    final i = _staff.indexWhere((s) => s.id == id);
    if (i < 0) throw StateError('Conta de equipe desconhecida no mock: $id');
    return i;
  }
}

/// Uma consulta à trilha feita ao mock, com o cursor que ela devolveu.
class AuditQuery {
  const AuditQuery({
    required this.filter,
    required this.limit,
    required this.beforeSequence,
    required this.nextBeforeSequence,
  });

  final AuditLogFilter filter;
  final int limit;
  final int? beforeSequence;
  final int? nextBeforeSequence;
}
