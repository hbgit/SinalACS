import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';

import 'support/layout_harness.dart';

/// Prova que as quatro telas cabem na janela, do celular ao desktop.
///
/// O backoffice nasceu desktop-first (`spec/PRD_system.md` §2.1) e até agora só
/// rodava em web; o único teste responsivo que existia checava qual barra de
/// navegação aparece, nada sobre o conteúdo. Ver `layout_harness.dart` para o
/// porquê de cada cuidado na detecção de estouro.
void main() {
  for (final (largura, altura) in const [(360.0, 800.0), (400.0, 800.0), (768.0, 1024.0), (1024.0, 768.0)]) {
    testWidgets('não estoura o layout em nenhuma das quatro telas a ${largura.toInt()}x${altura.toInt()}', (tester) async {
      await abrirBackoffice(tester, tamanho: Size(largura, altura));
      await percorrerBackofficeInteiro(tester, '${largura.toInt()}x${altura.toInt()}');
    });
  }

  testWidgets('não estoura o rail de navegação em paisagem de celular (800x360)', (tester) async {
    // 800dp de largura passa de AdminBreakpoints.rail, então o NavigationRail
    // entra — mas sobram ~288dp de altura depois do cabeçalho. `NavigationRail`
    // só rola com `scrollable: true`, que não é o default; com os quatro
    // destinos atuais o conteúdo cabe por poucos pixels. É uma folga que some
    // ao acrescentar um quinto destino — daí o caso seguinte, com fonte
    // ampliada, que é onde a margem acaba de verdade.
    await abrirBackoffice(tester, tamanho: const Size(800, 360));

    expect(find.byKey(const Key('admin_navigation_rail')), findsOneWidget);
    await percorrerBackofficeInteiro(tester, 'paisagem de celular');
  });

  testWidgets('não estoura o rail em paisagem de celular com fonte a 150%', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(800, 360), escalaDeFonte: 1.5);

    expect(find.byKey(const Key('admin_navigation_rail')), findsOneWidget);
    await percorrerBackofficeInteiro(tester, 'paisagem de celular com fonte a 150%');
  });

  testWidgets('mantém o NavigationRail no tablet em 1280x800 (desktop-first preservado)', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1280, 800));

    expect(find.byKey(const Key('admin_navigation_rail')), findsOneWidget);
    expect(find.byKey(const Key('admin_navigation_bar')), findsNothing);
    await percorrerBackofficeInteiro(tester, 'tablet 1280x800');
  });

  testWidgets('troca para NavigationBar exatamente no ponto de quebra declarado', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(AdminBreakpoints.rail, 800));
    expect(find.byKey(const Key('admin_navigation_rail')), findsOneWidget);

    redimensionar(tester, const Size(AdminBreakpoints.rail - 1, 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_navigation_bar')), findsOneWidget);
  });
}
