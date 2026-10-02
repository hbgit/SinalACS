import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar, irParaDaBarra;

const _aviso = 'Sua sessão expirou. Entre novamente com o código do autenticador.';

/// Sessão vencida com MFA: a reautenticação é empilhada SOBRE o painel. Nada do
/// que o painel guarda em memória (alertas já entregues por MQTT, formulário,
/// fila de visitas) pode se perder — um alerta vermelho nunca some em silêncio.
void main() {
  late FakeAcsBackend backend;
  late FakeAlertFeed feed;
  late OfflineVisitQueue fila;

  Future<void> abrir(WidgetTester tester) async {
    backend = FakeAcsBackend()
      ..expectedTotpCode = '123456'
      ..patients = [
        MicroAreaPatient(patientId: syntheticPatientId(5), name: 'Fulano de Tal', isChronic: false, chronicConditions: const []),
      ];
    fila = OfflineVisitQueue();
    await fila.add(OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'));
    await tester.pumpWidget(SinalAcsApp(backend: backend, visitQueue: fila, feedBuilder: (q) => feed = FakeAlertFeed(q)));
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
    await _digitarCodigo(tester);
    expect(find.byKey(const Key('login_button')), findsNothing, reason: 'o painel abriu');
    feed.deliver(testAlert(alertId: 'alerta-vermelho'));
    await assentar(tester);
    expect(find.byKey(const Key('alert_alerta-vermelho')), findsOneWidget);
  }

  testWidgets('(a) a sessão expira: login empilhado, e o alerta continua na fila sem confirmação', (tester) async {
    await abrir(tester);

    backend.expireSession();
    await assentar(tester);
    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.text(_aviso), findsOneWidget);

    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
    await _digitarCodigo(tester);

    expect(find.byKey(const Key('login_button')), findsNothing, reason: 'voltou ao painel');
    expect(find.byKey(const Key('alert_alerta-vermelho')), findsOneWidget);
    expect(find.text('Confirmar recebimento'), findsOneWidget, reason: 'segue sem confirmação');
    expect(backend.acknowledgedAlertIds, isEmpty);
    expect(fila.pendingCount, 1);
  });

  testWidgets('(b) confirmar depois de expirar mostra a mensagem e o alerta segue sem confirmação', (tester) async {
    await abrir(tester);
    backend.sessionExpired = true; // vence sem avisar a UI: o aviso vem da própria chamada

    await tester.tap(find.text('Confirmar recebimento'));
    await assentar(tester);

    expect(find.text(_aviso), findsWidgets, reason: 'mensagem visível (tela de reautenticação)');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(backend.acknowledgedAlertIds, isEmpty);

    // A mensagem cobre o rodapé da tela de login: dispensa para tocar no botão.
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('login_button')))).hideCurrentSnackBar();
    await assentar(tester);
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
    await _digitarCodigo(tester);
    expect(find.text('Confirmar recebimento'), findsOneWidget, reason: 'o alerta não sumiu nem foi confirmado');
  });

  testWidgets('(c) o formulário de visita pela metade sobrevive à reautenticação', (tester) async {
    await abrir(tester);
    await irParaDaBarra(tester, 'Visita');
    await tester.enterText(find.byKey(const Key('patient_search')), 'busca em andamento');
    await tester.pump();

    backend.expireSession();
    await assentar(tester);
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
    await _digitarCodigo(tester);

    expect(tester.widget<TextField>(find.byKey(const Key('patient_search'))).controller!.text, 'busca em andamento');
  });

  testWidgets('(d) outro usuário entra: a fila do anterior não é mantida', (tester) async {
    await abrir(tester);
    backend.expireSession();
    await assentar(tester);
    backend.nextUserId = '00000000-0000-4000-8000-0000000000ff';

    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-002');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
    await _digitarCodigo(tester);

    expect(find.byKey(const Key('login_button')), findsNothing, reason: 'painel novo aberto');
    expect(find.byKey(const Key('alert_alerta-vermelho')), findsNothing, reason: 'RNF06: nada do usuário anterior');
  });

  testWidgets('(e) duas expirações seguidas empilham uma única reautenticação', (tester) async {
    await abrir(tester);

    backend.expireSession();
    backend.expireSession();
    await assentar(tester);

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    // Um único `pop` volta ao painel: só havia uma rota por cima.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await assentar(tester);
    expect(find.byKey(const Key('login_button')), findsNothing);
  });
}

/// Depois de matrícula e senha o fake pede o código: digita e entra.
Future<void> _digitarCodigo(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('totp_field')), '123456');
  await tester.tap(find.byKey(const Key('login_button')));
  await assentar(tester);
}
