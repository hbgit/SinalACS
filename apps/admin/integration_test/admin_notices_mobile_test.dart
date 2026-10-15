import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';

import '../test/support/fake_admin_auth.dart';
import '../test/support/layout_harness.dart' show entrarComCredenciais;

/// Avisos e Termos no runtime real do Android (Issue #46).
///
/// **Hermético**: roda sobre o `MockAdminDataSource`, sem `docker compose`,
/// seed nem `--dart-define`:
///
///     flutter test integration_test/admin_notices_mobile_test.dart -d emulator-5554
///
/// Nenhum texto jurídico real: tudo é `[TEXTO PLACEHOLDER]`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> entrar(WidgetTester tester, {String role = 'admin'}) async {
    await tester.pumpWidget(SinalAdminApp(auth: FakeAdminAuth()..role = role));
    await tester.pumpAndSettle();
    await entrarComCredenciais(tester);
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  Future<void> abrirAvisos(WidgetTester tester) async {
    final porTexto = find.text('Avisos');
    await tocar(tester, porTexto.evaluate().isNotEmpty ? porTexto.last : find.byTooltip('Avisos').last);
    expect(find.text('Avisos às comunidades'), findsOneWidget);
  }

  testWidgets('admin agenda e cancela um aviso e publica uma versão dos termos', (tester) async {
    await entrar(tester);
    await abrirAvisos(tester);

    await tocar(tester, find.byKey(const Key('notice_new_button')));
    await tester.enterText(find.byKey(const Key('notice_title')), 'Aviso de teste');
    await tester.enterText(find.byKey(const Key('notice_message')), '[TEXTO PLACEHOLDER]');
    await tocar(tester, find.byKey(const Key('notice_area')));
    await tocar(tester, find.byType(DropdownMenuItem<String>).last);
    await tocar(tester, find.byKey(const Key('notice_submit')));

    expect(find.text('Aviso de teste'), findsOneWidget);
    expect(find.text('Agendado'), findsOneWidget);

    final cancelar = find.byWidgetPredicate((w) => w.key is Key && (w.key as Key).toString().contains('notice_cancel_') && !(w.key as Key).toString().contains('confirm'));
    await tocar(tester, cancelar.first);
    await tocar(tester, find.byKey(const Key('notice_cancel_confirm')));
    expect(find.text('Cancelado'), findsOneWidget);

    await tocar(tester, find.byKey(const Key('notices_tab_terms')));
    await tocar(tester, find.byKey(const Key('terms_new_button')));
    await tester.enterText(find.byKey(const Key('terms_version')), '2099.1');
    await tester.enterText(find.byKey(const Key('terms_summary')), '[TEXTO PLACEHOLDER]');
    await tocar(tester, find.byKey(const Key('terms_submit')));

    expect(find.text('Versão 2099.1'), findsOneWidget);
    expect(find.text('Aguardando revisão jurídica'), findsOneWidget);
    final publicar = find.widgetWithText(FilledButton, 'Publicar');
    expect(publicar, findsOneWidget);
    expect(tester.widget<FilledButton>(publicar).onPressed, isNull);

    await tocar(tester, find.textContaining('Marcar como revisado').first);
    await tocar(tester, find.byKey(const Key('terms_review_confirm')));
    final publicarHabilitado = find.text('Publicar');
    await tocar(tester, publicarHabilitado.first);
    await tocar(tester, find.byKey(const Key('terms_publish_confirm')));

    expect(find.textContaining('Publicada em'), findsOneWidget);
  });

  testWidgets('coordenador abre Avisos e não vê a sub-aba Termos', (tester) async {
    await entrar(tester, role: 'coordinator');
    await abrirAvisos(tester);

    expect(find.byKey(const Key('notices_tab_history')), findsOneWidget);
    expect(find.byKey(const Key('notices_tab_terms')), findsNothing);
    expect(find.text('Termos'), findsNothing);
  });
}
