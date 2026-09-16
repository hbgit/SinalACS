import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import '../test/support/failing_admin_data_source.dart';

/// Validação do backoffice num dispositivo Android real (ou emulador).
///
/// ATENÇÃO — este arquivo é **hermético**, ao contrário dos `integration_test/`
/// do app ACS e do app do paciente. O backoffice ainda roda sobre
/// `MockAdminDataSource`, então aqui **não** é preciso `docker compose up`,
/// nem seed, nem `--dart-define`. Basta:
///
///     flutter test integration_test -d emulator-5554
///
/// O que isto cobre e `flutter test` não consegue cobrir: o runtime real do
/// Android — densidade de tela, insets do sistema, rotação de verdade e a
/// escala de fonte do aparelho — em vez da janela sintética de 800x600 do
/// `flutter_test`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> entrar(WidgetTester tester, {dynamic dataSource}) async {
    await tester.pumpWidget(SinalAdminApp(dataSource: dataSource, devLoginEnabled: true));
    await tester.pumpAndSettle();
    final entrar = find.byKey(const Key('login_button'));
    await tester.ensureVisible(entrar);
    await tester.pumpAndSettle();
    await tester.tap(entrar);
    await tester.pumpAndSettle();
  }

  Future<void> irPara(WidgetTester tester, String destino) async {
    final alvo = find.text(destino).last;
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  testWidgets('abre o backoffice no dispositivo e navega pelos quatro destinos', (tester) async {
    await entrar(tester);

    expect(find.text('Painel de Indicadores'), findsOneWidget);
    await irPara(tester, 'Microáreas');
    expect(find.text('Microáreas e vínculo ACS'), findsOneWidget);
    await irPara(tester, 'Alertas');
    expect(find.text('Alertas da UBS'), findsOneWidget);
    await irPara(tester, 'Auditoria');
    expect(find.text('Logs de auditoria'), findsOneWidget);
  });

  testWidgets('escolhe a navegação conforme a largura real do aparelho', (tester) async {
    await entrar(tester);

    // Em celular sai a barra inferior; em tablet, o rail lateral. Qual dos dois
    // depende do aparelho — o que se afirma aqui é que existe exatamente um.
    final rail = find.byKey(const Key('admin_navigation_rail')).evaluate().length;
    final barra = find.byKey(const Key('admin_navigation_bar')).evaluate().length;
    expect(rail + barra, 1, reason: 'deve haver exatamente uma navegação, nunca as duas nem nenhuma');
  });

  testWidgets('não estoura o layout ao girar o aparelho', (tester) async {
    await entrar(tester);

    final tamanhoOriginal = tester.view.physicalSize;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = Size(tamanhoOriginal.height, tamanhoOriginal.width);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'estouro de layout após girar para paisagem');

    tester.view.physicalSize = tamanhoOriginal;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'estouro de layout ao voltar para retrato');
  });

  testWidgets('bloqueia a exibição de dado sensível quando a auditoria falha', (tester) async {
    // PRD §4.2.2: acesso do administrador precisa ser auditado. Se o registro
    // falha, a tela mostra erro — nunca o dado sem auditoria (nada de
    // fail-open). Já coberto em `flutter test`; repetido aqui para valer também
    // no runtime real do Android.
    final dataSource = FailingAdminDataSource(inner: MockAdminDataSource())..failNextRecordAccess = true;
    await entrar(tester, dataSource: dataSource);

    await irPara(tester, 'Microáreas');

    expect(find.text('Microáreas e vínculo ACS'), findsNothing);
    expect(find.textContaining('Não foi possível'), findsOneWidget);
  });
}
