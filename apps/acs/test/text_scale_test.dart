import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// WCAG 1.4.4 (RNF05): o conteúdo precisa sobreviver a 200% de escala de texto.
///
/// O caminho é o layout aguentar, e não `MediaQuery.withClampedTextScaling`:
/// limitar a escala resolve o estouro desobedecendo à preferência de
/// acessibilidade de quem precisa dela.
void main() {
  for (final escala in const [1.3, 2.0]) {
    testWidgets('não estoura o layout com fonte a ${(escala * 100).toInt()}% em 360x800', (tester) async {
      await abrirPainel(tester, tamanho: const Size(360, 800), escalaDeFonte: escala);
      await percorrerPainelInteiro(tester, 'fonte a ${(escala * 100).toInt()}%');
    });
  }

  testWidgets('o cabeçalho cresce quando a escala muda em tempo de execução', (tester) async {
    // No Android a preferência de tamanho de fonte muda em Configurações, com o
    // app já aberto em segundo plano: o cabeçalho tem de acompanhar.
    await abrirPainel(tester, tamanho: const Size(360, 800));
    final alturaPadrao = tester.getSize(find.byType(AppBar)).height;

    redimensionar(tester, const Size(360, 800), escalaDeFonte: 2.0);
    await assentar(tester);
    final alturaAmpliada = tester.getSize(find.byType(AppBar)).height;

    expect(alturaAmpliada, greaterThan(alturaPadrao));
    esperarSemEstouro(tester, 'cabeçalho com fonte a 200%');
  });
}
