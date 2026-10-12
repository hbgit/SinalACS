import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/stale_badge.dart';

/// Selo de dado desatualizado (#44, Task 11; ADR "Intervalo e selo").
void main() {
  Future<void> montar(WidgetTester tester, {required DateTime ultimoSucesso, required DateTime agora}) =>
      tester.pumpWidget(MaterialApp(
        theme: buildAdminTheme(),
        home: Scaffold(body: StaleBadge(lastSuccess: ultimoSucesso, now: agora)),
      ));

  testWidgets('selo tem liveRegion e usa o token OnSurface', (tester) async {
    final handle = tester.ensureSemantics();
    await montar(
      tester,
      ultimoSucesso: DateTime(2026, 10, 11, 9, 0, 5),
      agora: DateTime(2026, 10, 11, 9, 2, 15),
    );

    const texto = 'Dados de 09:00:05 — sem atualização há 3 min';
    expect(find.text(texto), findsOneWidget);

    // Não depende só de cor: há ícone e texto.
    final icone = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('stale_badge')), matching: find.byType(Icon)));
    expect(icone.color, AdminColors.overdueOnSurface);
    final rotulo = tester.widget<Text>(find.text(texto));
    expect(rotulo.style?.color, AdminColors.overdueOnSurface);

    final semantica = tester.getSemantics(find.byKey(const Key('stale_badge')));
    expect(semantica.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('minutos arredondados para cima, no mínimo 1', (tester) async {
    final base = DateTime(2026, 10, 11, 14, 7, 9);
    await montar(tester, ultimoSucesso: base, agora: base.add(const Duration(seconds: 61)));
    expect(find.text('Dados de 14:07:09 — sem atualização há 2 min'), findsOneWidget);

    await montar(tester, ultimoSucesso: base, agora: base.add(const Duration(seconds: 120)));
    expect(find.text('Dados de 14:07:09 — sem atualização há 2 min'), findsOneWidget);

    await montar(tester, ultimoSucesso: base, agora: base.add(const Duration(seconds: 10)));
    expect(find.text('Dados de 14:07:09 — sem atualização há 1 min'), findsOneWidget);
  });
}
