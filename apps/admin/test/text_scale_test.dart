import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';

import 'support/fake_admin_auth.dart';
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

  for (final largura in const [360.0, 320.0]) {
    testWidgets('detalhe de pedido do titular não estoura com fonte a 200% em ${largura.toInt()}dp', (tester) async {
      await abrirBackoffice(tester, tamanho: Size(largura, 800), escalaDeFonte: 2.0);
      await irPara(tester, 'Pedidos do titular');
      await abrirPedidoDoTitular(tester, 'req-a18f');
      await percorrerTelaInteira(tester, 'detalhe do pedido (${largura.toInt()}dp, 200%)', lista: rolagemDosPedidos());
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

  // O login ganhou o campo do código e há a tela de ativação do MFA: as duas
  // têm de caber a 130%/200% de fonte e em 320dp de largura (WCAG 1.4.4/1.4.10).
  for (final largura in const [360.0, 320.0]) {
    for (final escala in const [1.3, 2.0]) {
      final rotulo = '${largura.toInt()}dp, fonte a ${(escala * 100).toInt()}%';

      testWidgets('login com campo do código não estoura em $rotulo', (tester) async {
        redimensionar(tester, Size(largura, 800), escalaDeFonte: escala);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final auth = FakeAdminAuth()..requiresTotp = true;
        await tester.pumpWidget(SinalAdminApp(auth: auth));
        await tester.pumpAndSettle();
        await percorrerTelaInteira(tester, 'login ($rotulo)');
        // Primeira tentativa sem código: o campo do código aparece.
        await entrarComCredenciais(tester);
        expect(find.byKey(const Key('totp_field')), findsOneWidget);
        await percorrerTelaInteira(tester, 'login com código ($rotulo)');
      });

      testWidgets('ativação do MFA não estoura em $rotulo', (tester) async {
        redimensionar(tester, Size(largura, 800), escalaDeFonte: escala);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final auth = FakeAdminAuth()..failWith = const AdminMfaEnrollmentRequired();
        await tester.pumpWidget(SinalAdminApp(auth: auth));
        await entrarComCredenciais(tester);
        expect(find.byKey(const Key('activation_code_field')), findsOneWidget);
        await percorrerTelaInteira(tester, 'código de ativação ($rotulo)');
        await tester.enterText(find.byKey(const Key('activation_code_field')), 'ABCD-EFGH');
        await tester.ensureVisible(find.byKey(const Key('activation_continue')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('activation_continue')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
        await percorrerTelaInteira(tester, 'ativação ($rotulo)');
      });
    }
  }
}
