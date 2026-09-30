import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show TermsChangeNotice;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';
import 'support/semantics_scan.dart';

final _aviso = TermsChangeNotice(
  version: '2026.2',
  effectiveFrom: DateTime.utc(2026, 10, 20, 12),
  summary: 'Novo canal de dúvidas.',
);

UpcomingLegalDocuments _textoNovoDe(String versao) => UpcomingLegalDocuments(
      version: versao,
      privacy: LegalDocument(
        id: 'privacy',
        title: 'Política de Privacidade',
        version: versao,
        effectiveDate: '20/10/2026',
        summary: privacyPolicy.summary,
        sections: privacyPolicy.sections,
        history: [
          LegalVersion(version: versao, date: '20/10/2026', changes: 'Texto novo.'),
          ...privacyPolicy.history,
        ],
      ),
      terms: LegalDocument(
        id: 'terms',
        title: 'Termo de Uso',
        version: versao,
        effectiveDate: '20/10/2026',
        summary: termsOfUse.summary,
        sections: termsOfUse.sections,
        history: [
          LegalVersion(version: versao, date: '20/10/2026', changes: 'Texto novo.'),
          ...termsOfUse.history,
        ],
      ),
    );

final _textoNovo = _textoNovoDe('2026.2');

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
  await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
  await tester.tap(find.byKey(const Key('enter_button')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
  await tester.tap(find.byKey(const Key('verify_code_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('com aviso ativo, a home mostra o cartão com a data e o resumo', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_change_notice_card')), findsOneWidget);
    expect(find.textContaining('20/10/2026'), findsOneWidget);
    expect(find.textContaining('2026.2'), findsOneWidget);
    expect(find.textContaining('Novo canal de dúvidas.'), findsOneWidget);
  });

  testWidgets('sem aviso, não há cartão', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await login(tester);
    expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
  });

  testWidgets('dispensar some com o cartão', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    await tester.tap(find.byKey(const Key('terms_change_notice_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
  });

  testWidgets('"Ler os termos atuais" abre os documentos', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    await tester.tap(find.byKey(const Key('terms_change_notice_read')));
    await tester.pumpAndSettle();
    expect(find.text('Privacidade e termos'), findsWidgets);
  });

  testWidgets('falha ao buscar o aviso não afeta a home nem mostra erro', (tester) async {
    final backend = FakePatientBackend()
      ..termsNotice = _aviso
      ..termsNoticeFailure = const BackendFailure('sem rede');
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    expect(find.byType(PatientHomeShell), findsOneWidget);
    expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
    expect(find.textContaining('sem rede'), findsNothing);
  });

  testWidgets('servidor que nunca responde não atrasa a home', (tester) async {
    final backend = FakePatientBackend()
      ..termsNotice = _aviso
      ..termsNoticeGate = Completer<void>();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    expect(find.byType(PatientHomeShell), findsOneWidget);
    expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);

    // Passado o teto, a busca abandonada não derruba nada.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(PatientHomeShell), findsOneWidget);
  });

  testWidgets('o shell montado sem BackendScope não quebra (teste de Lembretes)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PatientHomeShell(initialDestination: PatientDestination.reminders),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('o cartão não cria nó de botão inerte', (tester) async {
    final handle = tester.ensureSemantics();
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    expectNenhumBotaoInerte(tester);
    handle.dispose();
  });

  testWidgets('na aba de urgência o cartão não aparece e o botão de pânico fica na tela', (tester) async {
    // Tela pequena e fonte grande: o pior caso para o botão descer.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    expect(find.byKey(const Key('terms_change_notice_card')), findsOneWidget);

    await tester.tap(find.text('Urgência'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
    final botao = find.byKey(const Key('panic_button'));
    expect(botao, findsOneWidget);
    final area = tester.getRect(botao);
    expect(area.top, greaterThanOrEqualTo(0));
    expect(area.bottom, lessThanOrEqualTo(640));
  });

  testWidgets('o cartão volta nas outras abas depois de passar pela urgência', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    await tester.tap(find.text('Urgência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terms_change_notice_card')), findsOneWidget);
  });

  testWidgets('com o texto novo embarcado na mesma versão do aviso, oferece "Ler o texto novo"', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso; // versão 2026.2
    await tester.pumpWidget(SinalAcsApp(backend: backend, upcomingDocuments: _textoNovo));
    await login(tester);

    await tester.tap(find.byKey(const Key('terms_change_notice_read_new')));
    await tester.pumpAndSettle();

    expect(find.text('Termos que passam a valer'), findsOneWidget);
    expect(find.textContaining('Versão 2026.2'), findsWidgets);
  });

  testWidgets('o detalhe do texto novo diz que ele AINDA NÃO vale, com a data', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso; // vigência 20/10/2026
    await tester.pumpWidget(SinalAcsApp(backend: backend, upcomingDocuments: _textoNovo));
    await login(tester);
    await tester.tap(find.byKey(const Key('terms_change_notice_read_new')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('legal_open_terms')));
    await tester.pumpAndSettle();

    final versao = tester.widget<Text>(find.byKey(const Key('legal_version'))).data!;
    expect(versao, contains('passa a valer em 20/10/2026'));
    expect(versao, isNot(contains('vigente desde')));
    // O histórico também não pode chamar a versão futura de vigente.
    await tester.scrollUntilVisible(find.byKey(const Key('legal_history')), 300);
    expect(find.textContaining('2026.2 · passa a valer em 20/10/2026'), findsOneWidget);
    expect(find.textContaining('2026.2 · vigente desde'), findsNothing);
  });

  testWidgets('o detalhe do texto vigente continua dizendo "vigente desde"', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    await tester.tap(find.byKey(const Key('terms_change_notice_read')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('legal_open_terms')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('legal_version'))).data!, contains('vigente desde'));
  });

  testWidgets('aviso de versão que o app não conhece: só o texto vigente, sem erro', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend)); // sem texto novo embarcado
    await login(tester);
    expect(find.byKey(const Key('terms_change_notice_read_new')), findsNothing);
    expect(find.byKey(const Key('terms_change_notice_read')), findsOneWidget);
  });

  testWidgets('texto novo de OUTRA versão que a do aviso não é oferecido', (tester) async {
    final backend = FakePatientBackend()..termsNotice = _aviso; // 2026.2
    await tester.pumpWidget(SinalAcsApp(backend: backend, upcomingDocuments: _textoNovoDe('2026.3')));
    await login(tester);
    expect(find.byKey(const Key('terms_change_notice_read_new')), findsNothing);
  });

  testWidgets('o título do cartão é um cabeçalho semântico', (tester) async {
    final handle = tester.ensureSemantics();
    final backend = FakePatientBackend()..termsNotice = _aviso;
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    final data = tester.getSemantics(find.text('Os termos vão mudar')).getSemanticsData();
    expect(data.flagsCollection.isHeader, isTrue);
    expect(data.label, contains('Os termos vão mudar'));
    handle.dispose();
  });
}
