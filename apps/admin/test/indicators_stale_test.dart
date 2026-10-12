import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

import 'support/scripted_pulse_data_source.dart';

/// Painel de indicadores alimentado pelo pulso (#44, Task 11; ADR D5): o
/// dashboard não consulta `fetchDashboardIndicators` em laço.
void main() {
  late DateTime agora;
  late ScriptedPulseDataSource fonte;

  setUp(() {
    agora = DateTime(2026, 10, 11, 9);
    fonte = ScriptedPulseDataSource(now: () => agora);
  });

  Future<void> montarPainel(WidgetTester tester) async {
    final monitoramento = MonitoringController(dataSource: fonte, now: () => agora);
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: IndicatorsScreen(dataSource: fonte, monitoring: monitoramento)),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> ciclo(WidgetTester tester, {Duration relogio = const Duration(seconds: 30)}) async {
    agora = agora.add(relogio);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('painel atualiza contagens e TMRAV pelo pulso', (tester) async {
    await montarPainel(tester);
    expect(find.text('78s'), findsOneWidget);

    fonte.indicadores = const DashboardIndicators(
      countsByRisk: {RiskLevel.red: 9, RiskLevel.yellow: 2, RiskLevel.green: 1},
      openRedAlerts: 4,
      acknowledgedRedAlerts: 5,
      tmravSeconds: 42,
    );
    await ciclo(tester);

    expect(find.text('42s'), findsOneWidget);
    expect(find.text('78s'), findsNothing);
    expect(
      find.descendant(of: find.byKey(const Key('risk_counter_red')), matching: find.text('9')),
      findsOneWidget,
    );
    expect(fonte.buscasDeIndicadores, 1, reason: 'só o carregamento inicial lê os indicadores; o resto vem do pulso');
  });

  testWidgets('painel mostra o selo com dado velho', (tester) async {
    await montarPainel(tester);
    fonte.falhaDoPulso = StateError('rede fora');

    // 31 s sem sucesso: ainda tolerado.
    await ciclo(tester, relogio: const Duration(seconds: 31));
    expect(find.byKey(const Key('stale_badge')), findsNothing);

    // 61 s: desatualizado.
    await ciclo(tester);
    expect(find.byKey(const Key('stale_badge')), findsOneWidget);
    expect(find.text('Dados de 09:00:00 — sem atualização há 2 min'), findsOneWidget);
    // O dado velho continua na tela, sem erro em tela cheia.
    expect(find.text('Painel de Indicadores'), findsOneWidget);
    expect(find.text('78s'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);

    fonte.falhaDoPulso = null;
    await ciclo(tester);
    expect(find.byKey(const Key('stale_badge')), findsNothing);
  });
}
