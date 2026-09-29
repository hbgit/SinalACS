import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';
import 'support/layout_harness.dart';

/// WCAG 2.5.5, na régua de `spec/ux_accessibility_assessment.md`: 48dp.
///
/// Os apps ACS e paciente já fixam `minimumSize` nos botões; o backoffice
/// nunca precisou porque era só web com mouse. Em celular o default do
/// Material 3 para `OutlinedButton`/`TextButton` é 40dp de altura — abaixo do
/// mínimo. A correção mora no tema, não no widget, senão o próximo botão
/// adicionado nasce fora da régua de novo.
void main() {
  const alturaMinima = 48.0;

  testWidgets('o botão de tentar novamente tem pelo menos 48dp de altura', (tester) async {
    final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())..failNextIndicators = true;

    await abrirBackoffice(tester, tamanho: const Size(360, 800), dataSource: dataSource);

    expect(find.text('Tentar novamente'), findsOneWidget);
    final botao = tester.getSize(find.widgetWithText(OutlinedButton, 'Tentar novamente'));
    expect(botao.height, greaterThanOrEqualTo(alturaMinima));
  });

  testWidgets('o botão de entrar tem pelo menos 48dp de altura', (tester) async {
    redimensionar(tester, const Size(360, 800));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(SinalAdminApp(devLoginEnabled: true));
    await tester.pumpAndSettle();

    final botao = tester.getSize(find.byKey(const Key('login_button')));
    expect(botao.height, greaterThanOrEqualTo(alturaMinima));
  });

  testWidgets('os destinos da navegação inferior têm pelo menos 48dp de altura', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));

    final barra = tester.getSize(find.byKey(const Key('admin_navigation_bar')));
    expect(barra.height, greaterThanOrEqualTo(alturaMinima));
  });
}
