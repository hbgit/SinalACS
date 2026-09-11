import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

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

    testWidgets('deve avisar quando a central de alertas está inacessível', (tester) async {
      // Um ACS que não sabe que parou de receber alertas é o pior modo de falha
      // do produto: a falha precisa ser visível, não silenciosa.
      await tester.pumpWidget(SinalAcsApp(
        backend: FakeAcsBackend(),
        feedBuilder: (queue) => FakeAlertFeed(queue, failOnStart: true),
      ));

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feed_error')), findsOneWidget);
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
    OfflineVisitRecord visit(String name) => OfflineVisitRecord(
          patientName: name,
          risk: 'red',
          status: 'PENDENTE',
        );

    test('deve enviar as visitas pendentes ao servidor e marcar como sincronizadas', () async {
      final sender = FakeVisitSynchronizer();
      final queue = OfflineVisitQueue(synchronizer: sender);

      await queue.add(visit('Maria Souza'));
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

      await queue.add(visit('João Souza'));

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

      await queue.add(visit('Ana Costa'));
      final result = await queue.sync();

      expect(result.kind, SyncOutcomeKind.error);
      expect(queue.pendingCount, 1);
      expect(queue.syncedCount, 0);
    });

    test('deve restaurar as visitas gravadas de uma execução anterior', () async {
      // Fechar o app não pode perder a fila.
      final store = InMemoryVisitStore();
      final first = OfflineVisitQueue(store: store);
      await first.add(visit('Maria Souza'));

      final second = OfflineVisitQueue(store: store);
      await second.restore();

      expect(second.pendingCount, 1);
      expect(second.pendingVisits.single.patientName, 'Maria Souza');
    });

    test('não deve declarar sincronizado sem sincronizador configurado', () async {
      // O comportamento antigo carimbava 'SINCRONIZADO' sem nada sair do
      // dispositivo, o que escondia a ausência de integração.
      final queue = OfflineVisitQueue();
      await queue.add(visit('Maria Souza'));

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

      await tester.tap(find.byKey(const Key('save_visit')));
      await tester.pumpAndSettle();

      expect(visitQueue.pendingCount, 1);
    });
  });
}
