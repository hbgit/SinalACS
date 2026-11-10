/// C-04 (#127): pedido de contato sem rótulo de urgência e saída "Ligar 192"
/// sem envio (P-09, `spec/requisitos_piloto.md` §INV-03 no piloto).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/events/local_event_log.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';
import 'package:sinalacs_patient/core/services/emergency_dialer.dart';
import 'package:sinalacs_patient/core/triage/self_assessment.dart';

import 'support/fake_patient_backend.dart';

class _FakeDialer implements EmergencyDialer {
  _FakeDialer({this.opens = true});

  final bool opens;
  final dialed = <String>[];

  @override
  Future<bool> dial(String number) async {
    dialed.add(number);
    return opens;
  }
}

/// Trilha cujo banco não abre: a orientação tem de aparecer e fechar igual.
class _BrokenEventLog implements LocalEventLog {
  var attempts = 0;

  @override
  Future<void> record(LocalEvent event) async {
    attempts++;
    throw StateError('banco local indisponível');
  }

  @override
  Future<List<LocalEvent>> list() async => const [];
}

class _NoLocation implements LocationReader {
  @override
  Future<LocationReading> read({Duration timeout = const Duration(seconds: 5)}) async =>
      const LocationUnavailable(LocationUnavailableReason.unknown);
}

