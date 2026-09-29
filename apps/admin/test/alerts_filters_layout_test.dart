import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// Os dois filtros de Alertas ficavam sempre lado a lado.
///
/// Em 360dp cada `Expanded` recebia ~170dp: o rótulo do campo e o valor
/// selecionado disputavam o mesmo espaço e "Microárea 12 — Zona Rural" virava
/// reticências quase inteiras. `isExpanded` e `TextOverflow.ellipsis`
/// impediam o estouro, então nenhum teste de overflow pegaria isto — é um
/// defeito de legibilidade, e precisa da sua própria asserção.
void main() {
  Offset posicaoDe(WidgetTester tester, String chave) => tester.getTopLeft(find.byKey(Key(chave)));

  testWidgets('empilha os filtros de microárea e status abaixo de 480dp', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));
    await irPara(tester, 'Alertas');

    final microArea = posicaoDe(tester, 'alerts_micro_area_filter');
    final status = posicaoDe(tester, 'alerts_status_filter');

    expect(status.dy, greaterThan(microArea.dy), reason: 'o filtro de status deveria estar abaixo, não ao lado');
    expect(status.dx, equals(microArea.dx), reason: 'empilhados, os dois começam na mesma margem');
  });

  testWidgets('mantém os filtros lado a lado no layout largo', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 768));
    await irPara(tester, 'Alertas');

    final microArea = posicaoDe(tester, 'alerts_micro_area_filter');
    final status = posicaoDe(tester, 'alerts_status_filter');

    expect(status.dy, equals(microArea.dy));
    expect(status.dx, greaterThan(microArea.dx));
  });
}
