import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/terms_panel.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/layout_harness.dart';

/// Painel de termos (#46). Só texto placeholder: nenhum texto jurídico real.
final _agora = DateTime(2026, 10, 14, 9);
const _texto = '[TEXTO PLACEHOLDER]';

class _Fake extends MockAdminDataSource {
  _Fake() : super(now: () => _agora);

  int revisoes = 0;
  int publicacoes = 0;
  Object? erroNaPublicacao;
  Object? erroNaCarga;
  final List<(String, String)> acessos = [];

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {
    acessos.add((actionType, resourceType));
  }

  @override
  Future<List<TermsVersionSummary>> fetchTermsVersions() async {
    final e = erroNaCarga;
    if (e != null) throw e;
    return super.fetchTermsVersions();
  }

  @override
  Future<TermsVersionSummary> markTermsReviewed(String id) {
    revisoes++;
    return super.markTermsReviewed(id);
  }

  @override
  Future<TermsVersionSummary> publishTermsVersion(String id) {
    publicacoes++;
    final e = erroNaPublicacao;
    if (e != null) throw e;
    return super.publishTermsVersion(id);
  }
}

Future<TermsVersionSummary> _rascunho(_Fake f, {String versao = '2026.2', int dias = 30}) =>
    f.draftTermsVersion(version: versao, summary: _texto, effectiveFrom: DateTime(2026, 10, 14 + dias));

