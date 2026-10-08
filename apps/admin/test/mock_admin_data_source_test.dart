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
      microAreaId: 'ma-07',
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

  test('pedidos do titular: fixtures sintéticas ordenadas por prazo, com um vencido', () async {
    final dataSource = MockAdminDataSource();

    final pedidos = await dataSource.fetchDataRequests();

    expect(pedidos, isNotEmpty);
    for (var i = 1; i < pedidos.length; i++) {
      expect(pedidos[i - 1].dueAt.isAfter(pedidos[i].dueAt), isFalse);
    }
    expect(pedidos.where((p) => p.overdue), isNotEmpty);
  });

  test('pedidos do titular: atender correção muda o status e grava a resposta', () async {
    final dataSource = MockAdminDataSource();

    await dataSource.completeDataRequest('req-a18f', note: 'Resposta fictícia.');
    final pedido = await dataSource.fetchDataRequest('req-a18f');

    expect(pedido.status, DataRequestStatus.completed);
    expect(pedido.resolution, 'Resposta fictícia.');
    expect(pedido.overdue, isFalse, reason: 'decidido não é mais vencido');
    await expectLater(
      dataSource.rejectDataRequest('req-a18f', reason: 'tarde demais'),
      throwsA(isA<AdminDataFailure>()),
    );
  });
}
