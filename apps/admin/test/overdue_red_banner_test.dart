import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

import 'support/scripted_pulse_data_source.dart';

/// Contador "N vermelhos vencidos" (#44, F2) e o filtro de status sem
/// "Escalonado" (F1).
///
/// O contador vem do `overdueRed` do último pulso: é ele que mostra ao
/// coordenador que existe vermelho vencido mesmo quando o filtro da lista o
/// esconde. Não é botão.
void main() {
  late DateTime agora;
  late ScriptedPulseDataSource fonte;
  final faixa = find.byKey(const Key('overdue_red_banner'));

  setUp(() {
    agora = DateTime(2026, 10, 11, 9);
    fonte = ScriptedPulseDataSource(now: () => agora);
  });

  Future<MonitoringController> montar(WidgetTester tester, Widget Function(MonitoringController) tela) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    final monitoramento = MonitoringController(dataSource: fonte, now: () => agora);
    await tester.pumpWidget(MaterialApp(theme: buildAdminTheme(), home: Scaffold(body: tela(monitoramento))));
    await tester.pump();
    await tester.pump();
    return monitoramento;
  }

  Future<void> ciclo(WidgetTester tester) async {
    agora = agora.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump();
  }

  Future<void> encerrar(WidgetTester tester, MonitoringController m) async {
    await tester.pumpWidget(const SizedBox());
    m.dispose();
  }

  for (final (nome, tela) in <(String, Widget Function(ScriptedPulseDataSource, MonitoringController))>[
    ('Painel', (f, m) => IndicatorsScreen(dataSource: f, monitoring: m)),
    ('Alertas', (f, m) => AlertsScreen(dataSource: f, monitoring: m)),
  ]) {
    testWidgets('$nome: contador aparece com overdueRed=2 e some com 0', (tester) async {
      fonte.overdueRed = 2;
      final m = await montar(tester, (m) => tela(fonte, m));

      expect(faixa, findsOneWidget);
      expect(find.descendant(of: faixa, matching: find.text('2 vermelhos vencidos')), findsOneWidget);
      // Ícone + texto, não só cor (WCAG 1.4.1).
      expect(find.descendant(of: faixa, matching: find.byType(Icon)), findsOneWidget);
      // Não é botão: nada ali é tocável.
      expect(find.descendant(of: faixa, matching: find.byType(InkWell)), findsNothing);
      expect(find.descendant(of: faixa, matching: find.byType(ButtonStyleButton)), findsNothing);

      fonte.overdueRed = 0;
      await ciclo(tester);
      expect(faixa, findsNothing);
      expect(find.textContaining('vencido'), findsNothing);
      await encerrar(tester, m);
    });

    testWidgets('$nome: singular com 1', (tester) async {
      fonte.overdueRed = 1;
      final m = await montar(tester, (m) => tela(fonte, m));
      expect(find.text('1 vermelho vencido'), findsOneWidget);
      expect(find.text('1 vermelhos vencidos'), findsNothing);
      await encerrar(tester, m);
    });
  }

  testWidgets('contador usa o token de texto e é anunciado (liveRegion)', (tester) async {
    fonte.overdueRed = 3;
    final m = await montar(tester, (m) => IndicatorsScreen(dataSource: fonte, monitoring: m));

    final texto = tester.widget<Text>(find.text('3 vermelhos vencidos'));
    expect(texto.style?.color, AdminColors.redOnSurface, reason: 'texto vermelho sobre card usa o token *OnSurface, nunca o fill');
    final icone = tester.widget<Icon>(find.descendant(of: faixa, matching: find.byType(Icon)));
    expect(icone.color, AdminColors.redOnSurface);

    final semantica = tester.getSemantics(faixa);
    expect(semantica.flagsCollection.isLiveRegion, isTrue);
    expect(semantica.label, contains('3 vermelhos vencidos'));
    await encerrar(tester, m);
  });

  testWidgets('dropdown de status não oferece "Escalonado"', (tester) async {
    fonte.overdueRed = 0;
    final m = await montar(tester, (m) => AlertsScreen(dataSource: fonte, monitoring: m));

    await tester.tap(find.byKey(const Key('alerts_status_filter')));
    await tester.pumpAndSettle();

    final opcoes = tester
        .widgetList<DropdownMenuItem<AlertStatus?>>(find.byType(DropdownMenuItem<AlertStatus?>))
        .map((i) => i.value)
        .toSet();
    expect(opcoes, {null, AlertStatus.pending, AlertStatus.acknowledged, AlertStatus.resolved});
    expect(opcoes, isNot(contains(AlertStatus.escalated)));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await encerrar(tester, m);
  });

  testWidgets('linha legada com status escalated ainda mostra "Escalonado"', (tester) async {
    fonte.overdueRed = 0;
    final m = await montar(tester, (m) => AlertsScreen(dataSource: fonte, monitoring: m));

    // alert-5 do mock é a linha legada (`AlertStatus.escalated`).
    final linha = find.byKey(const Key('alert_alert-5'), skipOffstage: false);
    expect(linha, findsOneWidget);
    expect(find.descendant(of: linha, matching: find.text('Status: Escalonado'), skipOffstage: false), findsOneWidget);
    await encerrar(tester, m);
  });
}
