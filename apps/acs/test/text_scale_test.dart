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
  // 360x800 é o aparelho comum; 320x640 é o piso de largura; 800x360 é a paisagem,
  // em que a altura útil encolhe justamente quando o cabeçalho cresce com a fonte.
  const janelas = {
    '360x800': Size(360, 800),
    '320x640': Size(320, 640),
    '800x360 (paisagem)': Size(800, 360),
  };
  for (final janela in janelas.entries) {
    for (final escala in const [1.3, 2.0]) {
      final rotulo = '${(escala * 100).toInt()}%';
      testWidgets('não estoura o layout com fonte a $rotulo em ${janela.key}', (tester) async {
        await abrirPainel(tester, tamanho: janela.value, escalaDeFonte: escala);
        await percorrerPainelInteiro(tester, 'fonte a $rotulo em ${janela.key}');
      });
    }
  }

  // Alcançar não é só existir na árvore: o botão que grava a visita precisa estar
  // habilitado, receber toque (nada o cobre, nem a barra de navegação) e manter
  // o alvo mínimo de 48 dp. Desabilitado não prova nada, daí a chegada confirmada.
  for (final janela in janelas.entries) {
    testWidgets('save_visit fica alcançável a 200% em ${janela.key}', (tester) async {
      // Alerta amarelo: o vermelho só oferece "Acionar SAMU", e a rota de visita
      // parte do cartão do alerta na Fila.
      final feed = await abrirPainel(tester, tamanho: janela.value, escalaDeFonte: 2.0);
      feed.deliver(testAlert(alertId: 'alerta-visita', riskLevel: 'yellow'));
      await assentar(tester);
      await irParaDaBarra(tester, 'Fila');
      final iniciar = find.text('Iniciar rota de visita');
      await rolarAte(tester, iniciar);
      await tester.tap(iniciar);
      await assentar(tester);
      final chegada = find.byKey(const Key('arrival_confirmation'));
      await rolarAte(tester, chegada);
      await tester.tap(chegada);
      await assentar(tester);

      final salvar = find.byKey(const Key('save_visit'));
      await rolarAte(tester, salvar);
      expect(tester.widget<FilledButton>(salvar).onPressed, isNotNull,
          reason: 'botão desabilitado não prova alcance');
      expect(salvar.hitTestable(), findsOneWidget);
      expect(tester.getSize(salvar).height, greaterThanOrEqualTo(48));
      esperarSemEstouro(tester, 'botão Salvar a 200% em ${janela.key}');
    });
  }

  // O chip de conexão corta o texto com elipse a 200% (`maxLines: 1`): o estado
  // continua legível pelo ícone e pela cor, e o nome acessível tem de seguir
  // inteiro para quem usa leitor de tela. WCAG 1.4.1 (não só cor) e 4.1.2.
  group('chip de conexão a 200% em 320x640', () {
    const tamanho = Size(320, 640);

    testWidgets('com a central conectada o rótulo semântico é completo', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        final feed = await abrirPainel(tester, tamanho: tamanho, escalaDeFonte: 2.0);
        feed.onConnectionChanged?.call(true);
        await assentar(tester);

        expect(tester.getSemantics(find.byKey(const Key('broker_status'))).label, contains('Alertas em tempo real'));
        esperarSemEstouro(tester, 'chip conectado a 200%');
      } finally {
        semantica.dispose();
      }
    });

    testWidgets('sem a central o rótulo semântico é completo', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        final feed = await abrirPainel(tester, tamanho: tamanho, escalaDeFonte: 2.0);
        feed.onConnectionChanged?.call(false);
        await assentar(tester);

        expect(tester.getSemantics(find.byKey(const Key('broker_status'))).label, contains('Sem central'));
        esperarSemEstouro(tester, 'chip sem central a 200%');
      } finally {
        semantica.dispose();
      }
    });

    testWidgets('na tela de login (sem estado) o rótulo semântico é "Offline ready"', (tester) async {
      final semantica = tester.ensureSemantics();
      try {
        redimensionar(tester, tamanho, escalaDeFonte: 2.0);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(SinalAcsApp(backend: FakeAcsBackend(), feedBuilder: (q) => FakeAlertFeed(q)));
        await assentar(tester);

        expect(tester.getSemantics(find.byKey(const Key('broker_status'))).label, contains('Offline ready'));
        esperarSemEstouro(tester, 'chip no login a 200%');
      } finally {
        semantica.dispose();
      }
    });
  });

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
