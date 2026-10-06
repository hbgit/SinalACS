import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/app/mfa_enrollment_screen.dart';

import 'support/fakes.dart';
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

  testWidgets('Preferências com "Sair e encerrar o turno" não estoura a 200% em 360x800', (tester) async {
    await abrirPainel(tester, tamanho: const Size(360, 800), escalaDeFonte: 2.0);
    await irParaDoMais(tester, 'Preferências');
    await percorrerTelaInteira(tester, 'Preferências a 200%');
    final sair = find.byKey(const Key('logout_button'));
    await tester.ensureVisible(sair);
    await assentar(tester);
    expect(sair.hitTestable(), findsOneWidget);
    esperarSemEstouro(tester, 'botão Sair a 200%');

    final limpar = find.byKey(const Key('wipe_button'));
    await tester.ensureVisible(limpar);
    await assentar(tester);
    expect(limpar.hitTestable(), findsOneWidget);
    expect(tester.getSize(limpar).height, greaterThanOrEqualTo(48));
    esperarSemEstouro(tester, 'botão Limpar este aparelho a 200%');
  });

  testWidgets('diálogos do "Sair" e do "Limpar este aparelho" não estouram a 200% em 360x800', (tester) async {
    await abrirPainel(tester, tamanho: const Size(360, 800), escalaDeFonte: 2.0);
    await irParaDoMais(tester, 'Preferências');

    final sair = find.byKey(const Key('logout_button'));
    await tester.ensureVisible(sair);
    await assentar(tester);
    await tester.tap(sair);
    await assentar(tester);
    expect(find.byKey(const Key('logout_confirm')), findsOneWidget);
    esperarSemEstouro(tester, 'diálogo do Sair a 200%');
    await tester.tap(find.text('Cancelar'));
    await assentar(tester);

    // Sem banco legível na VM, a conferência falha fechada: diálogo de bloqueio.
    final limpar = find.byKey(const Key('wipe_button'));
    await tester.ensureVisible(limpar);
    await assentar(tester);
    await tester.tap(limpar);
    await assentar(tester);
    expect(find.byKey(const Key('wipe_blocked')), findsOneWidget);
    esperarSemEstouro(tester, 'diálogo de bloqueio da limpeza a 200%');
  });

  // Telas novas da MFA: o campo de código no login e a ativação (QR + chave + campo).
  for (final escala in const [1.3, 2.0]) {
    final rotulo = '${(escala * 100).toInt()}%';

    testWidgets('login com o campo de código não estoura com fonte a $rotulo em 360x800', (tester) async {
      redimensionar(tester, const Size(360, 800), escalaDeFonte: escala);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = FakeAcsBackend()..expectedTotpCode = '123456';
      await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
      await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
      await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
      final entrar = find.byKey(const Key('login_button'));
      await tester.ensureVisible(entrar);
      await tester.pump();
      await tester.tap(entrar);
      await assentar(tester);

      expect(find.byKey(const Key('totp_field')), findsOneWidget);
      await percorrerTelaInteira(tester, 'login com código a $rotulo');
    });

    testWidgets('tela de ativação da MFA não estoura com fonte a $rotulo em 360x800', (tester) async {
      redimensionar(tester, const Size(360, 800), escalaDeFonte: escala);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        home: MfaEnrollmentScreen(backend: FakeAcsBackend(), matricula: 'ACS-001', senha: 'senha-sintetica'),
      ));
      await assentar(tester);

      expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
      await percorrerTelaInteira(tester, 'ativação da MFA a $rotulo');
    });
  }
}