Future<void> _openContact(WidgetTester tester) async {
  await tester.tap(find.text('Contato'));
  await tester.pumpAndSettle();
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
  await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
  await tester.tap(find.byKey(const Key('enter_button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
  await tester.tap(find.byKey(const Key('verify_code_button')));
  await tester.pumpAndSettle();
}

/// Responde à autoavaliação com "sim" só para dor no peito (vermelho no motor).
Future<void> _answerRed(WidgetTester tester) async {
  await tester.tap(find.text('Triagem'));
  await tester.pumpAndSettle();
  for (final symptom in TriageSymptom.values) {
    final key = symptom == TriageSymptom.chestPain ? symptom.key : '${symptom.key}_no';
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_triage')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('saída "Ligar 192" da autoavaliação', () {
    testWidgets('mostra a orientação, grava o evento local e não chama createRedAlert', (tester) async {
      final backend = FakePatientBackend(risk: RiskLevel.red);
      final events = InMemoryLocalEventLog();
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        localEvents: events,
        emergencyDialer: _FakeDialer(),
      ));
      await _login(tester);

      await _answerRed(tester);

      expect(find.byKey(const Key('call_192_title')), findsOneWidget);
      expect(find.byKey(const Key('call_192_button')), findsOneWidget);
      // Nada saiu para o agente: nenhuma chamada a `alerts.createRedAlert`.
      expect(backend.idempotencyKeys, isEmpty);
      // Nem rótulo de risco nem a promessa antiga de que a equipe foi avisada.
      expect(find.textContaining('Risco'), findsNothing);
      expect(find.textContaining('foi avisada'), findsNothing);

      final recorded = await events.list();
      expect(recorded, hasLength(1));
      expect(recorded.single.kind, LocalEventKind.call192OrientationShown);
      expect(recorded.single.engineVersion, selfAssessmentEngineVersion);
      expect(recorded.single.occurredAt.isUtc, isTrue);
    });

    testWidgets('não fecha pelo voltar do sistema; só pela escolha explícita', (tester) async {
      final backend = FakePatientBackend(risk: RiskLevel.red);
      final events = InMemoryLocalEventLog();
      await tester.pumpWidget(SinalAcsApp(backend: backend, localEvents: events));
      await _login(tester);
      await _answerRed(tester);

      // Voltar do sistema (botão ou gesto do Android).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call_192_title')), findsOneWidget);
      // Sem botão de voltar no cabeçalho.
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(CloseButton), findsNothing);

      await tester.tap(find.byKey(const Key('call_192_close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call_192_title')), findsNothing);
      // A autoavaliação recomeça do zero, sem guardar as respostas.
      expect(find.text('Passo 1 de 6'), findsOneWidget);
      // Fechar não gera pedido nem um segundo evento.
      expect(backend.idempotencyKeys, isEmpty);
      expect(await events.list(), hasLength(1));
    });

    testWidgets('"Ligar 192" abre o discador com 192, sem ligar sozinho', (tester) async {
      final dialer = _FakeDialer();
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(risk: RiskLevel.red),
        localEvents: InMemoryLocalEventLog(),
        emergencyDialer: dialer,
      ));
      await _login(tester);
      await _answerRed(tester);

      await tester.tap(find.byKey(const Key('call_192_button')));
      await tester.pumpAndSettle();

      expect(dialer.dialed, ['192']);
      // Ligar não fecha a orientação: a pessoa pode voltar a ela.
      expect(find.byKey(const Key('call_192_title')), findsOneWidget);
    });

    testWidgets('sem discador no aparelho, diz para ligar 192 pelo telefone', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(risk: RiskLevel.red),
        localEvents: InMemoryLocalEventLog(),
        emergencyDialer: _FakeDialer(opens: false),
      ));
      await _login(tester);
      await _answerRed(tester);

      await tester.tap(find.byKey(const Key('call_192_button')));
      await tester.pump();

      expect(find.text('Não foi possível abrir o discador. Ligue 192 pelo telefone.'), findsOneWidget);
    });

    testWidgets('com o banco local indisponível a orientação aparece e fecha igual', (tester) async {
      final events = _BrokenEventLog();
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(risk: RiskLevel.red),
        localEvents: events,
      ));
      await _login(tester);
      await _answerRed(tester);

      expect(events.attempts, 1);
      expect(find.byKey(const Key('call_192_title')), findsOneWidget);
      await tester.tap(find.byKey(const Key('call_192_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call_192_title')), findsNothing);
    });

    testWidgets('o título é cabeçalho e a tela passa nas diretrizes de alvo de toque', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(risk: RiskLevel.red),
        localEvents: InMemoryLocalEventLog(),
      ));
      await _login(tester);
      await _answerRed(tester);

      final titulo = tester.getSemantics(find.byKey(const Key('call_192_title')));
      expect(titulo.getSemanticsData().flagsCollection.isHeader, isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('querer falar com o agente depois é um ato separado, na aba Contato', (tester) async {
      final backend = FakePatientBackend(risk: RiskLevel.red);
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        localEvents: InMemoryLocalEventLog(),
        locationReader: _NoLocation(),
      ));
      await _login(tester);
      await _answerRed(tester);
      await tester.tap(find.byKey(const Key('call_192_close')));
      await tester.pumpAndSettle();
      expect(backend.idempotencyKeys, isEmpty);

      await tester.tap(find.text('Contato'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panic_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar pedido'));
      await tester.pumpAndSettle();

      // Agora sim, sob a INV-03: um pedido, com a localização de reserva.
      expect(backend.idempotencyKeys, hasLength(1));
      expect(backend.locationHashes.single, unknownLocationHash);
    });
  });

  group('aba Contato', () {
    testWidgets('"Ligar 192" aparece antes do pedido de contato', (tester) async {
      final dialer = _FakeDialer();
      await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend(), emergencyDialer: dialer));
      await _login(tester);
      await _openContact(tester);
      expect(find.text('Pedido de contato'), findsOneWidget);

      final ligar = tester.getRect(find.byKey(const Key('call_192_button')));
      final pedido = tester.getRect(find.byKey(const Key('panic_button')));
      expect(ligar.bottom, lessThan(pedido.top));

      await tester.tap(find.byKey(const Key('call_192_button')));
      await tester.pumpAndSettle();
      expect(dialer.dialed, ['192']);
    });

    testWidgets('nenhum rótulo de urgência nem promessa de atendimento na tela', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(),
        locationReader: _NoLocation(),
      ));
      await _login(tester);
      await _openContact(tester);
      await tester.tap(find.byKey(const Key('panic_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar pedido'));
      await tester.pumpAndSettle();

      expect(find.text('Pedido enviado ao agente. Acompanhe a resposta na aba Status.'), findsOneWidget);
      for (final proibido in ['EMERGÊNCIA', 'Urgência', 'Alerta', 'recebido pela equipe', 'Atendid']) {
        expect(find.textContaining(proibido), findsNothing, reason: proibido);
      }
      // "Ligar 192" é o único caminho de emergência na tela.
      expect(find.textContaining('Em risco de vida, ligue 192'), findsOneWidget);
    });

    testWidgets('o estado do pedido é anunciado ao leitor de tela', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend(), locationReader: _NoLocation()));
      await _login(tester);
      await _openContact(tester);
      await tester.tap(find.byKey(const Key('panic_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar pedido'));
      await tester.pumpAndSettle();

      final estado = tester.getSemantics(find.byKey(const Key('contact_request_state')));
      expect(estado.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });
}

