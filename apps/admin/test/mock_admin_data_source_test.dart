import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

void main() {
  test('deve calcular contadores por risco e métricas de alerta vermelho a partir dos alertas mockados', () async {
    final dataSource = MockAdminDataSource();

    final indicators = await dataSource.fetchDashboardIndicators();

    expect(indicators.countsByRisk[RiskLevel.red], 2);
    expect(indicators.countsByRisk[RiskLevel.yellow], 2);
    expect(indicators.countsByRisk[RiskLevel.green], 2);
    expect(indicators.openRedAlerts, 1);
    expect(indicators.acknowledgedRedAlerts, 1);
  });

  test('deve filtrar alertas por microárea e status combinados', () async {
    final dataSource = MockAdminDataSource();

    final filtered = await dataSource.fetchAlerts(
      microAreaName: 'Microárea 07 — Centro',
      status: AlertStatus.acknowledged,
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.id, 'alert-3');
  });

  test('deve registrar acessos em ordem cronológica reversa (mais recente primeiro)', () async {
    final dataSource = MockAdminDataSource();

    await dataSource.recordAccess(actionType: 'view', resourceType: 'micro_areas');
    await dataSource.recordAccess(actionType: 'view', resourceType: 'alerts');

    final log = await dataSource.fetchAuditLogs();

    expect(log, hasLength(2));
    expect(log.first.resourceType, 'alerts');
    expect(log.last.resourceType, 'micro_areas');
  });
}
