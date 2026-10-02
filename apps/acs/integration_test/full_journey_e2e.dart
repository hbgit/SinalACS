/// Jornada completa do ACS contra o BANCO DE TESTE, pela tela, com login
/// institucional real (RF07): senha errada, seletor de pacientes restrito à
/// microárea (RNF06) e visita sincronizada, conferida no servidor. Rodada por
/// `scripts/qa/acs_full_e2e.sh`.
///
/// NÃO cobre MQTT/ACK: o `aclfile` do broker só libera o UUID de microárea do
/// seed de desenvolvimento e as fixtures daqui são aleatórias, então o broker
/// nega o ACS. O alerta pelo broker é provado por `smoke_test.dart` e
/// `red_alert_cycle_test.dart` na stack de desenvolvimento.
///
/// Sufixo `_e2e.dart` (não `_test.dart`): `flutter test integration_test`
/// descobre `*_test.dart` por pasta e o `e2e.sh --full` rodaria isto contra a
/// stack de desenvolvimento, onde não há fixtures nem relé.
///
/// PRIVACIDADE: só fixtures sintéticas geradas na execução; nada de CPF em log.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(done(), isTrue, reason: 'condição não atingida em ${timeout.inSeconds}s');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login real, seletor por microárea, visita e sincronização', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    const host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    api.Client novoCliente() => api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    final outsider = e2ePatient('outsider');

    await tester.pumpWidget(SinalAcsApp(backend: backend));

    // Review Focus 4 — senha errada: erro visível, painel fechado.
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), '${cred.senha}-errada');
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('login_error')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não pode abrir');

    // A sessão certa logo depois funciona, sem reiniciar.
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('login_button')).evaluate().isEmpty);

    // Visita de rotina pelo seletor: o paciente da microárea aparece; o de fora, não (RNF06).
    await tester.tap(find.text('Visita'));
    await _pumpUntil(tester, () => find.byKey(const Key('patient_picker')).evaluate().isNotEmpty);
    expect(find.byKey(Key('patient_${main.id}')), findsOneWidget);
    expect(find.byKey(Key('patient_${outsider.id}')), findsNothing, reason: 'outra microárea');

    await tester.tap(find.byKey(Key('patient_${main.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('arrival_confirmation')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_visit')));
    await _pumpUntil(tester, () => find.text('Pendentes de sincronização: 1').evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('sync_visits')));
    await _pumpUntil(tester, () => find.text('Pendentes de sincronização: 0').evaluate().isNotEmpty);

    // A visita está NO SERVIDOR (conferida por um cliente separado, com login real).
    final acsClient = novoCliente();
    addTearDown(acsClient.close);
    final acs = await acsClient.auth.loginInstitutional(matricula: cred.matricula, password: cred.senha);
    final remotas = await acsClient.visits.pull(
      accessToken: acs.accessToken,
      since: DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(remotas.any((v) => v.patientId == main.id), isTrue);

    // Desmonta o app aqui: o feed e os timers do painel ainda estão ativos e o
    // desmonte automático do fim do teste os pegava em meio ao descarte.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
