import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_uploader.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar, irParaDaBarra, irParaDoMais;

/// Transporte falso de `telemetry.ingest`: recusa sessão de outro dono, como o
/// `BackendClient` (RNF06), e registra cada lote com a sessão em que subiu.
class _TransporteFalso implements TelemetryTransport {
  _TransporteFalso(this.backend);

  final FakeAcsBackend backend;
  bool semRede = false;
  final List<({String sessao, List<TelemetryEventRecord> eventos})> lotes = [];

  @override
  Future<TelemetryIngestAck> ingestTelemetry(
    List<TelemetryEventRecord> events, {
    required String expectedUserId,
  }) async {
    final sessao = backend.session?.userId;
    if (sessao != expectedUserId) throw const BackendFailure('Sessão de outro usuário.');
    if (semRede) throw const BackendFailure('Sem conexão com o servidor.');
    lotes.add((sessao: sessao!, eventos: List.of(events)));
    return TelemetryIngestAck(accepted: {for (final e in events) e.eventId}, rejected: const {});
  }

  Iterable<TelemetryEventRecord> get enviados => lotes.expand((l) => l.eventos);
}

/// Telemetria ligada no app (#83, Task 14): a fila do painel grava com o
/// `alertId` do cartão, e o envio dispara depois do sync e nos gatilhos do
/// envio diferido. Ids e pacientes sintéticos.
void main() {
  const acsA = '00000000-0000-4000-8000-0000000000a1';
  const acsB = '00000000-0000-4000-8000-0000000000b1';
  const alerta = '33333333-3333-4333-8333-333333333333';

  late InMemoryVisitStorage storage;
  late InMemoryTelemetryStore telemetria;
  late FakeAcsBackend backend;
  late _TransporteFalso transporte;
  late StreamController<bool> rede;
  late FakeAlertFeed feed;

  setUp(() {
    storage = InMemoryVisitStorage();
    telemetria = InMemoryTelemetryStore();
    backend = FakeAcsBackend()
      ..nextUserId = acsA
      ..patients = [
        MicroAreaPatient(
          patientId: syntheticPatientId(7),
          name: 'Beltrano Sintético',
          isChronic: false,
          chronicConditions: const [],
        ),
      ];
    transporte = _TransporteFalso(backend);
    rede = StreamController<bool>.broadcast();
  });

  tearDown(() => rede.close());

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      visitStorage: storage,
      telemetryStore: telemetria,
      telemetryTransport: transporte,
      connectivityChanges: rede.stream,
      biometricGate: FakeBiometricGate(),
      feedBuilder: (q) => feed = FakeAlertFeed(q),
    ));
    await assentar(tester);
  }

  Future<void> entrarComo(WidgetTester tester, String userId) async {
    backend.nextUserId = userId;
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    final botao = find.byKey(const Key('login_button'));
    await tester.ensureVisible(botao);
    await tester.pump();
    await tester.tap(botao);
    await assentar(tester);
    expect(find.text('Painel operacional'), findsOneWidget);
  }

  Future<void> tocar(WidgetTester tester, Key key) async {
    // O SnackBar da visita salva cobre o rodapé por 4 s.
    await tester.pump(const Duration(seconds: 5));
    await assentar(tester);
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await assentar(tester);
  }

  Future<void> visitaDeRotina(WidgetTester tester) async {
    await irParaDaBarra(tester, 'Visita');
    await tester.tap(find.text('Beltrano Sintético'));
    await assentar(tester);
    await tocar(tester, const Key('arrival_confirmation'));
    await tocar(tester, const Key('save_visit'));
  }

  Future<List<TelemetryEventRecord>> eventos(String dono, [String? nome]) async => [
        for (final e in await telemetria.oldestForOwner(dono, limit: 1000))
          if (nome == null || e.name == nome) e,
      ];

  testWidgets('visita salva pela tela de escalonamento leva o alertId do cartão', (tester) async {
    await abrirApp(tester);
    await entrarComo(tester, acsA);

    feed.deliver(testAlert(alertId: alerta, riskLevel: 'red'));
    await assentar(tester);
    await tester.tap(find.text('Acionar SAMU / Atender'));
    await assentar(tester);
    await tocar(tester, const Key('escalation_visit'));
    await tocar(tester, const Key('arrival_confirmation'));
    await tocar(tester, const Key('save_visit'));

    final registro = (await eventos(acsA, 'visit_registered')).single;
    expect(registro.payload['visit_type'], 'alert');
    expect(registro.payload['alert_id'], alerta);
    expect(registro.payload['patient_id'], seedPatientId);
  });

  testWidgets('visita de rotina pelo seletor não leva alertId', (tester) async {
    await abrirApp(tester);
    await entrarComo(tester, acsA);

    await visitaDeRotina(tester);

    final registro = (await eventos(acsA, 'visit_registered')).single;
    expect(registro.payload['visit_type'], 'routine');
    expect(registro.payload.containsKey('alert_id'), isFalse);
    expect(registro.payload['patient_id'], syntheticPatientId(7));
  });

  testWidgets('Sincronizar agora dispara o flush depois do sync', (tester) async {
    await abrirApp(tester);
    await entrarComo(tester, acsA);
    await visitaDeRotina(tester);
    expect(transporte.enviados.where((e) => e.name == 'sync_result'), isEmpty);

    await tocar(tester, const Key('sync_visits'));

    final nomes = transporte.enviados.map((e) => e.name).toList();
    expect(nomes, containsAll(['visit_registered', 'sync_attempt', 'sync_result']));
    expect(await eventos(acsA), isEmpty, reason: 'o aceito sai do aparelho');
    expect(transporte.lotes.every((l) => l.sessao == acsA), isTrue);
  });

  testWidgets('conexão que volta dispara o flush', (tester) async {
    await abrirApp(tester);
    await entrarComo(tester, acsA);
    transporte.semRede = true;
    await visitaDeRotina(tester);
    expect(await eventos(acsA, 'visit_registered'), hasLength(1));

    transporte.semRede = false;
    rede.add(false);
    await assentar(tester);
    expect(transporte.enviados, isEmpty, reason: 'sem rede não dispara');
    rede.add(true);
    await assentar(tester);

    expect(transporte.enviados.map((e) => e.name), contains('visit_registered'));
    expect(await eventos(acsA), isEmpty);
  });

  testWidgets('trocar de usuário não envia eventos do anterior', (tester) async {
    await abrirApp(tester);
    await entrarComo(tester, acsA);
    transporte.semRede = true;
    await visitaDeRotina(tester);
    final deA = {for (final e in await eventos(acsA)) e.eventId};
    expect(deA, isNotEmpty);

    // "Sair" de A sem rede: as visitas e os eventos de A ficam no aparelho.
    backend.syncFailure = const BackendFailure('Sem conexão com o servidor.');
    await irParaDoMais(tester, 'Preferências');
    await tocar(tester, const Key('logout_button'));
    await tester.tap(find.byKey(const Key('logout_confirm')));
    await assentar(tester);
    backend.syncFailure = null;
    transporte.semRede = false;

    await entrarComo(tester, acsB);
    await visitaDeRotina(tester);
    await tocar(tester, const Key('sync_visits'));
    for (final estado in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
        AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    rede.add(true);
    await assentar(tester);

    expect(transporte.lotes, isNotEmpty, reason: 'B envia os dele');
    for (final lote in transporte.lotes) {
      expect(lote.sessao, acsB);
      expect(lote.eventos.map((e) => e.owner).toSet(), {acsB});
    }
    expect(transporte.enviados.map((e) => e.eventId).toSet().intersection(deA), isEmpty);
    // Os de A (mais o attempt/result do sync sem rede do "Sair") esperam o
    // próximo login de A.
    expect({for (final e in await eventos(acsA)) e.eventId}, containsAll(deA),
        reason: 'os de A esperam o login de A');
  });
}
