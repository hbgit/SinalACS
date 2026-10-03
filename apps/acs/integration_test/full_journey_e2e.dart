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
/// O último teste (MFA) também prova o refresh token no aparelho: o login com
/// TOTP deixa o token no Keystore, a renovação rotaciona sem tela de
/// reautenticação e a partida a frio retoma a sessão sem senha. Por padrão a
/// renovação é forçada por `renewSession()`; com
/// `--dart-define=E2E_ESPERAR_JWT=true` (`acs_full_e2e.sh --esperar-jwt`) o
/// teste espera o JWT de 15 min vencer de verdade e a renovação sai de uma
/// chamada autenticada comum. O `audit_logs` (`refresh_granted`) e as linhas de
/// `acs_refresh_tokens` são conferidos pelo script, no banco.
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
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';
import 'support/totp.dart';

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 30), Duration step = const Duration(milliseconds: 200)}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(step);
  }
  if (done()) return;
  // O que a tela diz quando trava: sem isto a falha é só "condição não atingida".
  final telas = <String>[
    for (final k in const ['login_error', 'login_aviso', 'resume_offline', 'resume_progress'])
      if (find.byKey(Key(k)).evaluate().isNotEmpty)
        '$k=${find.descendant(of: find.byKey(Key(k)), matching: find.byType(Text), matchRoot: true).evaluate().map((e) => (e.widget as Text).data).join(' ')}',
  ];
  fail('condição não atingida em ${timeout.inSeconds}s; tela: ${telas.isEmpty ? '(nada)' : telas.join('; ')}');
}

/// Toca "Entrar". O teclado virtual aberto pelo `enterText` encolhe a área
/// visível e o botão, no fim do `ListView`, fica fora dela: o toque cairia no
/// fundo do formulário (o `flutter test` só avisa "would not hit test").
Future<void> _tocarEntrar(WidgetTester tester) async {
  final botao = find.byKey(const Key('login_button'));
  await tester.ensureVisible(botao);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(botao);
}

/// Espera o JWT vencer de verdade (15 min) em vez de forçar a renovação.
const _esperarJwt = bool.fromEnvironment('E2E_ESPERAR_JWT');

/// Desbloqueio local de teste. O padrão é "indisponível": sem ele, um aparelho
/// com PIN/digital cadastrado abriria o `BiometricPrompt` real na partida (há
/// refresh token de um teste anterior no Keystore) e a tela de login ficaria
/// travada em "Retomando a sessão…". O desbloqueio real é provado à parte, por
/// adb (ver o relatório da Task 8).
class _DesbloqueioDeTeste implements BiometricGate {
  _DesbloqueioDeTeste({this.available = false});
  final bool available;
  int calls = 0;
  @override
  Future<bool> get isAvailable async => available;
  @override
  Future<UnlockResult> authenticate({required String reason}) async {
    calls++;
    return available ? UnlockResult.unlocked : UnlockResult.unavailable;
  }
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

    await tester.pumpWidget(SinalAcsApp(backend: backend, biometricGate: _DesbloqueioDeTeste()));

