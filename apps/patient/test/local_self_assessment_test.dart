/// C-11 (#132): autoavaliação local no pilar A, sem sessão nem registro no
/// servidor (RF04, RF16, RF22, RNF09).
///
/// A paridade das 64 combinações com o motor do backend é provada do lado do
/// servidor, por `backend/sinalacs_server/test/unit/self_assessment_parity_test.dart`,
/// que importa o motor do app; aqui se prova que a tela usa esse motor e que
/// nada sai do aparelho.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/events/local_event_log.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/triage/self_assessment.dart';

import 'support/fake_patient_backend.dart';

/// Backend que registra TODA chamada, de qualquer método, e falha. É a rede do
/// app: o paciente não fala com o servidor por nenhum outro caminho.
class _NetworkSentinel implements PatientBackend {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('chamada de rede na autoavaliação local: ${invocation.memberName}');
  }
}

Future<void> _openLocalSelfAssessment(WidgetTester tester) async {
  final entrada = find.byKey(const Key('login_self_assessment_button'));
  await tester.ensureVisible(entrada);
  await tester.pumpAndSettle();
  await tester.tap(entrada);
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, Set<TriageSymptom> yesTo) async {
  for (final symptom in TriageSymptom.values) {
    final key = yesTo.contains(symptom) ? symptom.key : '${symptom.key}_no';
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_triage')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('sem login: a autoavaliação abre na entrada e não faz nenhuma chamada de rede', (tester) async {
    final backend = _NetworkSentinel();
    await tester.pumpWidget(SinalAcsApp(backend: backend, localEvents: InMemoryLocalEventLog()));
    await tester.pumpAndSettle();
    final antes = List.of(backend.calls);

    await _openLocalSelfAssessment(tester);
    await _answer(tester, {TriageSymptom.fever});

    expect(find.text('Risco: Amarelo'), findsOneWidget);
    expect(backend.calls, antes, reason: 'nenhum método do backend pode ser chamado no pilar A');
  });

  testWidgets('o resultado local não fala de solicitação nem de agente', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: _NetworkSentinel()));
    await tester.pumpAndSettle();
    await _openLocalSelfAssessment(tester);

    await _answer(tester, const {});

    expect(find.text('Risco: Verde'), findsOneWidget);
    expect(find.textContaining('nada foi enviado'), findsOneWidget);
    expect(find.textContaining('solicitação'), findsNothing);
    expect(find.textContaining('entrará em contato'), findsNothing);

    // "Concluir" volta à entrada, ainda sem conta.
    await tester.tap(find.byKey(const Key('triage_continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cpf_field')), findsOneWidget);
  });

  testWidgets('vermelho local: orientação "Ligar 192", evento local e nada enviado', (tester) async {
    final backend = _NetworkSentinel();
    final events = InMemoryLocalEventLog();
    await tester.pumpWidget(SinalAcsApp(backend: backend, localEvents: events));
    await tester.pumpAndSettle();
    final antes = List.of(backend.calls);
    await _openLocalSelfAssessment(tester);

    await _answer(tester, {TriageSymptom.bleeding});

    expect(find.byKey(const Key('call_192_title')), findsOneWidget);
    expect(backend.calls, antes);
    final gravados = await events.list();
    expect(gravados.single.kind, LocalEventKind.call192OrientationShown);
    expect(gravados.single.engineVersion, selfAssessmentEngineVersion);

    await tester.tap(find.byKey(const Key('call_192_close')));
    await tester.pumpAndSettle();
    expect(find.text('Passo 1 de 6'), findsOneWidget);
  });

  testWidgets('a tela segue o motor do aparelho: cada saída da árvore aparece', (tester) async {
    // Uma amostra que cobre as três saídas pelo widget; as 64 combinações são
    // comparadas com o backend no teste de paridade.
    const engine = SelfAssessmentEngine();
    final casos = <Set<TriageSymptom>, String>{
      {TriageSymptom.persistentVomiting}: 'Risco: Amarelo',
      {TriageSymptom.fever, TriageSymptom.persistentVomiting}: 'Risco: Amarelo',
      const {}: 'Risco: Verde',
    };
    for (final MapEntry(key: sim, value: rotulo) in casos.entries) {
      final esperado = engine.evaluate(
        chestPain: sim.contains(TriageSymptom.chestPain),
        difficultyBreathing: sim.contains(TriageSymptom.difficultyBreathing),
        fever: sim.contains(TriageSymptom.fever),
        persistentVomiting: sim.contains(TriageSymptom.persistentVomiting),
        bleeding: sim.contains(TriageSymptom.bleeding),
        severeWeakness: sim.contains(TriageSymptom.severeWeakness),
      );
      expect(rotulo, 'Risco: ${{'yellow': 'Amarelo', 'green': 'Verde'}[esperado.name]}');

      await tester.pumpWidget(SinalAcsApp(backend: _NetworkSentinel()));
      await tester.pumpAndSettle();
      await _openLocalSelfAssessment(tester);
      await _answer(tester, sim);
      expect(find.text(rotulo), findsOneWidget, reason: '$sim');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('com sessão (pilar B), a autoavaliação continua indo ao servidor', (tester) async {
    final backend = FakePatientBackend(risk: RiskLevel.yellow);
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
    await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
    await tester.tap(find.byKey(const Key('enter_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
    await tester.tap(find.byKey(const Key('verify_code_button')));
    await tester.pumpAndSettle();

    await _answer(tester, {TriageSymptom.fever});

    expect(backend.triageCalls, hasLength(1));
    expect(find.text('Risco: Amarelo'), findsOneWidget);
    expect(find.text('Acompanhar solicitação'), findsOneWidget);
  });
}
