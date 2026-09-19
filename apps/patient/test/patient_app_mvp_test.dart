
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart'
    show AlertStatus, AlertStatusResult, RiskLevel;
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_scope.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:sinalacs_patient/core/reminders/reminder_store.dart';

import 'support/fake_patient_backend.dart';
import 'support/semantics_scan.dart';

/// Duplo de [ReminderStore] em memória — evita SQLite real no teste de
/// widget, mesmo padrão de `_FixedLocationReader`/`FakePatientBackend`.
class _InMemoryReminderStore implements ReminderStore {
  final _items = <int, Reminder>{};
  int _nextId = 1;

  @override
  Future<List<Reminder>> list() async => _items.values.toList()
    ..sort((a, b) => a.hour != b.hour ? a.hour - b.hour : a.minute - b.minute);

  @override
  Future<Reminder> save(Reminder reminder) async {
    if (reminder.id == 0) {
      final created = Reminder(
        id: _nextId++,
        label: reminder.label,
        hour: reminder.hour,
        minute: reminder.minute,
        active: reminder.active,
      );
      _items[created.id] = created;
      return created;
    }
    _items[reminder.id] = reminder;
    return reminder;
  }

  @override
  Future<void> delete(int id) async {
    _items.remove(id);
  }
}

/// Duplo de [ReminderScheduler] que só registra as chamadas recebidas —
/// nunca fala com `flutter_local_notifications`/canal de plataforma.
class _RecordingReminderScheduler implements ReminderScheduler {
  final scheduled = <int>[];
  final cancelled = <int>[];

  @override
  Future<void> schedule(Reminder reminder) async {
    scheduled.add(reminder.id);
  }

  @override
  Future<void> cancel(int reminderId) async {
    cancelled.add(reminderId);
  }
}

/// Duplo de [ReminderScheduler] que sempre lança — simula uma falha real do
/// plugin de notificações (`flutter_local_notifications` fala com código
/// nativo; pode falhar em dispositivo por motivos fora do controle da tela),
/// para provar que `RemindersScreen` trata o erro em vez de deixá-lo subir.
class _ThrowingReminderScheduler implements ReminderScheduler {
  @override
  Future<void> schedule(Reminder reminder) => throw StateError('falha simulada do agendador');

  @override
  Future<void> cancel(int reminderId) => throw StateError('falha simulada do agendador');
}

/// Duplo de [ReminderStore] que lê normalmente (delega a um
/// [_InMemoryReminderStore] real) mas lança em toda escrita — simula, por
/// exemplo, o disco cheio ou uma falha do SQLite em dispositivo real.
class _ThrowingReminderStore implements ReminderStore {
  _ThrowingReminderStore(this._delegate);

  final ReminderStore _delegate;

  @override
  Future<List<Reminder>> list() => _delegate.list();

  @override
  Future<Reminder> save(Reminder reminder) => throw StateError('falha simulada do store');

  @override
  Future<void> delete(int id) => throw StateError('falha simulada do store');
}

/// Duplo de [ConsentPreferences] com resposta fixa — por padrão simula
/// consentimento concedido, o cenário que os testes existentes de
/// `RemindersScreen` (criados antes deste consentimento existir) já
/// assumem implicitamente.
class _FixedConsentPreferences implements ConsentPreferences {
  _FixedConsentPreferences({this.granted = true});

  bool? granted;

  @override
  Future<bool?> localRemindersGranted() async => granted;

  @override
  Future<void> saveLocalRemindersConsent(bool value) async => granted = value;
}

/// Duplo de [LocationReader] com leitura fixa, para testar como a tela reage
/// a cada estado sem depender de canal de plataforma (GPS real).
class _FixedLocationReader implements LocationReader {
  _FixedLocationReader(this.reading);

  final LocationReading reading;
  int calls = 0;

  @override
  Future<LocationReading> read({Duration timeout = const Duration(seconds: 8)}) async {
    calls++;
    return reading;
  }
}

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

/// Percorre o login passwordless inteiro (RF01): credenciais, pedido do código
/// e verificação. É o mesmo ponto de entrada que os testes usavam quando a
/// tela era um `developmentLogin` de um toque só.
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

