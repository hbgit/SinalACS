import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/terms_panel.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/layout_harness.dart';

/// Formulário de nova versão de termos (#46). Só texto placeholder.
final _agora = DateTime(2026, 10, 14, 9);
const _texto = '[TEXTO PLACEHOLDER]';

class _Chamada {
  _Chamada(this.version, this.summary, this.effectiveFrom);
  final String version;
  final String summary;
  final DateTime effectiveFrom;
}

class _Fake extends MockAdminDataSource {
  _Fake() : super(now: () => _agora);

  final List<_Chamada> chamadas = [];
  Completer<void>? portao;
  Object? erro;

  @override
  Future<TermsVersionSummary> draftTermsVersion({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
  }) async {
    chamadas.add(_Chamada(version, summary, effectiveFrom));
    if (portao != null) await portao!.future;
    final e = erro;
    if (e != null) throw e;
    return super.draftTermsVersion(version: version, summary: summary, effectiveFrom: effectiveFrom);
  }
}

Future<void> _abrir(WidgetTester tester, _Fake fonte, {VoidCallback? aoVencer}) async {
  redimensionar(tester, const Size(1024, 1000));
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(
        body: AdminSessionScope(
          aoVencer: aoVencer ?? () {},
          child: TermsPanel(dataSource: fonte, now: () => _agora),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('terms_new_button')));
  await tester.pumpAndSettle();
}

Future<void> _preencher(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('terms_version')), '  2026.2  ');
  await tester.enterText(find.byKey(const Key('terms_summary')), '  $_texto  ');
  await tester.pumpAndSettle();
}

FilledButton _submit(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('terms_submit')));

void main() {
  testWidgets('versão vazia: submit desabilitado; resumo com limite 280 e ajuda', (tester) async {
    await _abrir(tester, _Fake());
    expect(_submit(tester).onPressed, isNull);
    expect(find.text('0/280'), findsOneWidget);
    expect(find.text('Resumo público exibido no cartão do paciente.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('terms_summary')), _texto);
    await tester.pumpAndSettle();
    expect(_submit(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('terms_version')), '   ');
    await tester.pumpAndSettle();
    expect(_submit(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('terms_version')), '2026.2');
    await tester.pumpAndSettle();
    expect(_submit(tester).onPressed, isNotNull);
  });

  testWidgets('data padrão é a próxima meia-noite a partir de now+15 dias', (tester) async {
    // 14/10 09:00 + 15 dias = 29/10 09:00 -> próxima meia-noite: 30/10.
    await _abrir(tester, _Fake());
    expect(find.text('Vigora em 30/10/2026'), findsOneWidget);
  });

  testWidgets('criar: uma chamada com valores aparados e vigência às 00:00 local; fecha e avisa', (tester) async {
    final f = _Fake();
    await _abrir(tester, f);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('terms_submit')));
    await tester.pumpAndSettle();
    expect(f.chamadas, hasLength(1));
    expect(f.chamadas.single.version, '2026.2');
    expect(f.chamadas.single.summary, _texto);
    expect(f.chamadas.single.effectiveFrom, DateTime(2026, 10, 30));
    expect(find.byKey(const Key('terms_submit')), findsNothing);
    expect(find.text('Rascunho criado.'), findsOneWidget);
    expect(find.text('Versão 2026.2'), findsOneWidget);
  });

  testWidgets('duplo toque dispara uma única chamada', (tester) async {
    final f = _Fake()..portao = Completer<void>();
    await _abrir(tester, f);
    await _preencher(tester);
    final alvo = find.byKey(const Key('terms_submit'));
    await tester.tap(alvo);
    await tester.tap(alvo, warnIfMissed: false);
    await tester.pump();
    expect(f.chamadas, hasLength(1));
    f.portao!.complete();
    await tester.pumpAndSettle();
    expect(f.chamadas, hasLength(1));
  });

  testWidgets('erro do servidor fica dentro do diálogo, que continua aberto', (tester) async {
    final f = _Fake()..erro = const AdminValidationFailure('Já existe uma versão com este número.');
    await _abrir(tester, f);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('terms_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Já existe uma versão com este número.'), findsOneWidget);
    expect(find.byKey(const Key('terms_version')), findsOneWidget);
    expect(_submit(tester).onPressed, isNotNull);
  });

  testWidgets('sessão vencida aciona o callback capturado', (tester) async {
    var venceu = 0;
    final f = _Fake()..erro = const AdminSessionExpired();
    await _abrir(tester, f, aoVencer: () => venceu++);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('terms_submit')));
    await tester.pumpAndSettle();
    expect(venceu, 1);
  });

  testWidgets('cancelar fecha sem chamar o data source', (tester) async {
    final f = _Fake();
    await _abrir(tester, f);
    await tester.tap(find.byKey(const Key('terms_form_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terms_version')), findsNothing);
    expect(f.chamadas, isEmpty);
  });
}
