import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(SinalAdminApp(auth: FakeAdminAuth()));
  await entrarComCredenciais(tester);
}

void main() {
  testWidgets('usa NavigationRail em telas largas (backoffice é desktop-first)', (tester) async {
    await _login(tester);

    expect(find.byKey(const Key('admin_navigation_rail')), findsOneWidget);
    expect(find.byKey(const Key('admin_navigation_bar')), findsNothing);
  });

  testWidgets('usa NavigationBar em telas estreitas', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    await _login(tester);

    expect(find.byKey(const Key('admin_navigation_bar')), findsOneWidget);
    expect(find.byKey(const Key('admin_navigation_rail')), findsNothing);
  });

  testWidgets('navega entre os cinco destinos do backoffice', (tester) async {
    await _login(tester);

    await tester.tap(find.text('Microáreas').last);
    await tester.pumpAndSettle();
    expect(find.text('Microáreas e vínculo ACS'), findsOneWidget);

    await tester.tap(find.text('Pedidos de contato').last);
    await tester.pumpAndSettle();
    expect(find.text('Pedidos de contato do grupo do piloto'), findsOneWidget);

    await tester.tap(find.text('Auditoria').last);
    await tester.pumpAndSettle();
    expect(find.text('Logs de auditoria'), findsOneWidget);

    await tester.tap(find.text('Pedidos do titular').last);
    await tester.pumpAndSettle();
    expect(find.text('Pedidos do titular (LGPD)'), findsOneWidget);
  });

  // C-06: o piloto não tem vínculo com unidade de saúde; nenhum destino do
  // backoffice mostra "UBS" (o modelo `ubs` só muda na C-06b).
  testWidgets('nenhum destino do backoffice mostra "UBS"', (tester) async {
    await _login(tester);

    expect(find.text('Contadores do grupo do piloto'), findsOneWidget);
    expect(find.textContaining('UBS'), findsNothing, reason: 'Indicadores');
    for (final destino in ['Microáreas', 'Pedidos de contato', 'Auditoria', 'Pedidos do titular', 'Avisos']) {
      await tester.tap(find.text(destino).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('UBS'), findsNothing, reason: destino);
    }
  });

  // #167: o pedido do participante (P-09) é "pedido de contato" também para a
  // coordenação; Painel e lista não o chamam de alerta nem de vermelho.
  testWidgets('Painel e Pedidos de contato não mostram "alerta" nem "vermelho"', (tester) async {
    await _login(tester);
    final proibido = RegExp('[Aa]lerta|[Vv]ermelh');

    expect(find.text('Pedido de contato'), findsOneWidget, reason: 'cartão do Painel');
    expect(find.text('Situação dos pedidos de contato'), findsOneWidget);
    expect(find.textContaining(proibido), findsNothing, reason: 'Indicadores');

    await tester.tap(find.text('Pedidos de contato').last);
    await tester.pumpAndSettle();
    expect(find.text('Pedidos de contato do grupo do piloto'), findsOneWidget);
    expect(find.textContaining('Tipo: Pedido de contato', skipOffstage: false), findsWidgets);
    expect(find.textContaining('Risco: Vermelho', skipOffstage: false), findsNothing);
    expect(find.textContaining(proibido, skipOffstage: false), findsNothing, reason: 'lista');
  });
}
