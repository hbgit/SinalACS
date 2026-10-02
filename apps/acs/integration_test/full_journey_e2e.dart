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
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';
import 'support/totp.dart';

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
    // O seletor não pode estar filtrado: sem isto, "o de fora não aparece"
    // poderia ser só um filtro por nome escondendo tudo o que não casa.
    final busca = tester.widget<TextField>(find.byKey(const Key('patient_search')));
    expect(busca.controller!.text, isEmpty, reason: 'o seletor deve abrir sem filtro de busca');
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

    // RNF06 no servidor: a lista da microárea nunca traz o paciente de fora.
    // Quem garante é o backend, não o filtro do seletor.
    final daMicroarea = await acsClient.patients.listMicroArea(accessToken: acs.accessToken);
    expect(daMicroarea.any((p) => p.patientId == main.id), isTrue);
    expect(daMicroarea.any((p) => p.patientId == outsider.id), isFalse, reason: 'outra microárea');
    // RF13: o contato da UBS chega pelo servidor real, escopado pelo token do ACS.
    final contato = await acsClient.ubs.myContact(accessToken: acs.accessToken);
    expect(contato.name, 'UBS E2E');
    expect(contato.phone, '+55 11 5550-0199');

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

  testWidgets('100 visitas offline sobem em menos de 5 s (M2.4)', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    await backend.login(matricula: cred.matricula, senha: cred.senha);

    final fila = OfflineVisitQueue(synchronizer: BackendVisitSynchronizer(backend: backend));
    final base = DateTime.now().toUtc().subtract(const Duration(days: 1));
    for (var n = 0; n < 100; n++) {
      // `localId` fica no padrão (um UUID novo): o protocolo o tipa como
      // `UuidValue` e o servidor recusa o que não for UUID.
      await fila.add(OfflineVisitRecord(
        patientId: main.id,
        risk: 'green',
        status: 'PENDENTE',
        createdAt: base.add(Duration(minutes: n)),
      ));
    }
    final enviados = {for (final v in fila.pendingVisits) v.localId.toLowerCase()};
    expect(enviados, hasLength(100));

    final relogio = Stopwatch()..start();
    final resultado = await fila.sync();
    relogio.stop();

    expect(resultado.kind, SyncOutcomeKind.synced, reason: resultado.message);
    expect(fila.syncedCount, 100);
    expect(fila.pendingCount, 0);
    // ignore: avoid_print
    print('rajada: 100 visitas em ${relogio.elapsedMilliseconds} ms');
    expect(relogio.elapsed, lessThan(const Duration(seconds: 5)),
        reason: 'PRD M2.4: 100 registros offline sincronizam em < 5 s');

    final remotas = await backend.pullVisits(since: DateTime.fromMillisecondsSinceEpoch(0));
    final noServidor = {for (final v in remotas) v.localId.toString().toLowerCase()};
    expect(noServidor.containsAll(enviados), isTrue,
        reason: 'as 100 visitas estão no servidor, conferidas por pull');
  });

  testWidgets('RF08: a microárea fica no aparelho, sobrevive à queda de rede e está cifrada', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    await backend.login(matricula: cred.matricula, senha: cred.senha);

    // O `keyStore` de PRODUÇÃO (Keystore do aparelho), numa base própria deste teste.
    await EncryptedLocalDatabase.deleteDatabaseFile('rf08_e2e.db');
    final store = MicroAreaCacheStore(keyStore: SecureStorageDatabaseKeyStore(), databaseName: 'rf08_e2e.db');
    final online = MicroAreaDirectory(fetch: backend.listPatients, session: () => backend.session, store: store);
    final primeira = await online.load();
    expect(primeira.fromCache, isFalse);
    expect(primeira.patients.any((p) => p.patientId == main.id), isTrue);

    // Rede caída: a central "não responde", o aparelho serve o que guardou.
    final offline = MicroAreaDirectory(
      fetch: () async => throw const BackendFailure('Sem conexão.'),
      session: () => backend.session,
      store: store,
    );
    final segunda = await offline.load();
    expect(segunda.fromCache, isTrue);
    expect(segunda.patients.any((p) => p.patientId == main.id), isTrue);

    // O arquivo no disco NÃO contém o nome do paciente em texto claro (SQLCipher no aparelho).
    final bytes = await File(await EncryptedLocalDatabase.pathFor('rf08_e2e.db')).readAsBytes();
    expect(String.fromCharCodes(bytes).contains(main.name), isFalse,
        reason: 'o nome do paciente não pode estar legível no arquivo do banco');
    expect(String.fromCharCodes(bytes.take(16)), isNot(startsWith('SQLite format 3')));
    await store.clear();
  });

  testWidgets('MFA: com a verificação ativa, o login pela tela pede e aceita o código', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    const host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    final cliente = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(cliente.close);
    final cred = await acsCredentialFromRelay();

    // 1) Liga a MFA pelo RPC: matrícula + senha + o código do segredo recém-sorteado.
    final inicio = await cliente.auth.beginTotpEnrollment(matricula: cred.matricula, password: cred.senha);
    final segredo = base32Decode(inicio.secretBase32);
    await cliente.auth.confirmTotpEnrollment(
      matricula: cred.matricula,
      password: cred.senha,
      code: totpCode(segredo, DateTime.now()),
    );

    // 2) Login pela tela: matrícula + senha -> o app pede o código e o painel NÃO abre.
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('totp_field')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não pode abrir sem o código');

    // 3) O código da ativação já foi usado (replay barrado): entra com o do PASSO SEGUINTE,
    //    que a janela de ±1 aceita.
    await tester.enterText(
      find.byKey(const Key('totp_field')),
      totpCode(segredo, DateTime.now().add(const Duration(seconds: 30))),
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () =>
        find.byKey(const Key('login_button')).evaluate().isEmpty || find.byKey(const Key('login_error')).evaluate().isNotEmpty);
    final erro = find.byKey(const Key('login_error'));
    expect(erro, findsNothing, reason: erro.evaluate().isEmpty ? '' : (tester.widget<Text>(erro).data ?? ''));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