void main() {
  testWidgets('deve autenticar no backend antes de abrir a triagem', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      locationReader: _FixedLocationReader(
        const LocationUnavailable(LocationUnavailableReason.unknown),
      ),
    ));

    expect(find.text('SinalACS'), findsOneWidget);
    expect(find.text('Acesso sem senha'), findsOneWidget);

    await login(tester);

    expect(backend.otpVerifications, hasLength(1));
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('não deve avançar quando a autenticação falha', (tester) async {
    final handle = tester.ensureSemantics();
    final backend = FakePatientBackend(
      verifyOtpFailure: const BackendFailure('Sem conexão com o servidor.'),
    );
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await login(tester);

    // A tela antiga navegava incondicionalmente; a regressão que este teste
    // protege é justamente entrar no app sem ter falado com o servidor.
    expect(find.text('Triagem rápida'), findsNothing);
    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
    // SC 4.1.3: o erro aparece sem mover o foco — sem `liveRegion` um leitor
    // de tela nunca saberia que o login falhou.
    final semantics = tester.getSemantics(find.byKey(const Key('login_error')));
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
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
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      locationReader: _FixedLocationReader(
        const LocationUnavailable(LocationUnavailableReason.unknown),
      ),
    ));

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

  testWidgets('deve anexar o hash e a célula de localização quando a permissão é concedida', (tester) async {
    final backend = FakePatientBackend();
    final locationReader =
        _FixedLocationReader(const LocationAvailable('abc123456789', '-2356:-4664'));
    await tester.pumpWidget(SinalAcsApp(backend: backend, locationReader: locationReader));

    await login(tester);
    await tester.tap(find.text('Urgência'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('panic_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar alerta'));
    await tester.pumpAndSettle();

    expect(locationReader.calls, 1);
    expect(backend.locationHashes.single, 'abc123456789');
    expect(backend.locationCells.single, '-2356:-4664');
    expect(find.text('Localização anexada ao alerta.'), findsOneWidget);
  });

  for (final reason in LocationUnavailableReason.values) {
    testWidgets(
      'deve enviar o alerta com hash desconhecido e avisar a pessoa quando a localização está indisponível '
      '(${reason.name})',
      (tester) async {
        final backend = FakePatientBackend();
        final locationReader = _FixedLocationReader(LocationUnavailable(reason));
        await tester.pumpWidget(SinalAcsApp(backend: backend, locationReader: locationReader));

        await login(tester);
        await tester.tap(find.text('Urgência'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('panic_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar alerta'));
        await tester.pumpAndSettle();

        // Alerta vermelho nunca pode ser perdido em silêncio por falta de
        // GPS: precisa ter sido enviado mesmo assim.
        expect(backend.locationHashes.single, unknownLocationHash);
        // Sem leitura de GPS não há célula para desenhar no mapa do ACS.
        expect(backend.locationCells.single, isNull);
        expect(find.text('Alerta recebido pela equipe'), findsOneWidget);
        // A UI precisa dizer isso explicitamente — nunca mascarar como se
        // uma coordenada válida tivesse sido usada.
        expect(
          find.text('Localização indisponível — o alerta será enviado mesmo assim.'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('o estado do alerta de emergência é anunciado ao leitor de tela', (tester) async {
    // É a confirmação de que o alerta chegou à equipe — o ponto mais crítico
    // do app para um leitor de tela anunciar sem depender de a pessoa
    // varrer a tela de novo.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      locationReader: _FixedLocationReader(
        const LocationUnavailable(LocationUnavailableReason.unknown),
      ),
    ));

    await login(tester);
    await tester.tap(find.text('Urgência'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('panic_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar alerta'));
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.text('Alerta recebido pela equipe'));
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('o botão de EMERGÊNCIA é UM nó, com o texto visível e a ação de toque', (tester) async {
    // WCAG 2.5.3 + 4.1.2 no controle mais crítico do app. Um `Semantics` em
    // volta de um botão de verdade não funde com ele: cria um nó próprio, com
    // papel de botão e sem ação, anunciado ANTES do botão real — o leitor de
    // tela encontrava primeiro um "botão" que não faz nada, de largura total.
    // `MergeSemantics` funde os dois: um nó só, com o texto visível dentro do
    // nome acessível, e a ação de toque.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      locationReader: _FixedLocationReader(
        const LocationUnavailable(LocationUnavailableReason.unknown),
      ),
    ));

    await login(tester);
    await tester.tap(find.text('Urgência'));
    await tester.pumpAndSettle();

    // A varredura vem primeiro de propósito: é ela que separa o defeito da
    // correção. As três asserções abaixo descrevem a forma corrigida, mas são
    // verdes com o defeito também (o nó do botão, sozinho, já responde ao toque
    // e já carrega o texto visível) — quem acusa o nó inerte é a varredura.
    expectNenhumBotaoInerte(tester);

    // `getSemantics` sobe enquanto o nó estiver mesclado, então com o
    // `MergeSemantics` este é o nó fundido — o mesmo que o leitor de tela lê.
    final noEmergencia = tester.getSemantics(find.byKey(const Key('panic_button')));
    final emergencia = noEmergencia.getSemanticsData();
    // Literalmente o texto visível, não uma variação de caixa: é o que o 2.5.3
    // exige, por qualquer leitura, sem depender de comparação case-insensitive.
    expect(emergencia.label, contains('EMERGÊNCIA'));
    // A frase descritiva continua no nome acessível.
    expect(emergencia.label, contains('Enviar alerta de emergência'));
    expect(emergencia.hasAction(SemanticsAction.tap), isTrue);
    // Um nó só, com a moldura do botão: com o defeito a moldura do nó sem ação
    // era a área de largura total do wrapper (752 de largura, medidos pela
    // varredura), e não os 208x208 do alvo de toque.
    expect(noEmergencia.rect.size, const Size(208, 208));
    handle.dispose();
  });

  testWidgets('deve expor rótulo semântico e alvo de toque acessível no fluxo do paciente', (tester) async {
    // `getSemantics` abaixo só acha nó com a árvore semântica ligada.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));

    final enterButton = tester.widget<FilledButton>(find.byKey(const Key('enter_button')));
    final minimumSize = enterButton.style?.minimumSize?.resolve({}) ?? const Size(0, 0);

    // WCAG 2.5.3 (Label in Name, nível A): o nome acessível é o texto visível do
    // botão, exposto pelo próprio botão — o `Semantics` que existia aqui com o
    // rótulo "Entrar na triagem do paciente" não fundia com ele, e sim criava um
    // segundo nó, sem ação de toque, anunciado ANTES do botão real (WCAG 4.1.2).
    //
    // Com `String`, `bySemanticsLabel` casa por **igualdade exata**
    // (`finders.dart`: `pattern == propertyValue`), não por *contains*: igualdade
    // é mais forte do que contenção, então a asserção vale — mas quem
    // acrescentar algo ao texto visível ("Entrar sem senha agora") vê esta linha
    // falhar mesmo com o rótulo contendo o texto. Com `RegExp` o finder casa por
    // `hasMatch`.
    expect(find.bySemanticsLabel('Entrar sem senha'), findsOneWidget);
    expect(find.bySemanticsLabel('Entrar na triagem do paciente'), findsNothing);
    // A varredura substitui a asserção de `tap` que ficava aqui. Aquela era
    // verde também com o defeito — nela, o nó que carrega o nome é justamente o
    // inerte, e o que responde ao toque é o filho — e prendia um invariante
    // ("o nó que carrega o nome do botão tem de ser o que responde ao toque")
    // que ela não testava. A varredura prende a classe, na árvore inteira.
    expectNenhumBotaoInerte(tester);

    expect(minimumSize.height, greaterThanOrEqualTo(48));
    expect(minimumSize.width, greaterThanOrEqualTo(48));
    handle.dispose();
  });

  testWidgets('a tela de login atende às diretrizes de contraste e alvo de toque do Flutter', (tester) async {
    // Substitui a auditoria manual no WebAIM/TalkBack do relatório anterior
    // por uma verificação determinística que o CI roda sozinho.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('a varredura de nós inertes detecta o que promete detectar', () {
    // Sem isto, a varredura poderia estar olhando uma árvore que não montou e
    // passando para todo mundo — o mesmo modo de falha silenciosa que ela
    // existe para pegar. O app admin guarda o detector de overflow dele do
    // mesmo jeito (`layout_harness_sanity_test.dart`).
    testWidgets('acusa o "botão" sem ação de toque', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Semantics(
            label: 'Rótulo de botão',
            button: true,
            child: SizedBox(
              width: 200,
              height: 60,
              child: FilledButton(onPressed: () {}, child: const Text('Visível')),
            ),
          ),
        ),
      ));

      final achados = botoesInertes(tester);
      expect(achados, hasLength(1));
      expect(achados.single, contains('Rótulo de botão'));
      handle.dispose();
    });

    testWidgets('não acusa controle legitimamente desabilitado', (tester) async {
      // `onPressed: null` também é `isButton` sem ação de toque, mas declara
      // `isEnabled: false` e o leitor de tela anuncia "desativado". Uma
      // varredura que acusasse isto apontaria defeito em toda tela com um botão
      // desabilitado — e seria apagada.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: FilledButton(onPressed: null, child: Text('Indisponível agora'))),
      ));

      expect(botoesInertes(tester), isEmpty);
      handle.dispose();
    });

    testWidgets('não passa em silêncio quando não há o que medir', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

      expect(() => botoesInertes(tester), throwsA(isA<TestFailure>()));
      handle.dispose();
    });
  });

  group('Lembretes locais (RF06)', () {
    Widget buildRemindersScreen(
      ReminderStore store,
      ReminderScheduler scheduler, {
      ConsentPreferences? consentPreferences,
    }) {
      return MaterialApp(
        home: RemindersScope(
          store: store,
          scheduler: scheduler,
          consentPreferences: consentPreferences ?? _FixedConsentPreferences(),
          child: const PatientHomeShell(initialDestination: PatientDestination.reminders),
        ),
      );
    }

    testWidgets('abre vazia quando não há lembretes cadastrados (sem lista fixa de exemplo)', (tester) async {
      await tester.pumpWidget(buildRemindersScreen(_InMemoryReminderStore(), _RecordingReminderScheduler()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reminders_empty_state')), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('criar um lembrete grava no store e agenda a notificação', (tester) async {
      final store = _InMemoryReminderStore();
      final scheduler = _RecordingReminderScheduler();
      await tester.pumpWidget(buildRemindersScreen(store, scheduler));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reminders_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reminder_label_field')), 'Losartana 50 mg');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminder_save_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reminders_empty_state')), findsNothing);
      expect(find.textContaining('Losartana 50 mg'), findsOneWidget);

      final saved = await store.list();
      expect(saved, hasLength(1));
      expect(scheduler.scheduled, [saved.single.id]);
    });

    testWidgets('alternar o switch active grava a mudança e agenda/cancela de acordo', (tester) async {
      final store = _InMemoryReminderStore();
      final seeded = await store.save(
        const Reminder(id: 0, label: 'Metformina 850 mg', hour: 7, minute: 0, active: true),
      );
      final scheduler = _RecordingReminderScheduler();
      await tester.pumpWidget(buildRemindersScreen(store, scheduler));
      await tester.pumpAndSettle();

      final switchKey = Key('reminder_switch_${seeded.id}');
      expect(find.text('Ativo'), findsOneWidget);

      await tester.tap(find.byKey(switchKey));
      await tester.pumpAndSettle();

      expect(find.text('Pausado'), findsOneWidget);
      expect(scheduler.cancelled, [seeded.id]);
      final afterToggleOff = await store.list();
      expect(afterToggleOff.single.active, isFalse);

      await tester.tap(find.byKey(switchKey));
      await tester.pumpAndSettle();

      expect(find.text('Ativo'), findsOneWidget);
      expect(scheduler.scheduled, [seeded.id]);
      final afterToggleOn = await store.list();
      expect(afterToggleOn.single.active, isTrue);
    });

    testWidgets('excluir um lembrete remove do store e cancela a notificação', (tester) async {
      final store = _InMemoryReminderStore();
      final seeded = await store.save(
        const Reminder(id: 0, label: 'Pesagem de rotina', hour: 9, minute: 0, active: true),
      );
      final scheduler = _RecordingReminderScheduler();
      await tester.pumpWidget(buildRemindersScreen(store, scheduler));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('reminder_delete_${seeded.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reminders_empty_state')), findsOneWidget);
      expect(await store.list(), isEmpty);
      expect(scheduler.cancelled, [seeded.id]);
    });

    group('tratamento de erro nas escritas', () {
      testWidgets('falha do store ao salvar (toggle) mostra erro inline e não corrompe a lista', (tester) async {
        final inner = _InMemoryReminderStore();
        final seeded = await inner.save(
          const Reminder(id: 0, label: 'Metformina 850 mg', hour: 7, minute: 0, active: false),
        );
        final store = _ThrowingReminderStore(inner);
        await tester.pumpWidget(buildRemindersScreen(store, _RecordingReminderScheduler()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('reminder_switch_${seeded.id}')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_error')), findsOneWidget);
        // A escrita falhou antes de qualquer `setState`: a tela continua
        // mostrando o estado anterior (persistido), não uma mudança fantasma.
        expect(find.text('Pausado'), findsOneWidget);
        expect(find.text('Ativo'), findsNothing);
      });

      testWidgets('falha do agendador ao agendar (criar) mostra erro inline e não insere na lista', (tester) async {
        final store = _InMemoryReminderStore();
        await tester.pumpWidget(buildRemindersScreen(store, _ThrowingReminderScheduler()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('reminders_add_button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('reminder_label_field')), 'Losartana 50 mg');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reminder_save_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_error')), findsOneWidget);
        // O store já gravou (a exceção veio do agendador, chamado depois),
        // mas a tela não atualizou a lista local — sem exceção não tratada,
        // sem lista incoerente exibida.
        expect(find.textContaining('Losartana 50 mg'), findsNothing);
        expect(find.byKey(const Key('reminders_empty_state')), findsOneWidget);
      });

      testWidgets('falha do agendador ao cancelar (excluir) mostra erro inline e mantém o lembrete visível', (tester) async {
        final store = _InMemoryReminderStore();
        final seeded = await store.save(
          const Reminder(id: 0, label: 'Pesagem de rotina', hour: 9, minute: 0, active: true),
        );
        await tester.pumpWidget(buildRemindersScreen(store, _ThrowingReminderScheduler()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('reminder_delete_${seeded.id}')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_error')), findsOneWidget);
        // O cancelamento no agendador falhou depois de o store já ter
        // apagado o registro; a tela não removeu o item da lista exibida
        // (evita a pessoa achar que o lembrete sumiu quando a notificação
        // agendada pode continuar ativa no aparelho).
        expect(find.byKey(Key('reminder_tile_${seeded.id}')), findsOneWidget);
      });
    });

    group('consentimento recusado (LGPD)', () {
      testWidgets('recusa registrada bloqueia a criação e nunca chama o agendador', (tester) async {
        final store = _InMemoryReminderStore();
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: false),
        ));
        await tester.pumpAndSettle();

        final addButton = tester.widget<IconButton>(find.byKey(const Key('reminders_add_button')));
        expect(addButton.onPressed, isNull);

        expect(find.byKey(const Key('reminders_consent_denied_banner')), findsOneWidget);
        expect(scheduler.scheduled, isEmpty);
        expect(await store.list(), isEmpty);
      });

      testWidgets('recusa registrada bloqueia reativar um lembrete existente', (tester) async {
        final store = _InMemoryReminderStore();
        final seeded = await store.save(
          const Reminder(id: 0, label: 'Metformina 850 mg', hour: 7, minute: 0, active: false),
        );
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: false),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('reminder_switch_${seeded.id}')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_error')), findsOneWidget);
        expect(scheduler.scheduled, isEmpty);
        final after = await store.list();
        expect(after.single.active, isFalse);
      });

      testWidgets('consentimento concedido continua permitindo criar e agendar normalmente', (tester) async {
        final store = _InMemoryReminderStore();
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: true),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_consent_denied_banner')), findsNothing);

        await tester.tap(find.byKey(const Key('reminders_add_button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('reminder_label_field')), 'Losartana 50 mg');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reminder_save_button')));
        await tester.pumpAndSettle();

        final saved = await store.list();
        expect(saved, hasLength(1));
        expect(scheduler.scheduled, [saved.single.id]);
      });

      testWidgets('sem registro local de consentimento, trata como recusa mas avisa para concluir o cadastro', (tester) async {
        final store = _InMemoryReminderStore();
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: null),
        ));
        await tester.pumpAndSettle();

        final addButton = tester.widget<IconButton>(find.byKey(const Key('reminders_add_button')));
        expect(addButton.onPressed, isNull);
        expect(find.textContaining('Não encontramos seu consentimento'), findsOneWidget);
        expect(find.textContaining('Você recusou'), findsNothing);
        expect(scheduler.scheduled, isEmpty);
      });

      testWidgets('carregar a tela sem consentimento cancela lembretes já ativos (revogação efetiva)', (tester) async {
        final store = _InMemoryReminderStore();
        final seeded = await store.save(
          const Reminder(id: 0, label: 'Metformina 850 mg', hour: 7, minute: 0, active: true),
        );
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: false),
        ));
        await tester.pumpAndSettle();

        expect(scheduler.cancelled, [seeded.id]);
        final after = await store.list();
        expect(after.single.active, isFalse);
        expect(find.text('Pausado'), findsOneWidget);
      });
    });
  });

  group('Status da solicitação (RF05)', () {
    testWidgets('sem alerta disparado, mostra que não há solicitação — não mais o ticket falso', (tester) async {
      final backend = FakePatientBackend();
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      await login(tester);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(backend.statusForCallCount, 1);
      expect(find.byKey(const Key('status_empty')), findsOneWidget);
      expect(find.text('Nenhuma solicitação registrada ainda.'), findsOneWidget);
      expect(find.textContaining('Solicitação de visita #4082'), findsNothing);
    });

    testWidgets('mostra o status real devolvido pelo servidor', (tester) async {
      final backend = FakePatientBackend()
        ..statusResult = AlertStatusResult(
          found: true,
          alertId: 'alerta-1',
          riskLevel: RiskLevel.red,
          status: AlertStatus.acknowledged,
          triggeredAt: DateTime.utc(2026, 9, 18, 9),
          acknowledgedAt: DateTime.utc(2026, 9, 18, 9, 5),
        );
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      await login(tester);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(find.text('Risco: Vermelho'), findsOneWidget);
      expect(find.text('Recebido pela equipe de saúde'), findsOneWidget);
    });

    testWidgets('uma falha ao consultar mostra o aviso, sem travar o botão de tentar de novo', (tester) async {
      final backend = FakePatientBackend()
        ..statusFailure = const BackendFailure('Sem conexão com o servidor.');
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      await login(tester);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('status_error')), findsOneWidget);
      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('refresh_status'))).onPressed,
        isNotNull,
      );
    });

    testWidgets('"Verificar status agora" repete a consulta manualmente', (tester) async {
      final backend = FakePatientBackend();
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      await login(tester);
      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();
      expect(backend.statusForCallCount, 1);

      await tester.tap(find.byKey(const Key('refresh_status')));
      await tester.pumpAndSettle();
      expect(backend.statusForCallCount, 2);
    });
  });

  group('sincronização periódica em segundo plano (RF05)', () {
    Widget buildStatusScreen(FakePatientBackend backend, {required Duration syncInterval}) {
      return MaterialApp(
        home: BackendScope(
          backend: backend,
          child: StatusScreen(syncInterval: syncInterval),
        ),
      );
    }

    testWidgets('repete a consulta de status em intervalos, sem toque manual', (tester) async {
      final backend = FakePatientBackend();
      await tester.pumpWidget(buildStatusScreen(backend, syncInterval: const Duration(seconds: 10)));
      await tester.pumpAndSettle();

      expect(backend.statusForCallCount, 1);

      await tester.pump(const Duration(seconds: 10));
      expect(backend.statusForCallCount, 2);

      await tester.pump(const Duration(seconds: 10));
      expect(backend.statusForCallCount, 3);
    });

    testWidgets('sair do primeiro plano cancela o ciclo; voltar consulta na hora e recomeça', (tester) async {
      final backend = FakePatientBackend();
      await tester.pumpWidget(buildStatusScreen(backend, syncInterval: const Duration(seconds: 10)));
      await tester.pumpAndSettle();
      expect(backend.statusForCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(backend.statusForCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.statusForCallCount, 2);

      await tester.pump(const Duration(seconds: 10));
      expect(backend.statusForCallCount, 3);
    });
  });
}
