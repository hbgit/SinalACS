import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

import 'support/fakes.dart';

/// Parte visível do reforço (#44) no cartão do painel.
void main() {
  Future<void> pintar(WidgetTester tester, AlertQueue queue) => tester.pumpWidget(MaterialApp(
        theme: buildAcsDarkTheme(),
        home: Scaffold(body: DashboardScreen(queue: queue)),
      ));

  testWidgets('cartão de reforço mostra rótulo, ícone e frase de leitor de tela', (tester) async {
    final handle = tester.ensureSemantics();
    final queue = AlertQueue(microAreaId: seedMicroAreaId)
      ..upsert(testAlert(alertId: 'normal', triggeredAt: DateTime.utc(2026, 9, 11, 8)))
      ..upsert(testAlert(alertId: 'reforcado', triggeredAt: DateTime.utc(2026, 9, 11, 9), escalated: true));
    await pintar(tester, queue);

    expect(find.byKey(const Key('escalated_reforcado')), findsOneWidget);
    expect(find.byKey(const Key('escalated_normal')), findsNothing);
    expect(find.text('Reforço da coordenação'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('alert_reforcado')), matching: find.byIcon(Icons.campaign)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('alert_normal')), matching: find.byIcon(Icons.campaign)), findsNothing);

    // Frase única do cartão: só o reforçado a traz.
    expect(find.bySemanticsLabel(RegExp('reforço da coordenação')), findsOneWidget);

    // Texto no token *OnSurface do risco (vermelho), não no preenchimento.
    final texto = tester.widget<Text>(find.byKey(const Key('escalated_reforcado')));
    expect(texto.style?.color, AcsRiskColors.dark.redOnSurface);
    handle.dispose();
  });

  testWidgets('cartão reforçado já confirmado não quebra e segue confirmado', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId)
      ..upsert(testAlert(alertId: 'a1', escalated: true))
      ..markAcknowledged('a1');
    await pintar(tester, queue);

    expect(find.text('Recebimento confirmado'), findsOneWidget);
    expect(find.byKey(const Key('ack_a1')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
