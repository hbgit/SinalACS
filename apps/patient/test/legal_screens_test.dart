import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/legal_screens.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

import 'support/fake_patient_backend.dart';
import 'support/contrast.dart';
import 'support/semantics_scan.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('antes de entrar, a tela de login abre a política e o termo', (
    tester,
  ) async {
    // Ler antes de aceitar: os documentos têm de abrir sem sessão.
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await tapKey(tester, 'login_legal_link');

    expect(find.byType(LegalDocumentsScreen), findsOneWidget);
    await tapKey(tester, 'legal_open_privacy');
    expect(find.text('Política de Privacidade'), findsWidgets);
    expect(
      find.textContaining('Versão $legalDocumentsVersion'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'legal_open_terms');
    expect(find.text('Termo de Uso'), findsWidgets);
  });

  testWidgets(
    'documento mostra resumo, texto completo expansível e histórico de versões',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: LegalDocumentScreen(document: privacyPolicy)),
      );

      expect(find.byKey(const Key('legal_summary')), findsOneWidget);
      for (final step in privacyPolicy.summary) {
        expect(find.text(step.title), findsOneWidget);
      }
      // Versão completa recolhida por padrão: o corpo só aparece ao expandir.
      final first = privacyPolicy.sections.first;
      expect(find.text(first.body), findsNothing);
      await tapKey(tester, 'legal_section_0');
      expect(find.text(first.body), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('legal_history')));
      expect(
        find.descendant(
          of: find.byKey(const Key('legal_history')),
          matching: find.textContaining('2026.1 · vigente desde 29/09/2026'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'índice dos documentos não tem botão inerte para leitor de tela',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: LegalDocumentsScreen()));
      expectNenhumBotaoInerte(tester);
      handle.dispose();
    },
  );

  testWidgets('números dos passos do resumo têm contraste de texto normal', (
    tester,
  ) async {
    // Dígito de 16sp sobre círculo preenchido: é texto normal (WCAG 1.4.3,
    // 4.5:1), não "texto grande" — o fill `accent` puro fica em ~3.7:1.
    await tester.pumpWidget(
      const MaterialApp(home: LegalDocumentScreen(document: privacyPolicy)),
    );
    final avatars = tester.widgetList<CircleAvatar>(
      find.descendant(
        of: find.byKey(const Key('legal_summary')),
        matching: find.byType(CircleAvatar),
      ),
    );
    expect(avatars, isNotEmpty);
    for (final avatar in avatars) {
      final ratio = contrastOn(avatar.foregroundColor!, avatar.backgroundColor!);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: '$ratio:1');
    }
  });
}
