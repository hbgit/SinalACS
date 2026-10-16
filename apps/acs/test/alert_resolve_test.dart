import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

import 'support/fakes.dart';

/// Mesmo caminho de `entrar` em `login_flow_test.dart` (não importável entre
/// arquivos de teste). Credenciais sintéticas.
Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
}

/// "Concluir atendimento" (#76): a ação do ACS que faz o paciente ver
/// "Atendido".
void main() {
  group('AlertQueue.markResolved', () {
    test('marca concluído, implica confirmado e desce abaixo dos confirmados', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'a', triggeredAt: DateTime.utc(2026, 10, 16, 8)))
        ..upsert(testAlert(alertId: 'b', triggeredAt: DateTime.utc(2026, 10, 16, 9)))
        ..markAcknowledged('a')
        ..markAcknowledged('b');

      expect(queue.markResolved('a'), isTrue);

      expect(queue.alerts.map((x) => x.alertId), ['b', 'a']);
      expect(queue.alerts.last.resolved, isTrue);
      expect(queue.alerts.last.acknowledged, isTrue);
      expect(queue.unacknowledgedCount, 0);
    });

    test('alerta fora da fila devolve false', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId);
      expect(queue.markResolved('nao-existe'), isFalse);
    });

    test('reentrega de um alerta concluído não o reabre', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'a'))
        ..markAcknowledged('a')
        ..markResolved('a');

      expect(queue.upsert(testAlert(alertId: 'a')), isFalse);
      expect(queue.upsert(testAlert(alertId: 'a', escalated: true)), isFalse);
      expect(queue.alerts.single.resolved, isTrue);
    });
  });

  group('cartão do alerta', () {
    Future<void> pintar(WidgetTester tester, AlertQueue queue, {void Function(PrioritizedAlert)? onResolve}) =>
        tester.pumpWidget(MaterialApp(
          theme: buildAcsDarkTheme(),
          home: Scaffold(body: DashboardScreen(queue: queue, onResolve: onResolve)),
        ));

    testWidgets('só o alerta confirmado oferece "Concluir atendimento"', (tester) async {
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'novo'))
        ..upsert(testAlert(alertId: 'visto'))
        ..markAcknowledged('visto');
      await pintar(tester, queue, onResolve: (_) {});

      expect(find.byKey(const Key('resolve_novo')), findsNothing);
      expect(find.byKey(const Key('resolve_visto')), findsOneWidget);
      final altura = tester.getSize(find.byKey(const Key('resolve_visto'))).height;
      expect(altura, greaterThanOrEqualTo(48));
    });

    testWidgets('concluído mostra rótulo e ícone, sem botões de ação', (tester) async {
      final handle = tester.ensureSemantics();
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'a1'))
        ..markAcknowledged('a1')
        ..markResolved('a1');
      await pintar(tester, queue, onResolve: (_) {});

      expect(find.byKey(const Key('resolved_a1')), findsOneWidget);
      expect(find.byKey(const Key('resolve_a1')), findsNothing);
      expect(find.byKey(const Key('ack_a1')), findsNothing);
      expect(find.text('Acionar SAMU / Atender'), findsNothing);
      expect(find.text('Iniciar rota de visita'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('atendimento concluído')), findsOneWidget);
      final texto = tester.widget<Text>(find.byKey(const Key('resolved_a1')));
      expect(texto.style?.color, AcsRiskColors.dark.greenOnSurface);
      handle.dispose();
    });
  });

  group('fluxo no painel', () {
    Future<FakeAlertFeed> abrirComAlertaConfirmado(WidgetTester tester, FakeAcsBackend backend) async {
      late FakeAlertFeed feed;
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      ));
      await entrar(tester);
      await tester.pumpAndSettle();
      feed.deliver(testAlert(alertId: 'alerta-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ack_alerta-1')));
      await tester.pumpAndSettle();
      return feed;
    }

    testWidgets('confirma no diálogo, chama o servidor e marca concluído', (tester) async {
      final backend = FakeAcsBackend();
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      expect(find.text('Concluir o atendimento?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmar_conclusao')));
      await tester.pumpAndSettle();

      expect(backend.resolvedAlertIds, ['alerta-1']);
      expect(find.byKey(const Key('resolved_alerta-1')), findsOneWidget);
      expect(find.text('Atendimento concluído. O paciente já vê "Atendido".'), findsOneWidget);
    });

    testWidgets('cancelar o diálogo não chama o servidor', (tester) async {
      final backend = FakeAcsBackend();
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelar_conclusao')));
      await tester.pumpAndSettle();

      expect(backend.resolvedAlertIds, isEmpty);
      expect(find.byKey(const Key('resolve_alerta-1')), findsOneWidget);
    });

    testWidgets('recusa do servidor aparece e o alerta segue por concluir', (tester) async {
      final backend = FakeAcsBackend()
        ..resolveFailure = const BackendFailure(
          'Confirme o recebimento antes de concluir o atendimento.',
          isRecoverable: false,
        );
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_conclusao')));
      await tester.pumpAndSettle();

      expect(find.text('Confirme o recebimento antes de concluir o atendimento.'), findsOneWidget);
      expect(find.byKey(const Key('resolve_alerta-1')), findsOneWidget);
      expect(find.byKey(const Key('resolved_alerta-1')), findsNothing);
    });

    testWidgets('alerta que a central não encontra não é marcado concluído', (tester) async {
      final backend = FakeAcsBackend()..resolved = false;
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_conclusao')));
      await tester.pumpAndSettle();

      expect(find.text('A central não reconheceu este alerta.'), findsOneWidget);
      expect(find.byKey(const Key('resolved_alerta-1')), findsNothing);
    });
  });
}
