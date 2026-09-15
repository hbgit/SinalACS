
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_queue_factory.dart';
import 'package:sinalacs_client/sinalacs_client.dart'
    show MicroAreaPatient, SyncStatus, VisitSyncResult;

import 'support/fakes.dart';

void main() {
  group('login e painel', () {
    testWidgets('deve autenticar no backend e assinar o tópico da própria microárea', (tester) async {
      final backend = FakeAcsBackend();
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(backend.loginCount, 1);
      expect(find.text('Painel de Priorização'), findsOneWidget);
      // O tópico vem da microárea do token, não de constante no app.
      expect(feed.startedTopicMicroArea, seedMicroAreaId);
    });

    testWidgets('não deve abrir o painel quando a autenticação falha', (tester) async {
      final backend = FakeAcsBackend(
        loginFailure: const BackendFailure('Sem conexão com o servidor.'),
      );

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Painel de Priorização'), findsNothing);
      expect(find.byKey(const Key('login_error')), findsOneWidget);
    });

    testWidgets('deve barrar o acesso quando a sessão não tem microárea', (tester) async {
      // Sem território não há como filtrar a fila; abrir o painel assim
      // arriscaria mostrar alerta de outra microárea.
      final backend = FakeAcsBackend(microAreaId: null);

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Painel de Priorização'), findsNothing);
      expect(find.byKey(const Key('login_error')), findsOneWidget);
    });

    testWidgets('deve exibir o alerta que chega pelo broker e confirmar o recebimento', (tester) async {
      final backend = FakeAcsBackend();
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum alerta na sua microárea agora.'), findsOneWidget);

      feed.deliver(testAlert(alertId: 'alerta-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alert_alerta-1')), findsOneWidget);
      expect(find.text('Risco: Vermelho'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ack_alerta-1')));
      await tester.pumpAndSettle();

      expect(backend.acknowledgedAlertIds, ['alerta-1']);
      expect(find.text('Recebimento confirmado'), findsOneWidget);
    });

    testWidgets('o cartão de alerta é lido como uma frase única pelo leitor de tela', (tester) async {
      // Antes, um leitor de tela lia o cartão como quatro nós soltos
      // ("Paciente 3f2a..." / "Risco: Vermelho" / "Recebido às..." / botão),
      // sem ligar a informação entre si.
      final handle = tester.ensureSemantics();
      final backend = FakeAcsBackend();
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      feed.deliver(testAlert(alertId: 'alerta-frase'));
      await tester.pumpAndSettle();

      // Sem hora fixa no rótulo esperado: `_time` converte para o fuso local
      // da máquina que roda o teste, e o que importa aqui é que as quatro
      // informações — paciente, risco, confirmação e horário — cheguem como
      // UMA frase, não a hora exata.
      expect(
        find.bySemanticsLabel(RegExp(r'Paciente .*, Risco: Vermelho, recebido às \d{2}:\d{2}')),
        findsOneWidget,
      );
      // Os botões continuam como nós próprios, não somem dentro do bloco
      // mesclado.
      expect(find.bySemanticsLabel('Confirmar recebimento'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('deve avisar quando a central de alertas está inacessível', (tester) async {
      // Um ACS que não sabe que parou de receber alertas é o pior modo de falha
      // do produto: a falha precisa ser visível, não silenciosa.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue, failOnStart: true),
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feed_error')), findsOneWidget);
      // SC 4.1.3: o banner troca de estado sem tirar o foco de onde a
      // pessoa estava — só é percebido por um leitor de tela se a
      // `SemanticsNode` estiver marcada como região viva.
      final semantics = tester.getSemantics(find.byKey(const Key('feed_error')));
      expect(semantics.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('deve expor rótulo semântico e alvo de toque acessível no login do ACS', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));

      final loginButton = tester.widget<FilledButton>(find.byKey(const Key('login_button')));
      final minimumSize = loginButton.style?.minimumSize?.resolve({}) ?? const Size(0, 0);

      expect(find.bySemanticsLabel('Entrar no painel de priorização'), findsOneWidget);
      expect(minimumSize.height, greaterThanOrEqualTo(48));
      expect(minimumSize.width, greaterThanOrEqualTo(48));
    });

    testWidgets('a tela de login atende às diretrizes de contraste e alvo de toque do Flutter', (tester) async {
      // Substitui a auditoria manual no WebAIM/TalkBack do relatório anterior
      // por uma verificação determinística que o CI roda sozinho.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('não deve pré-preencher credenciais no formulário', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));

      expect(tester.widget<TextField>(find.byKey(const Key('matricula_field'))).controller?.text, isEmpty);
      expect(tester.widget<TextField>(find.byKey(const Key('senha_field'))).controller?.text, isEmpty);
    });
  });

  group('fila de priorização', () {
    test('deve ordenar por risco e, no mesmo risco, pelo mais antigo', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId);

      queue.upsert(testAlert(alertId: 'verde', riskLevel: 'green', triggeredAt: DateTime.utc(2026, 9, 11, 8)));
      queue.upsert(testAlert(alertId: 'vermelho-novo', triggeredAt: DateTime.utc(2026, 9, 11, 12)));
      queue.upsert(testAlert(alertId: 'amarelo', riskLevel: 'yellow', triggeredAt: DateTime.utc(2026, 9, 11, 9)));
      queue.upsert(testAlert(alertId: 'vermelho-antigo', triggeredAt: DateTime.utc(2026, 9, 11, 10)));

      expect(
        queue.alerts.map((alert) => alert.alertId).toList(),
        ['vermelho-antigo', 'vermelho-novo', 'amarelo', 'verde'],
      );
    });

    test('deve recusar alerta de outra microárea', () {
      // Territorialização é invariante: a ACL do broker já restringe, e esta é a
      // segunda barreira.
      final queue = AlertQueue(microAreaId: seedMicroAreaId);

      expect(queue.upsert(testAlert(alertId: 'de-fora', microAreaId: otherMicroAreaId)), isFalse);
      expect(queue.isEmpty, isTrue);
    });

    test('não deve duplicar o mesmo alerta reentregue pelo broker', () {
      // QoS 1 é at-least-once: a mesma mensagem pode chegar duas vezes.
      final queue = AlertQueue(microAreaId: seedMicroAreaId);

      queue.upsert(testAlert(alertId: 'alerta-1'));
      queue.upsert(testAlert(alertId: 'alerta-1'));

      expect(queue.alerts, hasLength(1));
    });

    test('reentrega não deve desfazer um alerta já confirmado', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId);

      queue.upsert(testAlert(alertId: 'alerta-1'));
      queue.markAcknowledged('alerta-1');
      queue.upsert(testAlert(alertId: 'alerta-1'));

      expect(queue.alerts.single.acknowledged, isTrue);
    });
  });

  group('fila offline de visitas', () {
    OfflineVisitRecord visit(String patientId) => OfflineVisitRecord(
          patientId: patientId,
          risk: 'red',
          status: 'PENDENTE',
        );

    test('deve enviar as visitas pendentes ao servidor e marcar como sincronizadas', () async {
      final sender = FakeVisitSynchronizer();
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(visit(seedPatientId));
      expect(queue.pendingCount, 1);

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.synced);
      expect(queue.pendingCount, 0);
      expect(queue.syncedCount, 1);
      expect(sender.batches.single, hasLength(1));
    });

    test('deve reencolar registros em conflito e reprocessar no retry', () async {
      var firstPass = true;
      final sender = FakeVisitSynchronizer(
        statusFor: (_) => firstPass ? 'conflict' : 'synced',
      );
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(visit(syntheticPatientId(2)));

      final conflict = await queue.sync();
      expect(conflict.kind, SyncOutcomeKind.conflict);
      // Conflito volta para a fila: precisa de resolução, não de descarte.
      expect(queue.pendingCount, 1);
      expect(queue.conflictCount, 1);

      firstPass = false;
      final retried = await queue.sync();
      expect(retried.kind, SyncOutcomeKind.synced);
      expect(queue.pendingCount, 0);
      expect(queue.syncedCount, 1);
    });

    test('deve manter a visita na fila quando a rede falha', () async {
      // Perder a visita por falha de rede é exatamente o que a fila existe para
      // evitar.
      final sender = FakeVisitSynchronizer(throwOnPush: true);
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(visit(syntheticPatientId(3)));
      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.error);
      expect(queue.pendingCount, 1);
      expect(queue.syncedCount, 0);
    });

    test('deve preservar observações no ciclo offline e ao sincronizar', () async {
      final sender = FakeVisitSynchronizer();
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(OfflineVisitRecord(
        patientId: seedPatientId,
        risk: 'yellow',
        status: 'PENDENTE',
        notes: 'Paciente com febre e náusea na última consulta.',
      ));

      expect(queue.pendingVisits.single.notes, contains('febre'));

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.synced);
      expect(sender.batches.single.single.notes, contains('febre'));
    });

    test('deve restaurar as visitas gravadas de uma execução anterior', () async {
      // Fechar o app não pode perder a fila.
      final store = InMemoryVisitStore();
      final first = OfflineVisitQueue(store: store);
      await first.add(visit(seedPatientId));

      final second = OfflineVisitQueue(store: store);
      await second.restore();

      expect(second.pendingCount, 1);
      expect(second.pendingVisits.single.patientId, seedPatientId);
    });

    test('erro por visita devolve o motivo e a visita permanece pendente', () async {
      // Antes o status 'error' caía no ramo default e a chamada devolvia
      // `synced`: a visita recusada ficava presa na fila para sempre, sem que
      // ninguém pudesse descobrir por quê.
      final sender = FakeVisitSynchronizer(
        statusFor: (_) => 'error',
        messageFor: (_) => 'identificadores devem ser UUID',
      );
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(visit(seedPatientId));
      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.error);
      expect(result.message, 'identificadores devem ser UUID');
      expect(queue.pendingCount, 1);
      expect(queue.syncedCount, 0);
    });

    test('conflito tem precedência sobre erro no mesmo lote', () async {
      // Conflito exige decisão de quem registrou; erro, no máximo, uma nova
      // tentativa. Quem chama precisa ver o que pede ação.
      final conflitante = visit(seedPatientId);
      final sender = FakeVisitSynchronizer(
        statusFor: (v) => v.localId == conflitante.localId ? 'conflict' : 'error',
      );
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(conflitante);
      await queue.add(visit(syntheticPatientId(2)));

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.conflict);
      // Nada saiu: as duas continuam no aparelho.
      expect(queue.pendingCount, 2);
    });

    test('visita recusada em definitivo sai da fila e não é reenviada', () async {
      // É o teste que reprova o comportamento antigo: `case 'error'`
      // reenfileirava incondicionalmente, então uma recusa territorial (que
      // nunca vai dar certo numa próxima tentativa) retentava para sempre.
      final sender = FakeVisitSynchronizer(
        statusFor: (_) => 'rejected',
        messageFor: (_) => 'paciente fora da sua microárea',
      );
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(visit(seedPatientId));
      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.rejected);
      expect(result.message, 'paciente fora da sua microárea');
      expect(queue.pendingCount, 0);
      expect(queue.rejectedCount, 1);
      expect(queue.rejectedVisits.single.rejectionReason, 'paciente fora da sua microárea');

      // Um segundo sync não reenvia a recusada: nada de novo sai pela rede.
      final secondSync = await queue.sync();
      expect(secondSync.kind, SyncOutcomeKind.empty);
      expect(sender.batches, hasLength(1));
    });

    test('recusa tem precedência sobre conflito no mesmo lote', () async {
      final rejeitada = visit(seedPatientId);
      final sender = FakeVisitSynchronizer(
        statusFor: (v) => v.localId == rejeitada.localId ? 'rejected' : 'conflict',
      );
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(rejeitada);
      await queue.add(visit(syntheticPatientId(2)));

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.rejected);
      expect(queue.rejectedCount, 1);
      // O conflito continua pendente para resolução — só a recusada saiu.
      expect(queue.pendingCount, 1);
      expect(queue.conflictCount, 1);
    });

    test('discardRejected esvazia as recusadas e persiste', () async {
      final sender = FakeVisitSynchronizer(statusFor: (_) => 'rejected');
      final store = InMemoryVisitStore();
      final queue = OfflineVisitQueue(store: store, synchronizer: sender);

      await queue.add(visit(seedPatientId));
      await queue.sync();
      expect(queue.rejectedCount, 1);

      await queue.discardRejected();
      expect(queue.rejectedCount, 0);

      // A fila nova, lendo do mesmo store, não vê a recusada: ela saiu do
      // disco quando foi descartada.
      final reloaded = OfflineVisitQueue(store: store);
      await reloaded.restore();
      expect(reloaded.rejectedCount, 0);
      expect(reloaded.pendingCount, 0);
    });

    test('não deve declarar sincronizado sem sincronizador configurado', () async {
      // O comportamento antigo carimbava 'SINCRONIZADO' sem nada sair do
      // dispositivo, o que escondia a ausência de integração.
      final queue = OfflineVisitQueue();
      await queue.add(visit(seedPatientId));

      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.error);
      expect(queue.syncedCount, 0);
      expect(queue.pendingCount, 1);
    });
  });

  group('registro de visita', () {
    testWidgets('deve enfileirar na MESMA fila do app, não em uma instância nova', (tester) async {
      // A tela antes fazia OfflineVisitQueue() a cada gravação, e a visita era
      // descartada no retorno do callback.
      final visitQueue = OfflineVisitQueue();
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      feed.deliver(testAlert(alertId: 'alerta-1', riskLevel: 'yellow'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar rota de visita'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();

      expect(visitQueue.pendingCount, 1);
    });

    testWidgets('deve enviar o UUID do alerta ao servidor, não o rótulo da tela', (tester) async {
      // O caminho inteiro: alerta pelo broker → gravação → visits.sync. Antes a
      // tela gravava 'Paciente 00000000' e descartava o UUID, então o servidor
      // recusaria a visita por identificador inválido.
      final backend = FakeAcsBackend();
      final visitQueue = OfflineVisitQueue(
        synchronizer: BackendVisitSynchronizer(backend: backend),
      );
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      feed.deliver(testAlert(alertId: 'alerta-1', riskLevel: 'yellow'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar rota de visita'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending_visits_count')), findsOneWidget);
      expect(find.text('Pendentes de sincronização: 1'), findsOneWidget);

      // O SnackBar de confirmação ocupa o rodapé por 4 s e o botão fica abaixo
      // da dobra nesta viewport: sem avançar o relógio e rolar, o toque bate no
      // SnackBar. `pumpAndSettle` sozinho não resolve — ele só roda enquanto há
      // quadros agendados, e um SnackBar parado não agenda nenhum.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('sync_visits')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_visits')));
      await tester.pumpAndSettle();

      expect(backend.syncedVisitBatches.single.single.patientId, seedPatientId);
      expect(visitQueue.pendingCount, 0);
      expect(find.text('Pendentes de sincronização: 0'), findsOneWidget);
    });

    testWidgets('deve exigir confirmação de chegada antes de salvar a visita', (tester) async {
      final visitQueue = OfflineVisitQueue();
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      feed.deliver(testAlert(alertId: 'alerta-chegada', riskLevel: 'yellow'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar rota de visita'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('arrival_confirmation')), findsOneWidget);
      final botao = tester.widget<FilledButton>(find.byKey(const Key('save_visit')));
      expect(botao.onPressed, isNull);
    });

    testWidgets('deve iniciar a rota de visita do alerta vermelho após o escalonamento', (tester) async {
      final alert = testAlert(alertId: 'alerta-vermelho-visita', riskLevel: 'red');
      PrioritizedAlert? selected;

      await tester.pumpWidget(MaterialApp(
        home: EscalationScreen(
          alert: alert,
          onVisit: (value) => selected = value,
        ),
      ));

      expect(find.text('Ligar para o SAMU (192)'), findsOneWidget);
      expect(find.text('Iniciar rota de visita'), findsOneWidget);
      expect(
        find.text('A visita é acompanhamento do caso e não substitui o acionamento do SAMU.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('escalation_visit')));

      expect(selected?.alertId, alert.alertId);
    });

    testWidgets('deve informar explicitamente quando o ACS alcançou o local do paciente', (tester) async {
      final visitQueue = OfflineVisitQueue();
      final alert = testAlert(alertId: 'alerta-geofence', riskLevel: 'yellow');
      final hash = alert.locationHash;
      final seed = hash.codeUnits.fold<int>(0, (sum, code) => sum + code) % 1000;
      final destination = LatLng(
        -15.7942 + ((seed % 7) * 0.0025),
        -47.8828 + (((seed ~/ 7) % 9) * 0.0035),
      );

      await tester.pumpWidget(MaterialApp(
        home: VisitRegistrationScreen(
          queue: visitQueue,
          alert: alert,
          currentPosition: destination,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Local alcançado. Você pode registrar a visita agora.'), findsOneWidget);
      expect(find.byKey(const Key('arrival_confirmation')), findsOneWidget);
    });

    testWidgets('sem alerta vinculado não deixa gravar', (tester) async {
      // `visits.sync` exige UUID de paciente: gravar aqui criaria um registro
      // que nunca sobe e, por isso, nunca sai do aparelho.
      final visitQueue = OfflineVisitQueue();

      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Visita'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_needs_alert')), findsOneWidget);
      final botao = tester.widget<FilledButton>(find.byKey(const Key('save_visit')));
      expect(botao.onPressed, isNull);
    });

    testWidgets('sem alerta, escolher um paciente da microárea libera o formulário', (tester) async {
      // Sem isto, o único jeito de chegar à tela de visita era um alerta — e o
      // backend só publica risco vermelho (emergência, SAMU). A visita de
      // rotina do PRD (≥ 8/dia por ACS) não tinha de onde partir.
      final backend = FakeAcsBackend()
        ..patients = [
          MicroAreaPatient(
            patientId: syntheticPatientId(5),
            name: 'Fulano de Tal',
            isChronic: true,
            chronicConditions: const ['hipertensão'],
          ),
          MicroAreaPatient(
            patientId: syntheticPatientId(6),
            name: 'Ciclana da Silva',
            isChronic: false,
            chronicConditions: const [],
          ),
        ];
      final visitQueue = OfflineVisitQueue();

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visita'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_picker')), findsOneWidget);
      expect(find.text('Fulano de Tal'), findsOneWidget);
      expect(find.text('Ciclana da Silva'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('save_visit'))).onPressed,
        isNull,
      );

      await tester.tap(find.text('Ciclana da Silva'));
      await tester.pumpAndSettle();

      // O rótulo da tela passa a ser o NOME — é exatamente o que
      // spec/lgpd_design.md:364 autoriza para a visita de rotina — mas o
      // seletor de pacientes some, porque a escolha já foi feita.
      expect(find.text('Ciclana da Silva'), findsOneWidget);
      expect(find.byKey(const Key('patient_picker')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('arrival_confirmation')));
      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save_visit')));
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();

      expect(visitQueue.pendingCount, 1);
    });

    testWidgets('falha ao carregar a lista de pacientes mostra o motivo e permite tentar de novo',
        (tester) async {
      final backend = FakeAcsBackend()
        ..listPatientsFailure = const BackendFailure('Sem conexão com o servidor.');
      final visitQueue = OfflineVisitQueue();

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visita'));
      await tester.pumpAndSettle();

      // Falha ao carregar a lista não pode travar a tela: o app é
      // offline-first, e o caminho por alerta continua funcionando mesmo sem
      // rede nenhuma.
      expect(find.byKey(const Key('patient_directory_error')), findsOneWidget);
      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);

      backend.listPatientsFailure = null;
      backend.patients = [
        MicroAreaPatient(
          patientId: syntheticPatientId(5),
          name: 'Fulano de Tal',
          isChronic: false,
          chronicConditions: const [],
        ),
      ];
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_picker')), findsOneWidget);
      expect(find.text('Fulano de Tal'), findsOneWidget);
    });

    testWidgets('a visita gravada pelo seletor carrega o UUID do paciente, nunca o nome', (tester) async {
      // Minimização (LGPD-RF01): o nome do seletor vive só em memória, para
      // render. O que sai para a fila — e para o servidor — é sempre o UUID.
      final backend = FakeAcsBackend()
        ..patients = [
          MicroAreaPatient(
            patientId: syntheticPatientId(7),
            name: 'Beltrano de Souza',
            isChronic: false,
            chronicConditions: const [],
          ),
        ];
      final visitQueue = OfflineVisitQueue();

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visita'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beltrano de Souza'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('arrival_confirmation')));
      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save_visit')));
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();

      expect(visitQueue.pendingCount, 1);
      expect(visitQueue.pendingVisits.single.patientId, syntheticPatientId(7));
      // A prova de minimização: o UUID vai para a fila, o nome nunca vai.
      expect(visitQueue.pendingVisits.single.patientId, isNot(contains('Beltrano')));
    });

    testWidgets('falha de rede mostra o motivo e mantém a visita no aparelho', (tester) async {
      final backend = FakeAcsBackend()
        ..syncFailure = const BackendFailure('Sem conexão com o servidor.');
      final visitQueue = OfflineVisitQueue(
        synchronizer: BackendVisitSynchronizer(backend: backend),
      );
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      feed.deliver(testAlert(alertId: 'alerta-1', riskLevel: 'yellow'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar rota de visita'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('sync_visits')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync_visits')));
      await tester.pumpAndSettle();

      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      expect(visitQueue.pendingCount, 1);
    });

    testWidgets('visita recusada mostra o motivo, some da fila e sai só com confirmação',
        (tester) async {
      final backend = FakeAcsBackend()
        ..syncResultFor = (entry) => VisitSyncResult(
              localId: entry.localId,
              syncStatus: SyncStatus.rejected,
              message: 'paciente fora da sua microárea',
            );
      final visitQueue = OfflineVisitQueue(
        synchronizer: BackendVisitSynchronizer(backend: backend),
      );
      late FakeAlertFeed feed;

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      feed.deliver(testAlert(alertId: 'alerta-1', riskLevel: 'yellow'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Iniciar rota de visita'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('sync_visits')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync_visits')));
      await tester.pumpAndSettle();

      // Saiu da retentativa: o contador de pendentes zera, e o botão de
      // sincronizar desabilita sozinho — sem isso o ACS ficaria tocando
      // "Sincronizar agora" para sempre, à toa.
      expect(find.text('Pendentes de sincronização: 0'), findsOneWidget);
      expect(visitQueue.pendingCount, 0);
      expect(visitQueue.rejectedCount, 1);
      await tester.ensureVisible(find.byKey(const Key('rejected_visits_count')));
      await tester.pumpAndSettle();
      expect(find.textContaining('paciente fora da sua microárea'), findsWidgets);

      final syncButton = tester.widget<OutlinedButton>(find.byKey(const Key('sync_visits')));
      expect(syncButton.onPressed, isNull);

      // Cancelar a confirmação não descarta nada.
      await tester.ensureVisible(find.byKey(const Key('discard_rejected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard_rejected')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(visitQueue.rejectedCount, 1);

      // Confirmar descarta — e some do aparelho para sempre.
      await tester.tap(find.byKey(const Key('discard_rejected')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      expect(visitQueue.rejectedCount, 0);
      expect(find.byKey(const Key('rejected_visits_count')), findsNothing);
    });
  });

  group('avisos de infraestrutura', () {
    /// Leva até o painel, com o feed e a fila que o teste quiser.
    Future<void> abrirPainel(
      WidgetTester tester, {
      required OfflineVisitQueue visitQueue,
      AlertFeed Function(AlertQueue queue)? feedBuilder,
    }) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: feedBuilder ?? (queue) => FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
    }

    testWidgets('os dois avisos coexistem quando broker e armazenamento caem juntos', (tester) async {
      // Em campo os dois caem juntos, e o `??` de antes mostrava só o do
      // broker: o ACS nunca descobria que as visitas do dia não eram salvas.
      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(store: FailingVisitStore()),
        feedBuilder: (queue) => FakeAlertFeed(queue, failOnStart: true),
      );

      expect(find.byKey(const Key('feed_error')), findsOneWidget);
      expect(find.byKey(const Key('storage_error')), findsOneWidget);
      // Cada um com o seu subtítulo: o texto sobre alertas era fixo e passava a
      // mentir quando o aviso exibido era o de disco. A falha é transitória
      // (StateError genérico), por isso o aviso de tentativa automática.
      expect(
        find.text('Novos alertas podem não estar chegando. Tentando reconectar automaticamente.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('só existe na memória'),
        findsOneWidget,
      );
    });

    testWidgets('o aviso de armazenamento aparece sozinho, com o feed saudável', (tester) async {
      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(store: FailingVisitStore()),
      );

      expect(find.byKey(const Key('feed_error')), findsNothing);
      expect(find.byKey(const Key('storage_error')), findsOneWidget);
    });

    testWidgets('o aviso de armazenamento acende depois de uma gravação que falha', (tester) async {
      // O banco abre e só falha ao gravar. Um campo calculado no initState
      // nunca veria isto — era o segundo defeito.
      final visitQueue = OfflineVisitQueue(
        store: FailingVisitStore(failOnLoad: false, failOnSave: true),
      );
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: visitQueue,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      );
      expect(find.byKey(const Key('storage_error')), findsNothing);

      feed.deliver(testAlert(alertId: 'alerta-1', riskLevel: 'yellow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iniciar rota de visita'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();

      // Na própria tela de visita, onde a pessoa acabou de gravar.
      expect(find.byKey(const Key('visit_storage_error')), findsOneWidget);
      expect(find.textContaining('(em memória)'), findsOneWidget);

      await tester.tap(find.text('Fila'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('storage_error')), findsOneWidget);
    });

    testWidgets('sem senha compilada o painel diz que falta a senha, não que falta conexão', (tester) async {
      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => FakeAlertFeed(
          queue,
          failure: const AlertFeedFailure(
            AlertFeedFailureKind.missingPassword,
            title: 'Este aplicativo foi compilado sem a senha do broker de alertas.',
            detail: 'Nenhum alerta será recebido até o aplicativo ser recompilado.',
          ),
        ),
      );

      expect(
        find.text('Este aplicativo foi compilado sem a senha do broker de alertas.'),
        findsOneWidget,
      );
      expect(find.text('Sem conexão com a central de alertas.'), findsNothing);
    });

    testWidgets('credencial recusada não vira "sem conexão"', (tester) async {
      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => FakeAlertFeed(
          queue,
          failure: const AlertFeedFailure(
            AlertFeedFailureKind.refused,
            title: 'A central recusou as credenciais deste aplicativo.',
            detail: 'Novos alertas não estão chegando.',
          ),
        ),
      );

      expect(find.text('A central recusou as credenciais deste aplicativo.'), findsOneWidget);
      expect(find.text('Sem conexão com a central de alertas.'), findsNothing);
    });
  });

  group('reconexão do feed', () {
    /// Leva até o painel, com o feed e a fila que o teste quiser.
    ///
    /// Cópia local de propósito: o helper do grupo `avisos de infraestrutura`
    /// é privado ao seu próprio corpo.
    Future<void> abrirPainel(
      WidgetTester tester, {
      required OfflineVisitQueue visitQueue,
      AlertFeed Function(AlertQueue queue)? feedBuilder,
    }) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: feedBuilder ?? (queue) => FakeAlertFeed(queue),
        visitQueue: visitQueue,
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
    }

    testWidgets('o painel volta a receber alertas quando a conexão dá certo na segunda tentativa', (tester) async {
      // O defeito literal: antes disto, uma falha na primeira conexão exigia
      // fechar e reabrir o app. O broker guarda os alertas com QoS 1 — basta
      // conectar para recebê-los.
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue, failuresBeforeSuccess: 1),
      );

      expect(feed.startCount, 1);
      expect(find.byKey(const Key('feed_error')), findsOneWidget);
      expect(find.text('Sem central'), findsOneWidget);

      // O atraso inicial do ReconnectSchedule é de 2s.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(feed.startCount, 2);
      expect(find.byKey(const Key('feed_error')), findsNothing);
      expect(find.text('Alertas em tempo real'), findsOneWidget);

      feed.deliver(testAlert(alertId: 'alerta-pos-reconexao'));
      await tester.pumpAndSettle();
      // A fila cresceu: o cartão de "nenhum alerta" precisa ter sumido.
      expect(find.text('Nenhum alerta na sua microárea agora.'), findsNothing);
    });

    testWidgets('o atraso entre tentativas dobra a cada falha', (tester) async {
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue, failOnStart: true),
      );
      expect(feed.startCount, 1);

      await tester.pump(const Duration(seconds: 2));
      expect(feed.startCount, 2, reason: 'primeiro atraso: 2s');

      await tester.pump(const Duration(seconds: 2));
      expect(feed.startCount, 2, reason: 'segundo atraso é 4s, ainda não decorreu');

      await tester.pump(const Duration(seconds: 2));
      expect(feed.startCount, 3, reason: 'agora os 4s completaram');
    });

    testWidgets('"Tentar agora" reconecta sem esperar o backoff', (tester) async {
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue, failuresBeforeSuccess: 1),
      );
      expect(feed.startCount, 1);

      await tester.tap(find.byKey(const Key('retry_feed')));
      await tester.pumpAndSettle();

      expect(feed.startCount, 2);
      expect(find.byKey(const Key('feed_error')), findsNothing);
      expect(find.text('Alertas em tempo real'), findsOneWidget);
    });

    testWidgets('falta de senha não oferece nem agenda nova tentativa', (tester) async {
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => feed = FakeAlertFeed(
          queue,
          failure: const AlertFeedFailure(
            AlertFeedFailureKind.missingPassword,
            title: 'Este aplicativo foi compilado sem a senha do broker de alertas.',
            detail: 'Nenhum alerta será recebido até o aplicativo ser recompilado.',
          ),
        ),
      );

      expect(find.byKey(const Key('retry_feed')), findsNothing);

      // Bem além de qualquer atraso possível (teto de 60s) — se algo estivesse
      // agendado, teria disparado.
      await tester.pump(const Duration(seconds: 70));
      expect(feed.startCount, 1);
    });

    testWidgets('voltar do segundo plano tenta reconectar na hora', (tester) async {
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue, failuresBeforeSuccess: 1),
      );
      expect(feed.startCount, 1);

      // Sem avançar o relógio: o sinal costuma voltar com a tela apagada, e o
      // ACS reabre o app já esperando o alerta.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(feed.startCount, 2);
      expect(find.byKey(const Key('feed_error')), findsNothing);
    });

    testWidgets('o cabeçalho para de dizer "em linha" quando a conexão cai depois de conectar', (tester) async {
      late FakeAlertFeed feed;

      await abrirPainel(
        tester,
        visitQueue: OfflineVisitQueue(),
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      );
      expect(find.text('Alertas em tempo real'), findsOneWidget);

      // Simula o autoReconnect do mqtt_client notificando uma queda depois de
      // já ter conectado — o caso que o campo escrito uma única vez não via.
      feed.onConnectionChanged?.call(false);
      await tester.pump();

      expect(find.text('Sem central'), findsOneWidget);
      // Nenhum banner novo: quem trata essa reconexão é o autoReconnect do
      // mqtt_client, não o shell.
      expect(find.byKey(const Key('feed_error')), findsNothing);
    });
  });

  group('fiação de produção', () {
    test('a fila do app sai com o sincronizador do backend ligado', () {
      // A regressão que motivou tudo: o app montava a fila sem sincronizador,
      // `sync()` devolvia erro, e nenhum teste podia ver — a UI só é testável
      // com a fila injetada, então a montagem real nunca era exercitada.
      final queue = buildVisitQueue(
        backend: FakeAcsBackend(),
        store: InMemoryVisitStore(),
      );

      expect(queue.synchronizer, isA<BackendVisitSynchronizer>());
    });
  });
}
