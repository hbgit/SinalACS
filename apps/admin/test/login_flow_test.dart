import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';

void main() {
  testWidgets('deve autenticar e abrir o painel de indicadores', (tester) async {
    await tester.pumpWidget(SinalAdminApp());

    expect(find.byKey(const Key('dev_banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Painel de Indicadores'), findsOneWidget);
    expect(find.text('Vermelho'), findsOneWidget);
    expect(find.text('Amarelo'), findsOneWidget);
    expect(find.text('Verde'), findsOneWidget);
    expect(find.text('Abertos (pendentes)'), findsOneWidget);
  });

  testWidgets('deve expor rótulo semântico e alvo de toque acessível no login do admin', (tester) async {
    await tester.pumpWidget(SinalAdminApp());

    final loginButton = tester.widget<FilledButton>(find.byKey(const Key('login_button')));
    final minimumSize = loginButton.style?.minimumSize?.resolve({}) ?? const Size(0, 0);

    expect(find.bySemanticsLabel('Entrar no backoffice administrativo'), findsOneWidget);
    expect(minimumSize.height, greaterThanOrEqualTo(48));
    expect(minimumSize.width, greaterThanOrEqualTo(48));
  });
}
