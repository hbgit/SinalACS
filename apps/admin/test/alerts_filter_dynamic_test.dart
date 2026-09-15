import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Duplo com uma microárea que não existe na antiga lista fixa do dropdown de
/// filtro (achado da revisão do PR: as opções eram três strings fixas no
/// código, então uma microárea nova nunca apareceria como filtro possível,
/// mesmo já tendo alertas).
class _CustomAreaDataSource implements AdminDataSource {
  static const newArea = 'Microárea 99 — Nova Área';

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async => const DashboardIndicators(
        countsByRisk: {},
        openRedAlerts: 0,
        acknowledgedRedAlerts: 0,
        tmravSeconds: 0,
      );

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() async => const [
        MicroAreaSummary(id: 'ma-99', name: newArea, acsName: 'Fulana', acsEnrollmentId: 'ACS-099', acsActive: true),
      ];

  @override
  Future<List<AlertSummary>> fetchAlerts({String? microAreaName, AlertStatus? status}) async => [
        AlertSummary(
          id: 'alert-99',
          patientLabel: 'Paciente #999',
          microAreaName: newArea,
          riskLevel: RiskLevel.green,
          status: AlertStatus.resolved,
          triggeredAt: DateTime(2026, 9, 15),
        ),
      ].where((a) => microAreaName == null || a.microAreaName == microAreaName).toList();

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs() async => const [];

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {}
}

void main() {
  testWidgets('opções do filtro de microárea vêm de fetchMicroAreas(), não de uma lista fixa', (tester) async {
    await tester.pumpWidget(SinalAdminApp(dataSource: _CustomAreaDataSource()));
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('alerts_micro_area_filter')));
    await tester.pumpAndSettle();

    expect(find.text(_CustomAreaDataSource.newArea), findsWidgets);
  });
}
