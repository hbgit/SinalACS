import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(SinalAdminApp());
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
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

  testWidgets('navega entre os quatro destinos do backoffice', (tester) async {
    await _login(tester);

    await tester.tap(find.text('Microáreas').last);
    await tester.pumpAndSettle();
    expect(find.text('Microáreas e vínculo ACS'), findsOneWidget);

    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();
    expect(find.text('Alertas da UBS'), findsOneWidget);

    await tester.tap(find.text('Auditoria').last);
    await tester.pumpAndSettle();
    expect(find.text('Logs de auditoria'), findsOneWidget);
  });
}
