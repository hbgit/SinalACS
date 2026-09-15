import 'admin_data_source.dart';

/// Implementação mock de [AdminDataSource]. Todos os dados são fictícios
/// (nenhum dado real de paciente/UBS/ACS), no espírito do `AlertStore`/
/// `AlertPublisher` fake usados nos testes do backend.
class MockAdminDataSource implements AdminDataSource {
  MockAdminDataSource()
      : _microAreas = List.unmodifiable(_seedMicroAreas),
        _alerts = List.unmodifiable(_seedAlerts);

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
  Future<List<AlertSummary>> fetchAlerts({String? microAreaName, AlertStatus? status}) async {
    return _alerts.where((alert) {
      if (microAreaName != null && alert.microAreaName != microAreaName) return false;
      if (status != null && alert.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs() async => List.unmodifiable(_auditLog.reversed);

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
}