Future<void> _abrir(WidgetTester tester, _Fake fonte, {VoidCallback? aoVencer, bool assentar = true}) async {
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
  // Sessão vencida deixa um spinner girando: pumpAndSettle nunca assentaria.
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

FilledButton _publicar(WidgetTester tester, String id) =>
    tester.widget<FilledButton>(find.byKey(Key('terms_publish_$id')));

void main() {
  testWidgets('lista vazia, texto de ajuda e carga auditada', (tester) async {
    final f = _Fake();
    await _abrir(tester, f);
    expect(find.text('Nenhuma versão de termos cadastrada.'), findsOneWidget);
    expect(find.textContaining('O texto integral dos termos vai no release do app do paciente.'), findsOneWidget);
    expect(f.acessos, [('view', 'terms_versions')]);
  });

  testWidgets('erro na carga mostra retry e recarrega', (tester) async {
    final f = _Fake()..erroNaCarga = const AdminDataFailure('Falha de teste.');
    await _abrir(tester, f);
    expect(find.text('Falha de teste.'), findsOneWidget);
    f.erroNaCarga = null;
    await _rascunho(f);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Versão 2026.2'), findsOneWidget);
  });

  testWidgets('sessão vencida na carga aciona o scope', (tester) async {
    var venceu = 0;
    final f = _Fake()..erroNaCarga = const AdminSessionExpired();
    await _abrir(tester, f, aoVencer: () => venceu++, assentar: false);
    expect(venceu, greaterThan(0));
  });

  testWidgets('rascunho: Publicar desabilitado e explica "Aguardando revisão jurídica"', (tester) async {
    final f = _Fake();
    final t = await _rascunho(f);
    await _abrir(tester, f);
    expect(find.text('Rascunho'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    expect(_publicar(tester, t.id).onPressed, isNull);
    expect(find.text('Aguardando revisão jurídica'), findsOneWidget);
    expect(find.text('Vigora em 13/11/2026'), findsOneWidget);
  });

  testWidgets('Marcar como revisado pede confirmação, chama uma vez e habilita Publicar', (tester) async {
    final f = _Fake();
    final t = await _rascunho(f);
    await _abrir(tester, f);
    await tester.tap(find.byKey(Key('terms_review_${t.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmo que o jurídico revisou a versão 2026.2.'), findsOneWidget);
    expect(f.revisoes, 0);
    await tester.tap(find.byKey(const Key('terms_review_confirm')));
    await tester.pumpAndSettle();
    expect(f.revisoes, 1);
    expect(find.text('Revisada'), findsOneWidget);
    expect(_publicar(tester, t.id).onPressed, isNotNull);
    expect(find.byKey(Key('terms_review_${t.id}')), findsNothing);
    expect(find.text('Aguardando revisão jurídica'), findsNothing);
  });

  testWidgets('cancelar a confirmação não revisa', (tester) async {
    final f = _Fake();
    final t = await _rascunho(f);
    await _abrir(tester, f);
    await tester.tap(find.byKey(Key('terms_review_${t.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(f.revisoes, 0);
  });

  testWidgets('publicar cita versão e vigência; depois mostra "Publicada em … · vigora em …" sem botões', (tester) async {
    final f = _Fake();
    final t = await _rascunho(f);
    await f.markTermsReviewed(t.id);
    await _abrir(tester, f);
    await tester.tap(find.byKey(Key('terms_publish_${t.id}')));
    await tester.pumpAndSettle();
    expect(
      find.text('A versão 2026.2 passará a valer em 13/11/2026. Os pacientes verão o aviso desde hoje.'),
      findsOneWidget,
    );
    expect(f.publicacoes, 0);
    await tester.tap(find.byKey(const Key('terms_publish_confirm')));
    await tester.pumpAndSettle();
    expect(f.publicacoes, 1);
    expect(find.text('Publicada em 14/10/2026 · vigora em 13/11/2026'), findsOneWidget);
    expect(find.byKey(Key('terms_publish_${t.id}')), findsNothing);
    expect(find.byKey(Key('terms_review_${t.id}')), findsNothing);
  });

  testWidgets('revisada a 14 dias: Publicar desabilitado com prazo esgotado; com folga (meia-noite após 15 dias) habilita', (tester) async {
    final f = _Fake();
    final curto = await _rascunho(f, versao: '2026.3', dias: 14);
    final ok = await _rascunho(f, versao: '2026.4', dias: 16);
    await f.markTermsReviewed(curto.id);
    await f.markTermsReviewed(ok.id);
    await _abrir(tester, f);
    expect(_publicar(tester, curto.id).onPressed, isNull);
    expect(find.text('Prazo de 15 dias esgotado: crie uma nova versão com vigência posterior.'), findsOneWidget);
    expect(_publicar(tester, ok.id).onPressed, isNotNull);
  });

  testWidgets('borda dos 15 dias: vigência em now+15d exatos habilita; 1 s a menos desabilita', (tester) async {
    final f = _Fake();
    final exato = await f.draftTermsVersion(
        version: '2026.5', summary: _texto, effectiveFrom: _agora.add(const Duration(days: 15)));
    final curto = await f.draftTermsVersion(
        version: '2026.6',
        summary: _texto,
        effectiveFrom: _agora.add(const Duration(days: 15)).subtract(const Duration(seconds: 1)));
    await f.markTermsReviewed(exato.id);
    await f.markTermsReviewed(curto.id);
    await _abrir(tester, f);
    expect(_publicar(tester, exato.id).onPressed, isNotNull);
    expect(_publicar(tester, curto.id).onPressed, isNull);
    expect(find.text('Prazo de 15 dias esgotado: crie uma nova versão com vigência posterior.'), findsOneWidget);
  });

  testWidgets('erro do servidor na publicação vira SnackBar', (tester) async {
    final f = _Fake()..erroNaPublicacao = const AdminValidationFailure('A vigência exige 15 dias de antecedência.');
    final t = await _rascunho(f);
    await f.markTermsReviewed(t.id);
    await _abrir(tester, f);
    await tester.tap(find.byKey(Key('terms_publish_${t.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terms_publish_confirm')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(SnackBar), matching: find.text('A vigência exige 15 dias de antecedência.')), findsOneWidget);
    expect(f.publicacoes, 1);
  });

  testWidgets('sessão vencida ao publicar aciona o scope', (tester) async {
    var venceu = 0;
    final f = _Fake()..erroNaPublicacao = const AdminSessionExpired();
    final t = await _rascunho(f);
    await f.markTermsReviewed(t.id);
    await _abrir(tester, f, aoVencer: () => venceu++);
    await tester.tap(find.byKey(Key('terms_publish_${t.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terms_publish_confirm')));
    await tester.pumpAndSettle();
    expect(venceu, greaterThan(0));
  });
}
