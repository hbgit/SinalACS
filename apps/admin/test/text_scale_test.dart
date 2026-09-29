import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// WCAG 1.4.4 exige que o conteúdo sobreviva a 200% de escala de texto.
///
/// O caminho é o layout aguentar, e não `MediaQuery.withClampedTextScaling`:
/// limitar a escala resolve o estouro desobedecendo à preferência de acessi-
/// bilidade de quem precisa dela.
void main() {
  for (final escala in const [1.3, 2.0]) {
    testWidgets('não estoura o layout com fonte a ${(escala * 100).toInt()}% em 360x800', (tester) async {
      await abrirBackoffice(tester, tamanho: const Size(360, 800), escalaDeFonte: escala);
      await percorrerBackofficeInteiro(tester, 'fonte a ${(escala * 100).toInt()}%');
    });
  }

  testWidgets('o cabeçalho cresce quando a escala de fonte aumenta em tempo de execução', (tester) async {
    // Mudar a escala com o app aberto é o caso real: no Android a preferência
    // de tamanho de fonte muda em Configurações, com o app já em segundo plano.
    await abrirBackoffice(tester, tamanho: const Size(360, 800));
    final alturaPadrao = tester.getSize(find.byType(AppBar)).height;

    redimensionar(tester, const Size(360, 800), escalaDeFonte: 2.0);
    await tester.pumpAndSettle();
    final alturaAmpliada = tester.getSize(find.byType(AppBar)).height;

    expect(alturaAmpliada, greaterThan(alturaPadrao));
    esperarSemEstouroDeLayout(tester, 'cabeçalho com fonte a 200%');
  });
}