    // Review Focus 4 — senha errada: erro visível, painel fechado.
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), '${cred.senha}-errada');
    await _tocarEntrar(tester);
    await _pumpUntil(tester, () => find.byKey(const Key('login_error')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não pode abrir');

    // A sessão certa logo depois funciona, sem reiniciar.
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    await _tocarEntrar(tester);
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

  testWidgets('MFA: com a verificação ativa, o login pela tela pede e aceita o código; '
      'o refresh token renova sem reautenticação e retoma a sessão na partida', (tester) async {
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
    int passo(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;
    final passoDaAtivacao = passo(DateTime.now());
    await cliente.auth.confirmTotpEnrollment(
      matricula: cred.matricula,
      password: cred.senha,
      code: totpCode(segredo, DateTime.now()),
    );

    // 2) Login pela tela: matrícula + senha -> o app pede o código e o painel NÃO abre.
    //    `syncInterval` longo: nada renova a sessão por conta própria durante a
    //    espera do passo 4; quem renova é a chamada do passo 5.
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      biometricGate: _DesbloqueioDeTeste(),
      syncInterval: const Duration(hours: 2),
    ));
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    await _tocarEntrar(tester);
    await _pumpUntil(tester, () => find.byKey(const Key('totp_field')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não pode abrir sem o código');

    // 3) O código da ativação já foi usado (replay barrado). Espera o relógio do
    //    aparelho passar para um passo MAIOR que o da ativação e entra com o código
    //    do passo ATUAL: fica dentro da janela de +-1 do servidor para defasagem
    //    de relógio nos dois sentidos, sem apostar no passo seguinte.
    await _pumpUntil(tester, () => passo(DateTime.now()) > passoDaAtivacao, timeout: const Duration(seconds: 40));
    final agora = DateTime.now();
    final codigo = totpCode(segredo, agora);
    await tester.enterText(find.byKey(const Key('totp_field')), codigo);
    await _tocarEntrar(tester);
    await _pumpUntil(tester, () =>
        find.byKey(const Key('login_button')).evaluate().isEmpty || find.byKey(const Key('login_error')).evaluate().isNotEmpty);
    final erro = find.byKey(const Key('login_error'));
    expect(erro, findsNothing,
        reason: '${erro.evaluate().isEmpty ? '' : (tester.widget<Text>(erro).data ?? '')} '
            '(relógio do aparelho ${agora.toUtc().toIso8601String()}, passo ${passo(agora)}, ativação no passo $passoDaAtivacao)');

    // 4) Refresh token: o login com MFA deixou um no Keystore (o servidor só o
    //    emite a quem manda o deviceId; a linha em acs_refresh_tokens é
    //    conferida pelo script). Nenhuma senha ficou no app.
    final keystore = SecureStorageSessionTokenStore();
    final tokenDoLogin = await keystore.read();
    expect(tokenDoLogin, isNotNull, reason: 'o login com MFA grava o refresh token no Keystore');
    final primeira = backend.session!;
    if (_esperarJwt) {
      final inicio = DateTime.now();
      // ignore: avoid_print
      print('jwt: esperando vencer (exp ${primeira.expiresAt.toIso8601String()}, início ${inicio.toUtc().toIso8601String()})');
      await _pumpUntil(tester, () => primeira.isExpired(),
          timeout: const Duration(minutes: 16), step: const Duration(seconds: 2));
      // ignore: avoid_print
      print('jwt: vencido após ${DateTime.now().difference(inicio).inSeconds} s de espera real');
    } else {
      // Sem esperar 15 min: a mesma renovação que `_requireToken` dispara.
      await backend.renewSession();
    }

    // 5) Chamada autenticada comum (lista da microárea pela aba Visita): com o
    //    JWT vencido ela renova sozinha e a tela de reautenticação NÃO aparece.
    if (_esperarJwt) expect(backend.session!.isExpired(), isTrue, reason: 'o JWT deveria estar vencido aqui');
    final main = e2ePatient('main');
    await tester.tap(find.text('Visita'));
    await _pumpUntil(tester, () =>
        find.byKey(Key('patient_${main.id}')).evaluate().isNotEmpty ||
        find.byKey(const Key('login_button')).evaluate().isNotEmpty ||
        find.byKey(const Key('patient_directory_error')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsNothing, reason: 'a renovação não pode pedir a senha de novo');
    expect(find.textContaining('Sua sessão expirou'), findsNothing);
    expect(find.byKey(const Key('patient_directory_error')), findsNothing);
    expect(find.byKey(Key('patient_${main.id}')), findsOneWidget);
    final renovada = backend.session!;
    expect(renovada.isExpired(), isFalse);
    // `exp` tem resolução de segundos: sem a espera real, login e renovação
    // podem cair no mesmo segundo. A prova da rotação é o refresh token abaixo.
    expect(
        _esperarJwt ? renovada.expiresAt.isAfter(primeira.expiresAt) : !renovada.expiresAt.isBefore(primeira.expiresAt),
        isTrue,
        reason: 'JWT novo');
    final tokenRotacionado = await keystore.read();
    expect(tokenRotacionado, isNotNull);
    expect(tokenRotacionado, isNot(tokenDoLogin), reason: 'o refresh token é rotativo: o filho substitui o pai no Keystore');
    // ignore: avoid_print
    print('jwt: renovado sem reautenticação (exp anterior ${primeira.expiresAt.toIso8601String()}, '
        'novo ${renovada.expiresAt.toIso8601String()})');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    // 6) Partida a frio: cliente novo (nada em memória), o mesmo Keystore e um
    //    desbloqueio local que aceita. O painel abre sem matrícula/senha/código.
    final frio = BackendClient(trustedCaBytes: ca);
    addTearDown(frio.close);
    final desbloqueio = _DesbloqueioDeTeste(available: true);
    await tester.pumpWidget(SinalAcsApp(
      backend: frio,
      biometricGate: desbloqueio,
      syncInterval: const Duration(hours: 2),
    ));
    await _pumpUntil(tester, () => find.byKey(const Key('login_button')).evaluate().isEmpty);
    expect(desbloqueio.calls, 1, reason: 'a retomada passa pelo desbloqueio local');
    expect(frio.session, isNotNull);
    expect(await keystore.read(), isNot(tokenRotacionado), reason: 'a retomada também rotaciona');

    // 7) "Sair" revoga no servidor e apaga do Keystore: o próximo app não retoma.
    await frio.logout();
    expect(await keystore.read(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: _esperarJwt ? const Timeout(Duration(minutes: 22)) : null);
}
