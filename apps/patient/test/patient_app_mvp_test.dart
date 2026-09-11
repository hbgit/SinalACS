import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';

/// Responde "não" a todos os sintomas menos [yesTo], e conclui a triagem.
Future<void> answerTriage(
  WidgetTester tester, {
  Set<TriageSymptom> yesTo = const <TriageSymptom>{},
}) async {
  for (final symptom in TriageSymptom.values) {
    final key = yesTo.contains(symptom) ? symptom.key : '${symptom.key}_no';
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_triage')));
    await tester.pumpAndSettle();
  }
}

Future<void> login(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('enter_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deve autenticar no backend antes de abrir a triagem', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    expect(find.text('SinalACS'), findsOneWidget);
    expect(find.text('Acesso sem senha'), findsOneWidget);

    await login(tester);

    expect(backend.loginCount, 1);
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('não deve avançar quando a autenticação falha', (tester) async {
    final backend = FakePatientBackend(
      loginFailure: const BackendFailure('Sem conexão com o servidor.'),
    );
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await login(tester);

    // A tela antiga navegava incondicionalmente; a regressão que este teste
    // protege é justamente entrar no app sem ter falado com o servidor.
    expect(find.text('Triagem rápida'), findsNothing);
    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
  });

  testWidgets('deve enviar os sintomas ao servidor e exibir o risco recebido', (tester) async {
    final backend = FakePatientBackend(risk: RiskLevel.red);
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await login(tester);
    await answerTriage(tester, yesTo: {TriageSymptom.chestPain});

    expect(backend.triageCalls, hasLength(1));
    expect(backend.triageCalls.single, {
      'chestPain': true,
      'difficultyBreathing': false,
      'fever': false,
      'persistentVomiting': false,
      'bleeding': false,
      'severeWeakness': false,
    });
    expect(find.text('Risco: Vermelho'), findsOneWidget);
  });

  testWidgets('deve exibir o risco do servidor mesmo quando contraria o sintoma informado', (tester) async {
    // O app não tem regra de risco própria: exibe o que o motor determinístico
    // do servidor devolveu. Se a tela recalculasse localmente, este teste
    // mostraria "Vermelho" e falharia.
    final backend = FakePatientBackend(risk: RiskLevel.green);
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await login(tester);
    await answerTriage(tester, yesTo: {TriageSymptom.chestPain});

    expect(find.text('Risco: Verde'), findsOneWidget);
    expect(find.text('Risco: Vermelho'), findsNothing);
  });

  testWidgets('deve reusar a chave de idempotência quando o envio do alerta falha', (tester) async {
    final backend = FakePatientBackend(
      alertFailure: const BackendFailure('Sem conexão com o servidor.'),
    );
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await login(tester);

    // Vai para a aba de urgência.
    await tester.tap(find.text('Urgência'));
    await tester.pumpAndSettle();

    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.byKey(const Key('panic_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar alerta'));
      await tester.pumpAndSettle();
    }

    expect(backend.idempotencyKeys, hasLength(2));
    // Duas tentativas da MESMA emergência precisam levar a mesma chave, senão o
    // retry cria um segundo alerta vermelho no servidor.
    expect(backend.idempotencyKeys.first, backend.idempotencyKeys.last);
  });

  testWidgets('deve expor rótulo semântico e alvo de toque acessível no fluxo do paciente', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));

    final enterButton = tester.widget<FilledButton>(find.byKey(const Key('enter_button')));
    final minimumSize = enterButton.style?.minimumSize?.resolve({}) ?? const Size(0, 0);

    expect(find.bySemanticsLabel('Entrar na triagem do paciente'), findsOneWidget);
    expect(minimumSize.height, greaterThanOrEqualTo(48));
    expect(minimumSize.width, greaterThanOrEqualTo(48));
  });
}
