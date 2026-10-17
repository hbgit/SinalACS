import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/app/app_lock_gate.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/security/upload_token_store.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/remote_wipe.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';
import 'support/layout_harness.dart';

/// Armazenamento em memória que conta as destruições do banco (o apagador
/// real chama `destroyAll` uma vez por limpeza).
class _CountingStorage implements VisitStorage {
  final InMemoryVisitStorage inner = InMemoryVisitStorage();
  int destroyCalls = 0;

  @override
  VisitStore forOwner(String ownerId) => inner.forOwner(ownerId);

  @override
  LegacyVisitStore get legacy => inner.legacy;

  @override
  Future<Map<String, int>> countsByOwner() => inner.countsByOwner();

  @override
  Future<void> wipeAllData() => inner.wipeAllData();

  @override
  Future<void> destroyAll() async {
    destroyCalls++;
    await inner.destroyAll();
  }
}

/// Limpeza remota no app (#81, Task 5): partida, retomada, volta da rede e
/// renovação levam à mesma tela `device_wiped`, fora do bloqueio. Ids
/// sintéticos.
void main() {
  const idAntigo = '00000000-0000-4000-8000-0000000000d1';
  const ordem = 'ordem-1';

  late FakeAcsBackend backend;
  late MemoryDeviceIdStore deviceIds;
  late MemoryWipeJournal journal;
  late MemoryUploadTokenStore tokens;
  late _CountingStorage storage;
  late StreamController<bool> rede;
  late List<FakeAlertFeed> feeds;

  setUp(() {
    deviceIds = MemoryDeviceIdStore(idAntigo);
    backend = FakeAcsBackend()..deviceIds = deviceIds;
    journal = MemoryWipeJournal();
    tokens = MemoryUploadTokenStore({'acs-que-saiu': 'upload-sintetico'});
    storage = _CountingStorage();
    rede = StreamController<bool>.broadcast();
    feeds = <FakeAlertFeed>[];
  });

  tearDown(() => rede.close());

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      visitStorage: storage,
      uploadTokens: tokens,
      deviceIds: deviceIds,
      wipeJournal: journal,
      connectivityChanges: rede.stream,
      biometricGate: FakeBiometricGate(),
      feedBuilder: (AlertQueue q) {
        final feed = FakeAlertFeed(q);
        feeds.add(feed);
        return feed;
      },
    ));
    await assentar(tester);
  }

  Future<void> entrar(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    final botao = find.byKey(const Key('login_button'));
    await tester.ensureVisible(botao);
    await tester.pump();
    await tester.tap(botao);
    await assentar(tester);
    expect(find.text('Painel operacional'), findsOneWidget);
  }

  void esperarTelaDeLimpeza() {
    expect(find.byKey(const Key('device_wiped')), findsOneWidget);
    expect(find.text('Aparelho limpo pela coordenação'), findsOneWidget);
    expect(
      find.text('Os dados do SinalACS deste aparelho foram apagados a pedido da coordenação da UBS, '
          'inclusive as visitas que ainda não tinham sido enviadas. Os alertas continuam com a equipe da UBS.'),
      findsOneWidget,
    );
    expect(find.text('Painel operacional'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    // Fora do bloqueio por inatividade.
    expect(find.byType(AppLockGate), findsNothing);
  }

  testWidgets('pedido na partida apaga antes do login e mostra device_wiped', (tester) async {
    backend.pendingWipeOrderId = ordem;
    backend.storedRefreshToken = 'refresh-sintetico';

    await abrirApp(tester);

    esperarTelaDeLimpeza();
    expect(backend.resumeCount, 0, reason: 'a tela de login não chegou a retomar a sessão');
    expect(storage.destroyCalls, 1);
    expect(backend.forgetLocalSessionCount, 1);
    expect(await tokens.owners(), isEmpty);
    expect(await deviceIds.readOrCreate(), isNot(idAntigo));
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: ordem)]);
    expect(await journal.read(), isNull);
    expect(find.byKey(const Key('device_wiped_pending_confirm')), findsNothing);
    // INV-03 e sem revogar o que o servidor já revogou.
    expect(backend.acknowledgedAlertIds, isEmpty);
    expect(backend.resolvedAlertIds, isEmpty);
    expect(backend.revokedUploadTokens, isEmpty);
  });

  testWidgets('diário em erasing termina a limpeza na partida e mostra device_wiped', (tester) async {
    await journal.write(ordem, idAntigo, WipePhase.erasing);
    backend.storedRefreshToken = 'refresh-sintetico';

    await abrirApp(tester);

    esperarTelaDeLimpeza();
    expect(backend.resumeCount, 0);
    expect(storage.destroyCalls, 1);
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: ordem)]);
  });

  testWidgets('wipe remoto com painel aberto desmonta o painel e mostra device_wiped', (tester) async {
    backend.patients = [
      MicroAreaPatient(patientId: syntheticPatientId(5), name: 'Paciente Sintético', isChronic: false, chronicConditions: const []),
    ];
    await abrirApp(tester);
    await entrar(tester);
    await irParaDaBarra(tester, 'Visita');
    await tester.ensureVisible(find.byKey(const Key('patient_search')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('patient_search')), 'busca sintetica');
    await tester.pump();
    final feed = feeds.single;
    expect(feed.stopped, isFalse);

    backend.pendingWipeOrderId = ordem;
    // A sequência completa (o campo de texto aberto escuta o ciclo e recusa
    // pular estados): segundo plano e volta.
    for (final estado in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    await assentar(tester);

    esperarTelaDeLimpeza();
    expect(tester.takeException(), isNull);
    expect(feed.stopped, isTrue, reason: 'o feed de alertas fecha com o painel');
    expect(storage.destroyCalls, 1);
    expect(await storage.inner.forOwner(seedAcsId).load(), isEmpty, reason: 'a fila em RAM é descartada sem gravar');
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: ordem)]);
    expect(backend.acknowledgedAlertIds, isEmpty);
    expect(backend.resolvedAlertIds, isEmpty);

    // O painel não volta a rodar nada depois de desmontado.
    final consultas = backend.openAlertsCalls;
    await tester.pump(const Duration(minutes: 10));
    await assentar(tester);
    expect(backend.openAlertsCalls, consultas);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renovação com pedido leva à mesma tela, sem tela de reautenticação', (tester) async {
    await abrirApp(tester);
    await entrar(tester);

    // O `BackendClient` real faz isto quando a renovação recebe
    // `DeviceWipeRequiredException`: avisa o coordenador e lança.
    backend.openAlertsFailure = const DeviceWipeRequiredFailure(ordem);
    backend.onDeviceWipeRequired!(ordem);
    await assentar(tester);

    esperarTelaDeLimpeza();
    expect(tester.takeException(), isNull);
    expect(storage.destroyCalls, 1);
    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: ordem)]);
  });

  testWidgets('Entrar de novo abre login com deviceId novo', (tester) async {
    backend.pendingWipeOrderId = ordem;
    await abrirApp(tester);
    esperarTelaDeLimpeza();
    backend.pendingWipeOrderId = null; // o id novo não tem pedido

    final botao = find.byKey(const Key('device_wiped_login'));
    expect(find.descendant(of: botao, matching: find.text('Entrar de novo')), findsOneWidget);
    await tester.ensureVisible(botao);
    await tester.tap(botao);
    await assentar(tester);

    expect(find.byKey(const Key('device_wiped')), findsNothing);
    expect(find.byType(AppLockGate), findsOneWidget, reason: 'o bloqueio volta a valer');
    await entrar(tester);
    expect(backend.loginDeviceIds, hasLength(1));
    expect(backend.loginDeviceIds.single, isNot(idAntigo));
    expect(storage.destroyCalls, 1);
  });

  testWidgets('conexão que volta pergunta pendingWipe', (tester) async {
    await abrirApp(tester);
    final antes = backend.pendingWipeQueries.length;
    expect(antes, 1, reason: 'a partida pergunta uma vez');

    rede.add(false);
    await assentar(tester);
    expect(backend.pendingWipeQueries.length, antes);

    backend.pendingWipeOrderId = ordem;
    rede.add(true);
    await assentar(tester);

    expect(backend.pendingWipeQueries.length, antes + 1);
    esperarTelaDeLimpeza();
  });

  testWidgets('confirmação sem rede mostra a linha pendente, reenviada quando a conexão volta', (tester) async {
    backend.pendingWipeOrderId = ordem;
    backend.confirmWipeFailure = const BackendFailure('Sem conexão com o servidor.');

    await abrirApp(tester);

    esperarTelaDeLimpeza();
    expect(
      find.text('A confirmação ainda não chegou ao servidor; será enviada quando houver conexão.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('device_wiped_pending_confirm')), findsOneWidget);
    expect((await journal.read())?.phase, WipePhase.erased);

    backend.confirmWipeFailure = null;
    backend.pendingWipeOrderId = null;
    rede.add(false);
    rede.add(true);
    await assentar(tester);

    expect(backend.confirmedWipes, [(deviceId: idAntigo, orderId: ordem)]);
    expect(await journal.read(), isNull);
    expect(find.byKey(const Key('device_wiped_pending_confirm')), findsNothing);
    expect(storage.destroyCalls, 1, reason: 'reenviar a confirmação não apaga de novo');
  });

  testWidgets('fonte 200% em 320x640 sem estouro na device_wiped', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    redimensionar(tester, const Size(320, 640), escalaDeFonte: 2.0);
    backend.pendingWipeOrderId = ordem;
    backend.confirmWipeFailure = const BackendFailure('Sem conexão com o servidor.');

    await abrirApp(tester);

    esperarTelaDeLimpeza();
    expect(find.byKey(const Key('device_wiped_pending_confirm')), findsOneWidget);
    esperarSemEstouro(tester, 'device_wiped a 200%');
    final alvo = tester.getSize(find.byKey(const Key('device_wiped_login')));
    expect(alvo.height, greaterThanOrEqualTo(52));
    expect(alvo.width, greaterThanOrEqualTo(48));
  });
}
