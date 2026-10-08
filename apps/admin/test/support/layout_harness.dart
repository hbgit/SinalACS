import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/data_requests_screen.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

import 'fake_admin_auth.dart';

/// Ferramentas para provar que uma tela cabe na janela em que foi posta.
///
/// Detectar estouro de layout em teste de widget tem três armadilhas, e errar
/// qualquer uma produz um teste que passa sempre — pior do que não ter teste:
///
/// 1. `RenderFlex` só denuncia o estouro quando **pinta** o listrado amarelo e
///    preto (`DebugOverflowIndicatorMixin.paintOverflowIndicator` chamando
///    `FlutterError.reportError`). Checar antes de `pumpAndSettle()` não vê
///    nada.
/// 2. Item de `ListView` fora da viewport não é construído, logo não pinta e
///    nunca reclama. Todas as telas do backoffice são `ListView` na raiz, então
///    checar só o primeiro frame cobre a primeira dobra e mais nada — daí
///    [percorrerTelaInteira].
/// 3. `takeException()` consome **uma** exceção por chamada. Duas telas
///    estourando com uma única checagem no fim reportariam uma só.

/// Nomes dos cinco destinos, na ordem de `AdminDestination`.
const destinosDoBackoffice = ['Indicadores', 'Microáreas', 'Alertas', 'Auditoria', 'Pedidos do titular'];

/// Abre o backoffice já logado, numa janela de tamanho e escala de fonte fixos.
///
/// [tamanho] é em pixels lógicos (dp) porque `devicePixelRatio` é forçado a 1.
Future<void> abrirBackoffice(
  WidgetTester tester, {
  required Size tamanho,
  double escalaDeFonte = 1.0,
  AdminDataSource? dataSource,
  AdminAuthBackend? auth,
}) async {
  redimensionar(tester, tamanho, escalaDeFonte: escalaDeFonte);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(SinalAdminApp(dataSource: dataSource, auth: auth ?? FakeAdminAuth()));

  // `ensureVisible` antes do tap não é zelo: numa janela baixa (celular em
  // paisagem, 360dp de altura) o botão fica abaixo da dobra e `tap` acerta o
  // vazio sem lançar nada — os testes seguiriam medindo a tela de login
  // achando que estavam no backoffice.
  await entrarComCredenciais(tester);
}

/// Preenche matrícula e senha e toca em Entrar (o login real não tem atalho).
///
/// O `ensureVisible` antes de cada toque vale para o botão e para os campos:
/// com fonte a 200% o formulário passa da dobra.
Future<void> entrarComCredenciais(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (final (chave, texto) in const [('matricula_field', 'ADM-001'), ('senha_field', 'senha-de-teste')]) {
    final campo = find.byKey(Key(chave));
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.enterText(campo, texto);
  }
  final entrar = find.byKey(const Key('login_button'));
  await tester.ensureVisible(entrar);
  await tester.pumpAndSettle();
  await tester.tap(entrar);
  await tester.pumpAndSettle();
}

/// Troca o tamanho da janela de uma sessão já aberta — usado para girar a tela.
void redimensionar(WidgetTester tester, Size tamanho, {double escalaDeFonte = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = tamanho;
  tester.platformDispatcher.textScaleFactorTestValue = escalaDeFonte;
}

/// Falha se o frame recém-pintado reportou estouro de layout.
///
/// Precisa vir depois de `pumpAndSettle()` — ver armadilha 1 no topo.
void esperarSemEstouroDeLayout(WidgetTester tester, String contexto) {
  final erro = tester.takeException();
  expect(erro, isNull, reason: 'estouro de layout em $contexto: $erro');
}

/// Rola a tela até o fim, checando estouro a cada passo.
///
/// Sem isso só a primeira dobra seria coberta — ver armadilha 2 no topo.
///
/// [lista] escolhe a rolagem da página quando a tela tem outra mais funda
/// (um `TextField` de várias linhas também é `Scrollable`).
Future<void> percorrerTelaInteira(WidgetTester tester, String contexto, {Finder? lista}) async {
  esperarSemEstouroDeLayout(tester, '$contexto (topo)');
  lista ??= find.byType(Scrollable).last;
  for (var passo = 1; passo <= 8; passo++) {
    await tester.drag(lista, const Offset(0, -320));
    await tester.pumpAndSettle();
    esperarSemEstouroDeLayout(tester, '$contexto (rolagem $passo)');
  }
}

/// Visita os cinco destinos, percorrendo cada um por inteiro.
Future<void> percorrerBackofficeInteiro(WidgetTester tester, String contexto) async {
  for (final destino in destinosDoBackoffice) {
    await irPara(tester, destino);
    await percorrerTelaInteira(tester, '$contexto / $destino');
  }
}

/// Na barra inferior "Pedidos do titular" aparece como "Pedidos", com o nome
/// completo no tooltip: o destino é achado pelo texto ou pelo tooltip.
Future<void> irPara(WidgetTester tester, String destino) async {
  final porTexto = find.text(destino);
  final alvo = porTexto.evaluate().isNotEmpty ? porTexto.last : find.byTooltip(destino).last;
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
  esperarSemEstouroDeLayout(tester, 'navegação para $destino');
}

/// Complemento de [esperarSemEstouroDeLayout] para o caso que ele não pega:
/// um widget mais largo que a janela sem `Flex` intermediário que reclame.
void esperarCaberNaLargura(WidgetTester tester, Finder alvo, String contexto) {
  final larguraDaJanela = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  expect(tester.getSize(alvo).width, lessThanOrEqualTo(larguraDaJanela), reason: contexto);
}

/// A rolagem da página de pedidos do titular (fila ou detalhe), e não a do
/// campo de resposta, que também é `Scrollable`.
Finder rolagemDosPedidos() =>
    find.descendant(of: find.byType(DataRequestsScreen), matching: find.byType(Scrollable)).first;

/// Rola a página de pedidos até [alvo] ser construído e ficar visível: item de
/// `ListView` abaixo da dobra ainda não existe, então `ensureVisible` sozinho
/// não o acha.
Future<void> rolarAtePedido(WidgetTester tester, Finder alvo) async {
  await tester.scrollUntilVisible(alvo, 120, scrollable: rolagemDosPedidos());
  await tester.pumpAndSettle();
}

/// Abre o detalhe de um pedido do titular a partir da fila (tela já aberta).
Future<void> abrirPedidoDoTitular(WidgetTester tester, String id) async {
  final linha = find.byKey(Key('data_request_$id'));
  await rolarAtePedido(tester, linha);
  await tester.tap(linha);
  await tester.pumpAndSettle();
}
