import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// Prova que o detector de estouro do harness realmente detecta.
///
/// Sem este teste, um harness cego — checando antes da pintura, ou esquecendo
/// de chamar `takeException` — faria toda a suíte responsiva passar em verde
/// sem verificar nada, que é a falha mais cara possível aqui: ela não parece
/// uma falha.
void main() {
  testWidgets('esperarSemEstouroDeLayout falha diante de um estouro proposital', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(200, 400);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [SizedBox(width: 500, height: 20)])),
    ));
    await tester.pumpAndSettle();

    expect(
      () => esperarSemEstouroDeLayout(tester, 'estouro proposital'),
      throwsA(isA<TestFailure>()),
    );
  });
}
