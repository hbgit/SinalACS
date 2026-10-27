import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/escalate_alert_dialog.dart' show horaLocal;
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

/// Fonte com um vermelho `resolved` SEM `resolvedAt` (linha concluída antes
/// da coluna existir): a tela mostra o estado e nenhuma hora, sem lançar.
class _ConcluidoSemHora extends MockAdminDataSource {
  @override
  Future<List<AlertSummary>> fetchAlerts({
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) async => [
        AlertSummary(
          id: 'legado',
          patientLabel: 'Paciente #L3G0',
          microAreaName: 'Microárea 12 — Zona Rural',
          riskLevel: RiskLevel.red,
          status: AlertStatus.resolved,
          triggeredAt: DateTime(2026, 9, 11, 8, 12),
        ),
      ];
}

Finder _noCartao(String id, Finder alvo) => find.descendant(of: find.byKey(Key('alert_$id')), matching: alvo);

/// Fonte com um vermelho escalonado pelo backoffice e depois concluído pelo
/// ACS: os dois selos aparecem, na ordem em que aconteceram.
class _EscalonadoEConcluido extends MockAdminDataSource {
  @override
  Future<List<AlertSummary>> fetchAlerts({
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) async => [
        AlertSummary(
          id: 'ambos',
          patientLabel: 'Paciente #AMB0',
          microAreaName: 'Microárea 12 — Zona Rural',
          riskLevel: RiskLevel.red,
          status: AlertStatus.resolved,
          triggeredAt: DateTime(2026, 9, 11, 8, 12),
          escalatedAt: DateTime(2026, 9, 11, 8, 20),
          resolvedAt: DateTime(2026, 9, 11, 8, 50),
        ),
      ];
}

/// Estado "Concluído" e a hora da conclusão na lista de alertas (#87).
void main() {
  Future<void> montar(WidgetTester tester, AdminDataSource fonte) async {
    // Tela alta: os cartões concluídos (alert-4, alert-6) ficam no fim.
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: AlertsScreen(dataSource: fonte)),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('cartão concluído mostra "Concluído" e a hora; pendente não mostra hora', (tester) async {
    await montar(tester, MockAdminDataSource());

    expect(_noCartao('alert-4', find.text('Status: Concluído')), findsOneWidget);
    expect(_noCartao('alert-4', find.text('Concluído às ${horaLocal(DateTime(2026, 9, 10, 19, 40))}')), findsOneWidget);
    expect(_noCartao('alert-1', find.textContaining('Concluído às')), findsNothing);
    expect(find.text('Status: Resolvido'), findsNothing, reason: 'o vocabulário é o do ACS: "Concluir atendimento"');
  });

  testWidgets('resolved sem resolvedAt mostra o estado sem a hora e não lança', (tester) async {
    await montar(tester, _ConcluidoSemHora());

    expect(tester.takeException(), isNull);
    expect(find.text('Status: Concluído'), findsOneWidget);
    expect(find.textContaining('Concluído às'), findsNothing);
  });

  testWidgets('escalonado e depois concluído mostra os dois selos em ordem cronológica', (tester) async {
    await montar(tester, _EscalonadoEConcluido());

    final escalonado = _noCartao('ambos', find.textContaining('Escalonado às'));
    final concluido = _noCartao('ambos', find.textContaining('Concluído às'));
    expect(escalonado, findsOneWidget);
    expect(concluido, findsOneWidget);
    expect(tester.getTopLeft(escalonado).dy, lessThan(tester.getTopLeft(concluido).dy),
        reason: 'o escalonamento veio antes da conclusão');
  });

  testWidgets('o filtro de status oferece "Concluído" e filtra por ele', (tester) async {
    await montar(tester, MockAdminDataSource());

    await tester.tap(find.byKey(const Key('alerts_status_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concluído').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('alert_alert-4')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-6')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-1'), skipOffstage: false), findsNothing);
    expect(find.byKey(const Key('alert_alert-2'), skipOffstage: false), findsNothing);
  });
}
