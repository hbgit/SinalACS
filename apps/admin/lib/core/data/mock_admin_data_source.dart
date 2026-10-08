import 'admin_data_source.dart';

/// Implementação mock de [AdminDataSource]. Todos os dados são fictícios
/// (nenhum dado real de paciente/UBS/ACS), no espírito do `AlertStore`/
/// `AlertPublisher` fake usados nos testes do backend.
class MockAdminDataSource implements AdminDataSource {
  MockAdminDataSource({DateTime Function()? now})
      : _microAreas = List.unmodifiable(_seedMicroAreas),
        _alerts = List.unmodifiable(_seedAlerts),
        _now = now ?? DateTime.now {
    _pedidos.addAll(_seedPedidos(_now()));
  }

  final DateTime Function() _now;

  /// Pedidos do titular (#42), mutáveis para as decisões do mock. Textos
  /// fictícios; nenhum dado real de paciente.
  final List<DataRequestDetail> _pedidos = [];

  final List<MicroAreaSummary> _microAreas;
  final List<AlertSummary> _alerts;
  final List<AuditLogEntry> _auditLog = [];
  int _auditSeq = 0;

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
}
