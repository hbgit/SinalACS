import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show TermsChangeNotice;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';
import 'support/semantics_scan.dart';

final _aviso = TermsChangeNotice(
  version: '2026.2',
  effectiveFrom: DateTime.utc(2026, 10, 20, 12),
  summary: 'Novo canal de dúvidas.',
);

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
}
