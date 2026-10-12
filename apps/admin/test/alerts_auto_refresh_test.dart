import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';
import 'support/scripted_pulse_data_source.dart';

/// Atualização automática por pulso (#44, Task 11; ADR D5).
///
/// O relógio do controlador e o do mock são o mesmo `agora`, avançado pelo
/// teste junto com `tester.pump(Duration)` (que só avança os timers falsos).
void main() {
  late DateTime agora;
  late ScriptedPulseDataSource fonte;

  setUp(() {
    agora = DateTime(2026, 10, 11, 9);
    fonte = ScriptedPulseDataSource(now: () => agora);
  });

  MonitoringController controlador() => MonitoringController(dataSource: fonte, now: () => agora);

  Future<void> montarAlertas(WidgetTester tester, MonitoringController monitoramento) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: AlertsScreen(dataSource: fonte, monitoring: monitoramento)),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// Avança um ciclo: relógio e timers juntos, e deixa os futuros assentarem.
  Future<void> ciclo(WidgetTester tester, {Duration relogio = const Duration(seconds: 30)}) async {
    agora = agora.add(relogio);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('primeiro pulso é imediato e há um pulso a cada 30 s', (tester) async {
    await montarAlertas(tester, controlador());
    expect(fonte.pulsos, 1, reason: 'o 1º pulso abre a sessão no servidor: é imediato');

    await tester.pump(const Duration(seconds: 29));
    expect(fonte.pulsos, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(fonte.pulsos, 2);
    await ciclo(tester);
    expect(fonte.pulsos, 3);
  });

  testWidgets('lista recarrega sozinha quando maxChangedAt muda (sem toque)', (tester) async {
    // Tela alta: o alerta novo entra no fim da lista, e o ListView só monta
    // o que cabe na tela.
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    await montarAlertas(tester, controlador());
    expect(fonte.buscasDeAlertas, 1);
    expect(find.byKey(const Key('alert_novo')), findsNothing);

    fonte
      ..maxChangedAt = DateTime(2026, 10, 11, 9, 0, 20)
      ..extras.add(AlertSummary(
        id: 'novo',
        patientLabel: 'Paciente #0N0V',
        microAreaName: 'Microárea 12 — Zona Rural',
        riskLevel: RiskLevel.red,
        status: AlertStatus.pending,
        triggeredAt: DateTime(2026, 10, 11, 9, 0, 20),
      ));
    await ciclo(tester);

    expect(fonte.buscasDeAlertas, 2);
    expect(find.byKey(const Key('alert_novo')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
  });

  testWidgets('lista recarrega quando só as contagens do pulso mudam', (tester) async {
    await montarAlertas(tester, controlador());
    expect(fonte.buscasDeAlertas, 1);

    // maxChangedAt igual: um alerta que saiu do escopo não o move.
    fonte.overdueRed = 7;
    await ciclo(tester);
    expect(fonte.buscasDeAlertas, 2);

    final base = await fonte.fetchDashboardIndicators();
    fonte.buscasDeIndicadores = 0;
    fonte.indicadores = DashboardIndicators(
      countsByRisk: {...base.countsByRisk, RiskLevel.green: 0},
      openRedAlerts: base.openRedAlerts,
      acknowledgedRedAlerts: base.acknowledgedRedAlerts,
      tmravSeconds: base.tmravSeconds,
    );
    await ciclo(tester);
    expect(fonte.buscasDeAlertas, 3);
  });

  testWidgets('pulso sem mudança não recarrega a lista', (tester) async {
    await montarAlertas(tester, controlador());
    expect(fonte.buscasDeAlertas, 1, reason: 'o 1º pulso só estabelece a linha de base');

    await ciclo(tester);
    await ciclo(tester);
    await ciclo(tester);
    expect(fonte.pulsos, 4);
    expect(fonte.buscasDeAlertas, 1);
  });

  testWidgets('falha do pulso mantém as linhas e mostra o selo após 60 s', (tester) async {
    await montarAlertas(tester, controlador());
    expect(find.byKey(const Key('stale_badge')), findsNothing);

    fonte.falhaDoPulso = const AdminDataFailure('Não foi possível conectar ao servidor.');
    // 31 s sem sucesso (1 s de latência): tolera uma falha.
    await ciclo(tester, relogio: const Duration(seconds: 31));
    expect(find.byKey(const Key('stale_badge')), findsNothing);
    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);

    // 61 s desde o último sucesso.
    await ciclo(tester);
    expect(find.byKey(const Key('stale_badge')), findsOneWidget);
    expect(find.text('Dados de 09:00:00 — sem atualização há 2 min'), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-3')), findsOneWidget);
    expect(find.text('Não foi possível conectar ao servidor.'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets('selo some quando o pulso volta a ter sucesso', (tester) async {
    await montarAlertas(tester, controlador());
    fonte.falhaDoPulso = StateError('rede fora');
    await ciclo(tester, relogio: const Duration(seconds: 31));
    await ciclo(tester);
    expect(find.byKey(const Key('stale_badge')), findsOneWidget);

    fonte.falhaDoPulso = null;
    await ciclo(tester);
    expect(find.byKey(const Key('stale_badge')), findsNothing);
    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
  });

  testWidgets('falha do recarregamento da lista mantém as linhas e conta como falha', (tester) async {
    await montarAlertas(tester, controlador());
    // O pulso tem sucesso, mas a recarga que ele dispara falha.
    fonte
      ..maxChangedAt = DateTime(2026, 10, 11, 9, 0, 10)
      ..falhaDasBuscas = StateError('recarga falhou');
    await ciclo(tester);
    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
    expect(find.text('Não foi possível carregar os alertas.'), findsNothing);
  });

  testWidgets('um único pulso por ciclo com as duas telas vivas', (tester) async {
    // O shell troca de tela (não usa IndexedStack), mas o contrato é do
    // controlador: com o painel e a lista montados ao mesmo tempo sobre o
    // mesmo controlador, continua um pulso só por ciclo.
    final monitoramento = controlador();
    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(
        body: Column(children: [
          Expanded(child: IndicatorsScreen(dataSource: fonte, monitoring: monitoramento)),
          Expanded(child: AlertsScreen(dataSource: fonte, monitoring: monitoramento)),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(fonte.pulsos, 1);

    await ciclo(tester);
    expect(fonte.pulsos, 2);
    await ciclo(tester);
    expect(fonte.pulsos, 3);
  });

  testWidgets('no shell, trocar entre Painel e Alertas não abre outro ciclo de pulso', (tester) async {
    await tester.pumpWidget(SinalAdminApp(dataSource: fonte, auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);
    expect(fonte.pulsos, 1);

    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();
    expect(fonte.pulsos, 1, reason: 'a troca de aba não reinicia a sessão de monitoramento');
    expect(fonte.monitoringSessionEnds, 0);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(fonte.pulsos, 2);

    // Fora das telas de monitoração não há pulso: a sessão termina.
    await tester.tap(find.text('Auditoria').last);
    await tester.pumpAndSettle();
    expect(fonte.monitoringSessionEnds, 1);
    await tester.pump(const Duration(seconds: 90));
    expect(fonte.pulsos, 2);
  });

  testWidgets('timer cancelado no dispose e endMonitoringSession disparado sem await', (tester) async {
    // Um END que nunca completa: se alguém desse `await` nele, a desmontagem
    // ficaria pendurada.
    fonte.fimDaSessao = Completer<void>().future;
    // Sem controlador injetado: a tela cria e descarta o próprio.
    await tester.pumpWidget(MaterialApp(theme: buildAdminTheme(), home: Scaffold(body: AlertsScreen(dataSource: fonte))));
    await tester.pump();
    expect(fonte.pulsos, 1);

    await tester.pumpWidget(const SizedBox());
    expect(fonte.monitoringSessionEnds, 1);

    await tester.pump(const Duration(seconds: 120));
    expect(fonte.pulsos, 1, reason: 'nenhum pulso depois do dispose');
  });

  testWidgets('dispose do shell dispara um único endMonitoringSession', (tester) async {
    await tester.pumpWidget(SinalAdminApp(dataSource: fonte, auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);
    expect(fonte.pulsos, 1);

    await tester.pumpWidget(const SizedBox());
    expect(fonte.monitoringSessionEnds, 1);
    await tester.pump(const Duration(seconds: 120));
    expect(fonte.pulsos, 1);
  });

  testWidgets('app em segundo plano pausa o timer; ao voltar faz pulso imediato', (tester) async {
    await montarAlertas(tester, controlador());
    expect(fonte.pulsos, 1);

    for (final estado in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    await tester.pump();
    expect(fonte.monitoringSessionEnds, 1, reason: 'um END só, por mais estados de fundo que cheguem');

    await tester.pump(const Duration(seconds: 120));
    expect(fonte.pulsos, 1, reason: 'em segundo plano não há pulso');

    for (final estado in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    await tester.pump();
    expect(fonte.pulsos, 2, reason: 'ao voltar, pulso imediato');

    await tester.pump(const Duration(seconds: 30));
    expect(fonte.pulsos, 3, reason: 'e o ciclo de 30 s é retomado');
  });

  testWidgets('pulso com sessão vencida segue o encerramento de sessão do app', (tester) async {
    fonte.falhaDoPulso = const AdminSessionExpired();
    await tester.pumpWidget(SinalAdminApp(dataSource: fonte, auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);

    expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
    expect(find.byKey(const Key('stale_badge')), findsNothing);
    final pulsos = fonte.pulsos;
    await tester.pump(const Duration(seconds: 90));
    expect(fonte.pulsos, pulsos, reason: 'sessão vencida não segue pulsando');
  });
}
