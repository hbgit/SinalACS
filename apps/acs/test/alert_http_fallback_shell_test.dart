import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar;

/// Reserva por HTTP no painel (#80, R2): consulta ao abrir, a cada intervalo
/// só enquanto o broker está fora, e nunca duas ao mesmo tempo.
const _intervalo = Duration(seconds: 1);

const _brokerFora = AlertFeedFailure(
  AlertFeedFailureKind.unreachable,
  title: 'Sem conexão com a central de alertas.',
  detail: 'Novos alertas podem não estar chegando.',
  transient: true,
);

AcsOpenAlert _aberto(String id) => AcsOpenAlert(
      alertId: id,
      patientId: seedPatientId,
      microAreaId: seedMicroAreaId,
      riskLevel: RiskLevel.red,
      locationHash: 'hash-sintetico',
      triggeredAt: DateTime.utc(2026, 10, 17, 12),
      status: AlertStatus.pending,
      escalated: false,
    );

void main() {
  late FakeAcsBackend backend;
  late FakeAlertFeed feed;

  Future<void> abrir(WidgetTester tester, {AlertFeedFailure? falhaDoFeed}) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      alertFallbackInterval: _intervalo,
      feedBuilder: (q) => feed = FakeAlertFeed(q, failure: falhaDoFeed),
    ));
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
  }

  /// Avança o relógio falso em passos do intervalo, deixando cada consulta
  /// terminar antes do próximo tique.
  Future<void> avancar(WidgetTester tester, int tiques) async {
    for (var i = 0; i < tiques; i++) {
      await tester.pump(_intervalo);
      await tester.pump();
    }
  }

  setUp(() => backend = FakeAcsBackend());

  testWidgets('ao abrir o painel consulta uma vez, mesmo com o broker conectado', (tester) async {
    await abrir(tester);
    expect(backend.openAlertsCalls, 1);

    await avancar(tester, 3);
    expect(backend.openAlertsCalls, 1, reason: 'broker conectado: sem tique');
    expect(find.byKey(const Key('alert_fallback_status')), findsNothing);
  });

  testWidgets('broker fora: o alerta do servidor aparece sem toque e a linha de status mostra a reserva',
      (tester) async {
    await abrir(tester, falhaDoFeed: _brokerFora);
    backend.openAlertsResult = [_aberto('via-http')];

    await avancar(tester, 1);

    expect(find.byKey(const Key('alert_via-http')), findsOneWidget);
    expect(find.byKey(const Key('alert_fallback_status')), findsOneWidget);
    expect(find.textContaining('Recebendo alertas pelo servidor a cada 1 s.'), findsOneWidget);
  });

  testWidgets('queda depois de conectar liga a reserva', (tester) async {
    await abrir(tester);
    expect(backend.openAlertsCalls, 1);

    feed.onConnectionChanged!(false);
    await avancar(tester, 2);

    expect(backend.openAlertsCalls, greaterThanOrEqualTo(3));
    expect(find.byKey(const Key('alert_fallback_status')), findsOneWidget);
  });

  testWidgets('ao armar, consulta na hora e não mostra a consulta de quando o MQTT estava em linha',
      (tester) async {
    final gate = Completer<void>();
    await abrir(tester);
    expect(backend.openAlertsCalls, 1, reason: 'a consulta da abertura, com o broker em linha');

    // A próxima consulta fica em voo: a linha tem de dizer "Consultando…",
    // não a hora da consulta de quando o tempo real ainda funcionava.
    backend.openAlertsGate = gate;
    feed.onConnectionChanged!(false);
    await tester.pump();

    expect(backend.openAlertsCalls, 2, reason: 'sem esperar um intervalo inteiro');
    expect(find.text('Consultando alertas pelo servidor…'), findsOneWidget);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Recebendo alertas pelo servidor'), findsOneWidget);
  });

  testWidgets('broker volta: o tique para', (tester) async {
    await abrir(tester);
    feed.onConnectionChanged!(false);
    await avancar(tester, 1);

    feed.onConnectionChanged!(true);
    await tester.pump();
    final chamadas = backend.openAlertsCalls;
    await avancar(tester, 3);

    expect(backend.openAlertsCalls, chamadas);
    expect(find.byKey(const Key('alert_fallback_status')), findsNothing);
  });

  testWidgets('MQTT e reserva entregam o mesmo alerta: um cartão', (tester) async {
    await abrir(tester, falhaDoFeed: _brokerFora);
    backend.openAlertsResult = [_aberto('mesmo')];
    await avancar(tester, 1);

    feed.deliver(testAlert(alertId: 'mesmo'));
    await tester.pump();

    expect(find.byKey(const Key('alert_mesmo')), findsOneWidget);
  });

  testWidgets('falha da consulta aparece na linha e não apaga a fila', (tester) async {
    await abrir(tester, falhaDoFeed: _brokerFora);
    backend.openAlertsResult = [_aberto('ja-na-fila')];
    await avancar(tester, 1);

    backend.openAlertsFailure = const BackendFailure('Sem conexão com o servidor.');
    await avancar(tester, 1);

    expect(find.textContaining('A consulta de alertas pelo servidor também falhou'), findsOneWidget);
    expect(find.byKey(const Key('alert_ja-na-fila')), findsOneWidget);
  });

  testWidgets('consulta em voo não se sobrepõe e não quebra no dispose', (tester) async {
    final gate = Completer<void>();
    backend
      ..openAlertsGate = gate
      // Não vazia: a fusão notificaria a fila já descartada.
      ..openAlertsResult = [_aberto('tarde-demais')];
    await abrir(tester, falhaDoFeed: _brokerFora);
    expect(backend.openAlertsCalls, 1);

    await avancar(tester, 3);
    expect(backend.openAlertsCalls, 1, reason: 'a primeira ainda está em voo');

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('em segundo plano não consulta; ao voltar consulta na hora', (tester) async {
    await abrir(tester, falhaDoFeed: _brokerFora);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final chamadas = backend.openAlertsCalls;

    await avancar(tester, 3);
    expect(backend.openAlertsCalls, chamadas);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.openAlertsCalls, chamadas + 1);
  });

  testWidgets('SessionExpired na reserva abre a reautenticação', (tester) async {
    await abrir(tester, falhaDoFeed: _brokerFora);
    backend.sessionExpired = true;

    await avancar(tester, 1);
    await assentar(tester);

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.text('Sua sessão expirou. Entre novamente com o código do autenticador.'), findsOneWidget);
  });
}
