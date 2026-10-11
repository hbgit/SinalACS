import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// WCAG 2.5.5, na régua de `spec/ux_accessibility_assessment.md`: 48dp.
///
/// Os apps ACS e paciente já fixam `minimumSize` nos botões; o backoffice
/// nunca precisou porque era só web com mouse. Em celular o default do
/// Material 3 para `OutlinedButton`/`TextButton` é 40dp de altura — abaixo do
/// mínimo. O tema do backoffice não define botão (`admin_theme.dart` não tem
/// `outlinedButtonTheme`/`filledButtonTheme`), então a correção é botão a botão,
/// como `login_screen.dart:184` já fazia.
///
/// A gestão de contas (#43) é o caso novo: a fileira de ações do cartão de ACS
/// e as ações do diálogo destrutivo declaram o próprio `minimumSize` e cada uma
/// tem o seu caso aqui.
///
/// Medido, e é por isso que cada botão é conferido em **duas** medidas:
/// `getSize` devolve o **alvo** (a caixa que recebe o toque), não a tinta. O
/// `AlertDialog` do Material 3 pinta ações de 40dp e o
/// `MaterialTapTargetSize.padded` do tema infla o alvo para 48 — com o
/// `minimumSize` removido o alvo continuava passando raspando, e só a medida da
/// tinta ([alturaPintada], o `Material` interno) denunciava o botão de 40dp. A
/// régua deste projeto é a altura pintada (é ela que
/// `spec/ux_accessibility_assessment.md` registra como "40dp de altura
/// visual"), então as duas valem: o alvo é o que a WCAG 2.5.5 pede e a tinta é
/// o que se vê e se acerta com o dedo.
void main() {
  const alturaMinima = 48.0;

  /// Traz [alvo] para dentro da janela antes de medir ou tocar.
  ///
  /// Não é zelo: a lista é preguiçosa e medir um widget que não foi construído
  /// lança em vez de medir, enquanto tocar num que está fora da viewport acerta
  /// o vazio sem lançar nada — o teste seguiria "passando" sem tocar no botão.
  Future<void> rolarAte(WidgetTester tester, Finder alvo) async {
    if (alvo.evaluate().isEmpty) {
      await tester.scrollUntilVisible(alvo, 320, scrollable: find.byType(Scrollable).last);
    }
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
  }

  Future<void> abrirMicroAreas(WidgetTester tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));
    await irPara(tester, 'Microáreas');
  }

  /// Altura da TINTA do botão — o `Material` que o `ButtonStyleButton` monta
  /// por dentro do `ConstrainedBox` das `minimumSize`.
  ///
  /// É a medida que pega a remoção do `minimumSize`: sem ela, o botão do
  /// `AlertDialog` volta a pintar 40dp enquanto o alvo segue com 48 — ver o
  /// cabeçalho.
  double alturaPintada(WidgetTester tester, Finder botao) =>
      tester.getSize(find.descendant(of: botao, matching: find.byType(Material)).first).height;

  /// Confere as duas medidas da WCAG 2.5.5 de um botão: alvo e tinta.
  void conferirAlvo(WidgetTester tester, Finder botao, String rotulo) {
    expect(tester.getSize(botao).height, greaterThanOrEqualTo(alturaMinima), reason: '$rotulo (alvo de toque)');
    expect(alturaPintada(tester, botao), greaterThanOrEqualTo(alturaMinima), reason: '$rotulo (altura pintada)');
  }

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

    await tester.pumpWidget(SinalAdminApp(auth: FakeAdminAuth()));
    await tester.pumpAndSettle();

    final botao = tester.getSize(find.byKey(const Key('login_button')));
    expect(botao.height, greaterThanOrEqualTo(alturaMinima));
  });

  testWidgets('os destinos da navegação inferior têm pelo menos 48dp de altura', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));

    final barra = tester.getSize(find.byKey(const Key('admin_navigation_bar')));
    expect(barra.height, greaterThanOrEqualTo(alturaMinima));
  });

  testWidgets('pedidos do titular: linha da fila, filtro, voltar e ações têm pelo menos 48dp', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(360, 800));
    await irPara(tester, 'Pedidos do titular');

    await rolarAtePedido(tester, find.byKey(const Key('data_request_req-a18f')));
    expect(tester.getSize(find.byKey(const Key('data_request_req-a18f'))).height, greaterThanOrEqualTo(alturaMinima));
    expect(tester.getSize(find.byKey(const Key('data_requests_status_filter'))).height, greaterThanOrEqualTo(alturaMinima));

    await abrirPedidoDoTitular(tester, 'req-a18f');
    for (final chave in const ['data_request_back', 'start_review_button', 'complete_button', 'reject_button']) {
      final alvo = find.byKey(Key(chave));
      await rolarAtePedido(tester, alvo);
      final tamanho = tester.getSize(alvo);
      expect(tamanho.height, greaterThanOrEqualTo(alturaMinima), reason: chave);
      expect(tamanho.width, greaterThanOrEqualTo(alturaMinima), reason: chave);
    }
  });
  testWidgets('o botão de cadastrar ACS tem pelo menos 48dp de altura', (tester) async {
    await abrirMicroAreas(tester);

    final botao = find.byKey(const Key('novo_acs'));
    await rolarAte(tester, botao);
    conferirAlvo(tester, botao, 'novo_acs');
  });

  testWidgets('as ações do cartão de ACS têm pelo menos 48dp de altura', (tester) async {
    await abrirMicroAreas(tester);

    // As quatro saem do mesmo `OutlinedButton.icon` com `minimumSize`; pinar
    // uma só deixaria as outras três regredirem em silêncio.
    for (final chave in const [
      'vincular_acs_acs-1',
      'redefinir_senha_acs-1',
      'redefinir_mfa_acs-1',
      'desativar_acs_acs-1',
    ]) {
      final botao = find.byKey(Key(chave));
      await rolarAte(tester, botao);
      conferirAlvo(tester, botao, chave);
    }
  });

  testWidgets('os botões do diálogo de confirmação têm pelo menos 48dp', (tester) async {
    await abrirMicroAreas(tester);

    final desativar = find.byKey(const Key('desativar_acs_acs-1'));
    await rolarAte(tester, desativar);
    await tester.tap(desativar);
    await tester.pumpAndSettle();

    // DENTRO do diálogo e não na tela de fundo: é aqui que o mínimo não vem de
    // graça — sem o `minimumSize` de `_ConfirmacaoDestrutiva._estilo` os dois
    // pintam 40dp e só o alvo do tema os segura em 48.
    conferirAlvo(tester, find.byKey(const Key('confirmar_acao')), 'confirmar_acao');
    conferirAlvo(tester, find.byKey(const Key('cancelar_acao')), 'cancelar_acao');
  });
}
