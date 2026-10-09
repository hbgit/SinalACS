import 'admin_data_source.dart';

/// Implementação mock de [AdminDataSource]. Todos os dados são fictícios
/// (nenhum dado real de paciente/UBS/ACS), no espírito do `AlertStore`/
/// `AlertPublisher` fake usados nos testes do backend.
class MockAdminDataSource implements AdminDataSource {
  MockAdminDataSource()
      : _microAreas = List.unmodifiable(_seedMicroAreas),
        _alerts = List.unmodifiable(_seedAlerts),
        _acs = [..._seedAcs],
        _staff = [..._seedStaff];

  final List<MicroAreaSummary> _microAreas;
  final List<AlertSummary> _alerts;
  final List<AcsSummary> _acs;
  final List<StaffSummary> _staff;
  final List<AuditLogEntry> _auditLog = [];
  int _auditSeq = 0;
  int _acsSeq = _seedAcs.length;

  /// Chamadas de escrita registradas para os testes de tela (Tarefa 10): o que
  /// se prova não é só o estado final, e sim que a chamada aconteceu — e que
  /// **não** aconteceu quando a ação foi cancelada.
  final List<String> desativados = [];
  final List<String> vinculados = [];
  final List<String> senhasRedefinidas = [];
  final List<String> mfasRedefinidas = [];

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
    ),
  ];

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
    final openRed = _alerts
        .where((alert) => alert.riskLevel == RiskLevel.red && alert.status == AlertStatus.pending)
        .length;
    final acknowledgedRed = _alerts
        .where((alert) => alert.riskLevel == RiskLevel.red && alert.status == AlertStatus.acknowledged)
        .length;
    return DashboardIndicators(
      countsByRisk: counts,
      openRedAlerts: openRed,
      acknowledgedRedAlerts: acknowledgedRed,
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
    }).skip(offset).take(limit).toList();
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50}) async =>
      List.unmodifiable(_auditLog.reversed.take(limit));

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {
    _auditSeq++;
    _auditLog.add(AuditLogEntry(
      id: 'audit-$_auditSeq',
      userLabel: 'admin.dev (Administrador)',
      actionType: actionType,
      resourceType: resourceType,
      timestamp: DateTime.now(),
      result: 'success',
    ));
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
