import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';

Future<void> login(
  WidgetTester tester, {
  String cpf = '123.456.789-09',
  String nascimento = '01/01/1990',
  String codigo = '123456',
}) async {
  await tester.enterText(find.byKey(const Key('cpf_field')), cpf);
  await tester.enterText(find.byKey(const Key('birth_date_field')), nascimento);
  await tester.tap(find.byKey(const Key('enter_button')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('otp_code_field')), codigo);
  await tester.tap(find.byKey(const Key('verify_code_button')));
  await tester.pumpAndSettle();
}


Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Paciente que ainda não aceitou nada: é o de quem entrou por OTP sem onboarding.
FakePatientBackend semAceite() {
  final backend = FakePatientBackend();
  backend.myDataResult = backend.myDataResult.copyWith(consents: const []);
  return backend;
}

void main() {
  testWidgets('sem aceite registrado, o login leva à tela de aceite', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsOneWidget);
    expect(find.text('Registrar alerta de urgência'), findsNothing);
  });

  testWidgets('aceitar exige marcar a caixa, grava uma vez e segue para a tela inicial', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    final antes = tester.widget<FilledButton>(find.byKey(const Key('terms_gate_accept_button')));
    expect(antes.onPressed, isNull);

    await tapKey(tester, 'terms_gate_checkbox');
    await tapKey(tester, 'terms_gate_accept_button');

    expect(backend.acceptTermsCalls, 1);
    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
  });

  testWidgets('"Agora não" entra sem gravar nada', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    await tapKey(tester, 'terms_gate_later_button');

    expect(backend.acceptTermsCalls, 0);
    expect(find.byKey(const Key('terms_gate_later_button')), findsNothing);
  });

  testWidgets('já aceitou a versão vigente: nenhuma tela extra, uma leitura', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
    expect(backend.myDataCallCount, 1);
  });

  testWidgets('falha ao ler os consentimentos não impede a entrada', (tester) async {
    // Emergência: o alerta de urgência não pode ficar atrás de um aceite.
    final backend = semAceite()..myDataFailure = const BackendFailure('sem rede');
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('falha ao aceitar mostra o erro, mantém "Agora não" e permite tentar de novo', (tester) async {
    final backend = semAceite()..acceptTermsFailure = const BackendFailure('Sem conexão.');
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    await tapKey(tester, 'terms_gate_checkbox');
    await tapKey(tester, 'terms_gate_accept_button');

    expect(find.byKey(const Key('terms_gate_error')), findsOneWidget);
    expect(find.byKey(const Key('terms_gate_later_button')), findsOneWidget);

    backend.acceptTermsFailure = null;
    await tapKey(tester, 'terms_gate_accept_button');
    expect(backend.acceptTermsCalls, 2);
    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
  });

  testWidgets('"Ler o Termo e a Política" abre os documentos', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: semAceite()));
    await login(tester);

    await tapKey(tester, 'terms_gate_read_button');

    expect(find.textContaining('Versão $legalDocumentsVersion'), findsWidgets);
  });

  testWidgets('leitura de consentimentos pendurada não segura o paciente no login', (tester) async {
    // `verifyOtp` já deu sessão: a checagem do aceite não pode ficar entre o
    // paciente e o alerta de urgência (a espera padrão do cliente é de 20 s).
    final backend = semAceite()..myDataGate = Completer<void>();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terms_gate_accept_button')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a tela de aceite não diz que é obrigatório e lembra do alerta', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: semAceite()));
    await login(tester);

    expect(find.textContaining('para continuar'), findsNothing);
    expect(find.textContaining('alerta de urgência continua disponível'), findsOneWidget);
  });

  testWidgets('"Agora não" tocado duas vezes entra uma vez só', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: semAceite()));
    await login(tester);

    final later = find.byKey(const Key('terms_gate_later_button'));
    await tester.tap(later);
    await tester.tap(later, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
