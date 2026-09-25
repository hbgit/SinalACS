import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';

void main() {
  group('login de desenvolvimento não pode funcionar fora de dev (achado da revisão do PR)', () {
    testWidgets('com devLoginEnabled: false, o botão fica desabilitado e não navega', (tester) async {
      await tester.pumpWidget(SinalAdminApp(devLoginEnabled: false));

      final loginButton = tester.widget<FilledButton>(find.byKey(const Key('login_button')));
      expect(loginButton.onPressed, isNull);
      expect(find.byKey(const Key('dev_login_disabled_notice')), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_button')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Painel de Indicadores'), findsNothing);
    });

    testWidgets('com devLoginEnabled: true, o botão funciona normalmente', (tester) async {
      await tester.pumpWidget(SinalAdminApp(devLoginEnabled: true));

      expect(find.byKey(const Key('dev_login_disabled_notice')), findsNothing);

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Painel de Indicadores'), findsOneWidget);
    });
  });
}
