import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';

import 'support/layout_harness.dart';

/// Prova que as cinco telas cabem na janela, do celular ao desktop.
///
/// O backoffice nasceu desktop-first (`spec/PRD_system.md` §2.1) e até agora só
/// rodava em web; o único teste responsivo que existia checava qual barra de
/// navegação aparece, nada sobre o conteúdo. Ver `layout_harness.dart` para o
/// porquê de cada cuidado na detecção de estouro.
void main() {
  for (final (largura, altura) in const [(320.0, 640.0), (360.0, 800.0), (400.0, 800.0), (768.0, 1024.0), (1024.0, 768.0)]) {
    testWidgets('não estoura o layout em nenhuma das cinco telas a ${largura.toInt()}x${altura.toInt()}', (tester) async {
      await abrirBackoffice(tester, tamanho: Size(largura, altura));
      await percorrerBackofficeInteiro(tester, '${largura.toInt()}x${altura.toInt()}');
    });
  }

  testWidgets('não estoura o rail de navegação em paisagem de celular (800x360)', (tester) async {
    // 800dp de largura passa de AdminBreakpoints.rail, então o NavigationRail
    // entra — mas sobram ~288dp de altura depois do cabeçalho. `NavigationRail`
    // só rola com `scrollable: true`, que não é o default; com cinco destinos
    // rotulados (#42) o conteúdo já passa da altura e depende da rolagem — daí
    // também o caso seguinte, com fonte ampliada.
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

  for (final largura in const [320.0, 360.0]) {
    for (final escala in const [1.0, 1.3, 2.0]) {
      final rotulo = '${largura.toInt()}dp, fonte a ${(escala * 100).toInt()}%';
      testWidgets('os cinco destinos cabem na barra inferior em $rotulo, sem rótulo cortado', (tester) async {
        await abrirBackoffice(tester, tamanho: Size(largura, 640), escalaDeFonte: escala);

        final barra = find.byKey(const Key('admin_navigation_bar'));
        expect(barra, findsOneWidget);
        esperarCaberNaLargura(tester, barra, 'barra inferior em $rotulo');
        final caixaDaBarra = tester.getRect(barra);
        // Rótulos curtos na barra, com o nome completo no tooltip.
        expect(find.byTooltip('Pedidos do titular'), findsOneWidget);
        expect(find.byTooltip('Indicadores'), findsOneWidget);
        // Todos os rótulos, não só o novo: o Flutter não reporta como estouro
        // um rótulo cortado pela borda de baixo da barra.
        final rotulos = find.descendant(of: barra, matching: find.byType(Text));
        expect(rotulos, findsWidgets);
        for (final elemento in rotulos.evaluate()) {
          final caixa = tester.getRect(find.byElementPredicate((e) => e == elemento));
          final texto = (elemento.widget as Text).data;
          expect(caixa.left, greaterThanOrEqualTo(caixaDaBarra.left), reason: '$texto em $rotulo');
          expect(caixa.right, lessThanOrEqualTo(caixaDaBarra.right), reason: '$texto em $rotulo');
          expect(caixa.bottom, lessThanOrEqualTo(caixaDaBarra.bottom), reason: '$texto cortado abaixo da barra em $rotulo');
        }
        esperarSemEstouroDeLayout(tester, 'barra inferior em $rotulo');
      });
    }
  }
}
