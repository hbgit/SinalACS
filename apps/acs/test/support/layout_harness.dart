import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';

import 'fakes.dart';

/// Ferramentas para provar que as telas do ACS cabem na janela em que foram
/// postas. Mesmo método do `apps/admin/test/support/layout_harness.dart`, e as
/// mesmas três armadilhas — errar qualquer uma produz um teste que passa
/// sempre:
///
/// 1. `RenderFlex` só denuncia o estouro quando **pinta**; checar antes de
///    assentar os quadros não vê nada.
/// 2. Item de `ListView` fora da viewport não é construído e nunca reclama;
///    daí [percorrerTelaInteira].
/// 3. `takeException()` consome **uma** exceção por chamada; [esperarSemEstouro]
///    esvazia todas.
///
/// Uma quarta é só do ACS: `pumpAndSettle()` **nunca assenta** na aba Área, porque
/// o spinner do pull anima sem parar contra o fake. [assentar] alterna quadros
/// e tempo real, como o `settleRealAsync` de `login_flow_test.dart`.

const destinosDaBarra = ['Área', 'Fila', 'Mapa', 'Visita'];

/// Itens da folha "Mais", pelo rótulo que `_moreItem` mostra.
const itensDoMais = [
  'Acionamento',
  'Geofencing',
  'Avisos à comunidade',
  'Convidar paciente',
  'Preferências',
];

/// Troca o tamanho da janela de uma sessão já aberta. [tamanho] é em dp, porque
/// `devicePixelRatio` é forçado a 1.
void redimensionar(WidgetTester tester, Size tamanho, {double escalaDeFonte = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = tamanho;
  tester.platformDispatcher.textScaleFactorTestValue = escalaDeFonte;
}

Future<void> assentar(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump();
}

/// Falha se algum quadro pintado desde a última checagem reportou estouro.
void esperarSemEstouro(WidgetTester tester, String contexto) {
  final erros = <String>[];
  Object? erro;
  while ((erro = tester.takeException()) != null) {
    erros.add(erro.toString().split('\n').first);
  }
  expect(erros, isEmpty, reason: 'estouro de layout em $contexto: ${erros.join(' | ')}');
}

/// Abre o painel já logado (login pela tela, contra o `FakeAcsBackend`), numa
/// janela de tamanho e escala de fonte fixos. Confere a tela de login ANTES de
/// entrar: ela também tem cabeçalho.
///
/// Devolve o feed fake, para o teste entregar um alerta depois do login (o
/// alerta pré-inserido abaixo só aparece no mapa, não na lista da Fila).
Future<FakeAlertFeed> abrirPainel(
  WidgetTester tester, {
  required Size tamanho,
  double escalaDeFonte = 1.0,
  BiometricGate? biometricGate,
}) async {
  redimensionar(tester, tamanho, escalaDeFonte: escalaDeFonte);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final alerta = testAlert(alertId: 'escala-1', locationCell: testLocationCell);
  late FakeAlertFeed feed;
  await tester.pumpWidget(SinalAcsApp(
    backend: FakeAcsBackend(),
    biometricGate: biometricGate,
    feedBuilder: (queue) {
      queue.upsert(alerta); // `initialAlert` só seleciona; a tela lê a fila
      return feed = FakeAlertFeed(queue);
    },
  ));
  await tester.pump();
  esperarSemEstouro(tester, 'tela de login');

  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
  // No aparelho o `enterText` abre o teclado de verdade, e ele come ~300 dp da
  // janela: a medida de layout seria a de "com teclado". Larga o foco e espera
  // o sistema recolhê-lo (tempo real; na VM não há teclado e isso é só um quadro).
  FocusManager.instance.primaryFocus?.unfocus();
  await assentar(tester);
  final entrar = find.byKey(const Key('login_button'));
  await tester.ensureVisible(entrar); // numa janela baixa o botão fica abaixo da dobra
  // Em paisagem a rolagem ainda anima depois do primeiro quadro e o botão não
  // recebe toque nesse intervalo; a tela de login assenta (a aba Área é que não).
  await tester.pumpAndSettle();
  await tester.tap(entrar);
  await assentar(tester);
  return feed;
}

/// Rola a tela até o fim, checando estouro a cada passo.
Future<void> percorrerTelaInteira(WidgetTester tester, String contexto) async {
  esperarSemEstouro(tester, '$contexto (topo)');
  // `TextField` também tem um `Scrollable` (restorationId 'editable'), e `.last`
  // o escolhia nas abas com campo de texto: o arrasto caía fora da tela e a
  // rolagem não acontecia, esvaziando a varredura justo na aba Visita.
  final rolaveis = find.byWidgetPredicate((w) => w is Scrollable && w.restorationId != 'editable');
  if (rolaveis.evaluate().isEmpty) return; // ex.: o mapa não rola
  for (var passo = 1; passo <= 8; passo++) {
    await tester.drag(rolaveis.last, const Offset(0, -320));
    await assentar(tester);
    esperarSemEstouro(tester, '$contexto (rolagem $passo)');
  }
}

/// Rola a página até [alvo] existir e ficar visível. `ensureVisible` não serve
/// para item de lista preguiçosa: fora da viewport ele ainda não foi construído
/// e o finder não acha nada (`Bad state: No element`).
Future<void> rolarAte(WidgetTester tester, Finder alvo) async {
  final pagina = find.byWidgetPredicate((w) => w is Scrollable && w.restorationId != 'editable').first;
  await tester.scrollUntilVisible(alvo, 200, scrollable: pagina, maxScrolls: 60);
  await assentar(tester);
}

Future<void> irParaDaBarra(WidgetTester tester, String destino) async {
  final alvo = find.descendant(of: find.byType(NavigationBar), matching: find.text(destino));
  await tester.tap(alvo);
  await assentar(tester);
  esperarSemEstouro(tester, 'navegação para $destino');
}

Future<void> irParaDoMais(WidgetTester tester, String item) async {
  final mais = find.descendant(of: find.byType(NavigationBar), matching: find.text('Mais'));
  await tester.tap(mais);
  await assentar(tester);
  esperarSemEstouro(tester, 'folha "Mais"');
  final alvo = find.text(item);
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await assentar(tester);
  esperarSemEstouro(tester, 'navegação para $item');
}

/// Visita os quatro destinos da barra e os cinco itens de "Mais".
Future<void> percorrerPainelInteiro(WidgetTester tester, String contexto) async {
  for (final destino in destinosDaBarra) {
    await irParaDaBarra(tester, destino);
    await percorrerTelaInteira(tester, '$contexto / $destino');
  }
  for (final item in itensDoMais) {
    await irParaDoMais(tester, item);
    await percorrerTelaInteira(tester, '$contexto / $item');
  }
}
