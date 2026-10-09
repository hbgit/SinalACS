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
/// mínimo. A correção mora no tema, não no widget, senão o próximo botão
/// adicionado nasce fora da régua de novo.
///
/// A gestão de contas (#43) é o caso novo: a fileira de ações do cartão de ACS
/// e as ações do diálogo destrutivo são as primeiras telas cujos botões não
/// herdam o mínimo do tema, então cada um declara o próprio `minimumSize` e cada
/// um tem o seu caso aqui.
///
/// Medido: `getSize` devolve o **alvo** (a caixa que recebe o toque), não a
/// tinta. O `AlertDialog` do Material 3 pinta ações de 40dp e o
/// `MaterialTapTargetSize.padded` do tema infla o alvo para 48 — ou seja, sem
/// `minimumSize` algum o alvo ainda passaria raspando e o botão visível ficaria
/// abaixo da régua. Quem medir a tinta um dia (o `Material` interno, 40dp) é
/// quem pega a remoção do `minimumSize`; aqui se prende o que a WCAG 2.5.5
/// pede, e é um `materialTapTargetSize: shrinkWrap` no tema que derruba isto.
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

  testWidgets('o botão de cadastrar ACS tem pelo menos 48dp de altura', (tester) async {
    await abrirMicroAreas(tester);

    final botao = find.byKey(const Key('novo_acs'));
    await rolarAte(tester, botao);
    expect(tester.getSize(botao).height, greaterThanOrEqualTo(alturaMinima));
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
      expect(tester.getSize(botao).height, greaterThanOrEqualTo(alturaMinima), reason: chave);
    }
  });

  testWidgets('os botões do diálogo de confirmação têm pelo menos 48dp', (tester) async {
    await abrirMicroAreas(tester);

    final desativar = find.byKey(const Key('desativar_acs_acs-1'));
    await rolarAte(tester, desativar);
    await tester.tap(desativar);
    await tester.pumpAndSettle();

    // DENTRO do diálogo e não na tela de fundo — ver o cabeçalho para o que
    // exatamente estes 48dp prendem (o alvo, que é o que a WCAG 2.5.5 mede).
    expect(tester.getSize(find.byKey(const Key('confirmar_acao'))).height, greaterThanOrEqualTo(alturaMinima));
    expect(tester.getSize(find.byKey(const Key('cancelar_acao'))).height, greaterThanOrEqualTo(alturaMinima));
  });
}
