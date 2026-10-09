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

  testWidgets('percorrerTelaInteira falha quando a tela não acaba dentro do teto de passos', (tester) async {
    // O outro jeito de o harness ficar cego: a tela cresce, o teto de rolagem
    // não, e o rodapé deixa de ser checado sem nada ficar vermelho. A tela aqui
    // é de propósito mais longa que `tetoDeRolagem` arrastos de 320dp.
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [for (var i = 0; i < 100; i++) const SizedBox(height: 200, child: Text('item'))],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // `try`/`catch` e não `expectLater(..., throwsA(...))`: a falha do harness
    // chega depois de trinta `pumpAndSettle`, e o `expectLater` de um Future
    // assim deixa o `TestFailure` escapar para o tratador de erro do teste
    // ("depois que o teste terminou") em vez de o capturar.
    Object? erro;
    try {
      await percorrerTelaInteira(tester, 'lista mais longa que o teto');
    } catch (e) {
      erro = e;
    }
    expect(erro, isA<TestFailure>(), reason: 'o teto de rolagem tem de falhar alto, não voltar em silêncio');
    expect('$erro', contains('tetoDeRolagem'), reason: 'a falha precisa dizer que o teto de rolagem acabou');
  });
}
