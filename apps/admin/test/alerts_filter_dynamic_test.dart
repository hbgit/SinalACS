import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

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
  Future<List<AlertSummary>> fetchAlerts({String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0}) async => [
        AlertSummary(
          id: 'alert-99',
          patientLabel: 'Paciente #999',
          microAreaName: newArea,
          riskLevel: RiskLevel.green,
          status: AlertStatus.resolved,
          triggeredAt: DateTime(2026, 9, 15),
        ),
      ].where((a) => microAreaId == null || microAreaId == 'ma-99').toList();

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50}) async => const [];

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {}

  // Pedidos do titular (#42): fora do escopo deste teste.
  @override
  Future<List<DataRequestSummary>> fetchDataRequests({DataRequestStatus? status, int limit = 50, int offset = 0}) async => const [];

  @override
  Future<DataRequestDetail> fetchDataRequest(String id) => throw UnimplementedError();

  @override
  Future<void> startDataRequestReview(String id) => throw UnimplementedError();

  @override
  Future<void> completeDataRequest(String id, {String? note}) => throw UnimplementedError();

  @override
  Future<void> rejectDataRequest(String id, {required String reason}) => throw UnimplementedError();
  // A gestão de contas (#43) não é exercitada aqui: este teste fica na aba
  // Alertas, e a tela Microáreas nem chega a ser montada.
  @override
  Future<List<AcsSummary>> fetchAcs() => throw UnimplementedError('não usado neste teste');

  @override
  Future<List<StaffSummary>> fetchStaff() => throw UnimplementedError('não usado neste teste');

  @override
  Future<NewAcsCredential> createAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) => throw UnimplementedError('não usado neste teste');

  @override
  Future<AcsSummary> setAcsMicroArea({required String acsId, required String microAreaId}) =>
      throw UnimplementedError('não usado neste teste');

  @override
  Future<AcsSummary> setAcsActive({required String acsId, required bool active}) =>
      throw UnimplementedError('não usado neste teste');

  @override
  Future<String> resetAcsPassword({required String acsId}) => throw UnimplementedError('não usado neste teste');

  @override
  Future<void> resetAcsMfa({required String acsId}) => throw UnimplementedError('não usado neste teste');

  @override
  Future<NewStaffActivation> resetStaffMfa({required String staffId}) =>
      throw UnimplementedError('não usado neste teste');
}

void main() {
  testWidgets('opções do filtro de microárea vêm de fetchMicroAreas(), não de uma lista fixa', (tester) async {
    await tester.pumpWidget(SinalAdminApp(dataSource: _CustomAreaDataSource(), auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);

    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('alerts_micro_area_filter')));
    await tester.pumpAndSettle();

    expect(find.text(_CustomAreaDataSource.newArea), findsWidgets);
  });
}
