import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';
import 'support/scripted_pulse_data_source.dart';

/// Fonte que só troca os contadores de vermelhos do mock: o resto do painel
/// segue igual. 1 aberto + 1 reconhecido + 2 concluídos = 4 vermelhos.
class _ComContadores extends MockAdminDataSource {
  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async {
    final base = await super.fetchDashboardIndicators();
    return DashboardIndicators(
      countsByRisk: {...base.countsByRisk, RiskLevel.red: 4},
      openRedAlerts: 1,
      acknowledgedRedAlerts: 1,
      resolvedRedAlerts: 2,
      tmravSeconds: base.tmravSeconds,
    );
  }
}

/// A linha [rotulo] do Painel mostra [valor]? A linha é a `_InfoRow` (o
/// `Padding` mais próximo do rótulo), para o número não casar com outro
/// contador da tela.
bool linha(String rotulo, String valor) {
  final r = find.text(rotulo);
  if (r.evaluate().isEmpty) return false;
  final l = find.ancestor(of: r, matching: find.byType(Padding)).first;
  return find.descendant(of: l, matching: find.text(valor)).evaluate().isNotEmpty;
}

/// Linha "Concluídos" do Painel de Indicadores (#87, INV-03): um vermelho
/// concluído sai de "Reconhecidos" e entra em "Concluídos", nunca some.
void main() {
  testWidgets('Indicadores mostra Abertos, Reconhecidos e Concluídos, e a soma fecha com Vermelho', (tester) async {
    await tester.pumpWidget(SinalAdminApp(dataSource: _ComContadores(), auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);

    expect(linha('Abertos (pendentes)', '1'), isTrue, reason: 'Abertos = 1');
    expect(linha('Reconhecidos (em atendimento)', '1'), isTrue, reason: 'Reconhecidos = 1');
    expect(linha('Concluídos', '2'), isTrue, reason: 'Concluídos = 2');
    expect(find.text('Reconhecidos'), findsNothing, reason: 'o rótulo antigo, sem a ressalva, saiu');
    // 1 + 1 + 2 == 4, o cartão Vermelho.
    expect(
      find.descendant(of: find.byKey(const Key('risk_counter_red')), matching: find.text('4')),
      findsOneWidget,
    );
  });

  testWidgets('a linha Concluídos anda pelo pulso, sem toque (#87)', (tester) async {
    var agora = DateTime(2026, 10, 11, 9);
    final fonte = ScriptedPulseDataSource(now: () => agora);
    final monitoramento = MonitoringController(dataSource: fonte, now: () => agora);
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: IndicatorsScreen(dataSource: fonte, monitoring: monitoramento)),
    ));
    await tester.pump();
    await tester.pump();
    expect(linha('Concluídos', '0'), isTrue, reason: 'o mock não tem vermelho concluído');

    // O mock tem 2 vermelhos (1 aberto, 1 reconhecido): um concluído a mais
    // faz 3. Constante, não `fetchDashboardIndicators()`: a chamada contaria
    // como leitura da tela.
    fonte.indicadores = const DashboardIndicators(
      countsByRisk: {RiskLevel.red: 3, RiskLevel.yellow: 2, RiskLevel.green: 2},
      openRedAlerts: 1,
      acknowledgedRedAlerts: 1,
      resolvedRedAlerts: 1,
      tmravSeconds: 78,
    );
    agora = agora.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump();

    expect(linha('Concluídos', '1'), isTrue, reason: 'o pulso trouxe o concluído');
    expect(fonte.buscasDeIndicadores, 1, reason: 'só o carregamento inicial lê os indicadores; o resto vem do pulso');
  });
}
