/// Telemetria dos eventos do PRD §1.3 (#83) no emulador, contra o BANCO DE
/// TESTE: alerta → ACK → visitas offline → reinício → online → reenvio
/// idempotente.
///
/// Só roda por `scripts/qa/acs_telemetria_e2e.sh` (sufixo `_e2e`: a descoberta
/// do `flutter test integration_test` não o encontra). Conversa com o script
/// por linhas marcadoras na saída:
///   E2E_ALERTA id=<uuid>   → o alerta do paciente `telemetry` (para o SQL)
///   E2E_CORTAR_BACKEND     → o script faz `docker pause sinalacs-traefik`
///   E2E_RESTAURAR_BACKEND  → o script faz `docker unpause sinalacs-traefik`
///   E2E_TELEMETRIA_OK      → o roteiro do aparelho terminou
///
/// O alerta chega ao ACS pela reserva HTTP (`alerts.openForMicroArea`): o
/// `aclfile` do broker só libera a microárea do seed de desenvolvimento, e o
/// script tira o broker do alcance do aparelho. O "offline" é REAL na rota do
/// app até o backend (o Traefik congelado), não um decorator. O "reinício" é
/// um `SinalAcsApp` novo, com cliente novo, sobre o MESMO arquivo SQLCipher.
///
/// As contagens no servidor (`telemetry_events`) e o `telemetry_report.dart`
/// são conferidos pelo script, no banco.
///
/// PRIVACIDADE: só fixtures sintéticas geradas por execução; nada de CPF em log.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_telemetry_store.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/telemetry/connectivity_network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';

class _SemBiometria implements BiometricGate {
  @override
  Future<bool> get isAvailable async => false;
  @override
  Future<UnlockResult> authenticate({required String reason}) async => UnlockResult.unavailable;
}

/// O store real do app, com uma cópia de tudo o que foi gravado: o reenvio
/// forçado do fim precisa dos MESMOS registros, e o aceito some do disco.
class _StoreQueGuarda implements TelemetryStore {
  _StoreQueGuarda(this._real, this.gravados);

  final TelemetryStore _real;
  final List<TelemetryEventRecord> gravados;

  @override
  Future<void> append(TelemetryEventRecord e) async {
    await _real.append(e);
    if (!gravados.any((x) => x.eventId == e.eventId)) gravados.add(e);
  }

  @override
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}) =>
      _real.oldestForOwner(owner, limit: limit);

  @override
  Future<void> deleteByIds(Iterable<String> ids) => _real.deleteByIds(ids);

  @override
  Future<int> countForOwner(String owner) => _real.countForOwner(owner);
}

Future<void> _ate(WidgetTester tester, bool Function() feito, {required Duration teto, required String oQue}) async {
  final fim = DateTime.now().add(teto);
  while (!feito()) {
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _ateAsync(WidgetTester tester, Future<bool> Function() feito,
    {required Duration teto, required String oQue}) async {
  final fim = DateTime.now().add(teto);
  while (!await feito()) {
    if (DateTime.now().isAfter(fim)) fail('$oQue: não aconteceu em ${teto.inSeconds} s');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Espera o script agir sobre a linha marcadora (o laço dele lê a cada 1 s).
Future<void> _esperarScript(WidgetTester tester) async {
  final fim = DateTime.now().add(const Duration(seconds: 6));
  while (DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(alvo);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _entrar(WidgetTester tester, ({String matricula, String senha}) cred) async {
  await _ate(tester, () => find.byKey(const Key('matricula_field')).evaluate().isNotEmpty,
      teto: const Duration(seconds: 30), oQue: 'tela de login');
  await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
  await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
  final entrar = find.byKey(const Key('login_button'));
  await _tocar(tester, entrar);
  await _ate(tester, () => entrar.evaluate().isEmpty, teto: const Duration(seconds: 45), oQue: 'login');
}

/// GET no relé do OTP (relógio e código do HOST, nunca do aparelho).
Future<String?> _rele(String path, {String query = ''}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(relayBase).replace(path: path, query: query));
    final response = await request.close();
    final body = (await utf8.decodeStream(response)).trim();
    return response.statusCode == 200 ? body : null;
  } finally {
    client.close(force: true);
  }
}

/// O paciente `telemetry` entra pelo OTP real e dispara o alerta vermelho.
Future<String> _dispararAlerta(api.Client paciente, E2ePatient fixture) async {
  final desde = await _rele('/now');
  if (desde == null) throw StateError('o relé não respondeu /now');
  await paciente.auth.requestOtp(cpf: fixture.cpf, birthDate: DateTime.parse(fixture.birthDate));
  String? codigo;
  for (var i = 0; i < 40 && codigo == null; i++) {
    codigo = await _rele('/code', query: 'since=$desde');
    if (codigo == null) await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (codigo == null) throw StateError('o relé não devolveu o código do OTP');
  final sessao = await paciente.auth.verifyOtp(cpf: fixture.cpf, code: codigo);
  final criado = await paciente.alerts.createRedAlert(
    accessToken: sessao.accessToken,
    idempotencyKey: 'telemetria-e2e-${DateTime.now().millisecondsSinceEpoch}',
    locationHash: 'sem-local-00',
  );
  return criado.alertId;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('telemetria: alerta, ACK, visitas offline, reinício e reenvio idempotente', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    const host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    final telemetria = e2ePatient('telemetry');
    // O id do aparelho sobrevive ao reinício, como no Keystore do app real.
    final aparelho = MemoryDeviceIdStore();

    const arquivo = 'telemetria_e2e.db';
    await EncryptedLocalDatabase.deleteDatabaseFile(arquivo);
    final gravados = <TelemetryEventRecord>[];

    // ---- 1) Login pela tela, alerta pela reserva HTTP e ACK ----
    final storage1 = SqlCipherVisitStorage(keyStore: SecureStorageDatabaseKeyStore(), databaseName: arquivo);
    final store1 = _StoreQueGuarda(SqlCipherTelemetryStore(storage1.database), gravados);
    final backend1 = BackendClient(trustedCaBytes: ca, deviceIds: aparelho);
    await tester.pumpWidget(SinalAcsApp(
      backend: backend1,
      biometricGate: _SemBiometria(),
      visitStorage: storage1,
      telemetryStore: store1,
      networkProbe: connectivityProbe(),
      // Só o toque em "Sincronizar agora" envia: a contagem de tentativas no
      // servidor é exata.
      syncInterval: const Duration(hours: 2),
      alertFallbackInterval: const Duration(seconds: 5),
    ));
    await _entrar(tester, cred);
    final acsId = backend1.session!.userId;
    await _ate(tester, () => find.byKey(const Key('alert_fallback_status')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 60), oQue: 'reserva HTTP ligada (o MQTT conectou?)');

    final paciente = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(paciente.close);
    final alertId = await _dispararAlerta(paciente, telemetria);
    // ignore: avoid_print
    print('E2E_ALERTA id=$alertId');

    final cartao = find.byKey(Key('alert_$alertId'), skipOffstage: false);
    await _ate(tester, () => cartao.evaluate().isNotEmpty, teto: const Duration(seconds: 45), oQue: 'alerta pela reserva');
    await _tocar(tester, find.descendant(of: cartao, matching: find.text('Confirmar recebimento')));
    await _ate(tester, () => find.descendant(of: cartao, matching: find.text('Recebimento confirmado')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 20), oQue: 'ACK pela tela');

    // O seletor carrega a microárea ANTES do corte (sem cache injetado aqui).
    await tester.tap(find.text('Visita'));
    await _ate(tester, () => find.byKey(Key('patient_${main.id}')).evaluate().isNotEmpty,
        teto: const Duration(seconds: 30), oQue: 'seletor de pacientes');

    // ---- 2) Corte real: Traefik congelado; 2 visitas de rotina e 1 do alerta ----
    // ignore: avoid_print
    print('E2E_CORTAR_BACKEND');
    await _esperarScript(tester);

    await _tocar(tester, find.byKey(Key('patient_${main.id}')));
    await _tocar(tester, find.byKey(const Key('arrival_confirmation')));
    for (var n = 1; n <= 2; n++) {
      await _tocar(tester, find.byKey(const Key('save_visit')));
      await _ate(tester, () => find.text('Pendentes de sincronização: $n').evaluate().isNotEmpty,
          teto: const Duration(seconds: 20), oQue: 'visita de rotina $n');
    }

    await tester.tap(find.text('Fila'));
    await tester.pump(const Duration(milliseconds: 500));
    await _tocar(tester, find.descendant(of: cartao, matching: find.text('Acionar SAMU / Atender')));
    await _tocar(tester, find.byKey(const Key('escalation_visit')));
    await _tocar(tester, find.byKey(const Key('arrival_confirmation')));
    await _tocar(tester, find.byKey(const Key('save_visit')));
    await _ate(tester, () => find.text('Pendentes de sincronização: 3').evaluate().isNotEmpty,
        teto: const Duration(seconds: 20), oQue: 'visita do alerta');

    await _tocar(tester, find.byKey(const Key('sync_visits')));
    await _ate(tester, () => gravados.any((e) => e.name == 'sync_result'),
        teto: const Duration(seconds: 90), oQue: 'erro de rede do sync');
    expect(find.text('Pendentes de sincronização: 3'), findsOneWidget, reason: 'nada subiu');

    // ---- 3) O store local ----
    Future<List<TelemetryEventRecord>> locais(TelemetryStore s) => s.oldestForOwner(acsId, limit: 1000);
    final noPasso3 = await locais(store1);
    final porNome = <String, int>{};
    for (final e in noPasso3) {
      porNome[e.name] = (porNome[e.name] ?? 0) + 1;
    }
    expect(porNome, {'visit_registered': 3, 'sync_attempt': 1, 'sync_result': 1});
    final resultado = noPasso3.singleWhere((e) => e.name == 'sync_result');
    expect(resultado.payload['transport_error'], isTrue);
    expect(resultado.payload['outcome'], 'error');
    final registros = noPasso3.where((e) => e.name == 'visit_registered').toList();
    expect(registros.where((e) => e.payload['alert_id'] == alertId), hasLength(1));
    expect(registros.where((e) => e.payload['visit_type'] == 'routine'), hasLength(2));
    final idsDoPasso3 = {for (final e in noPasso3) e.eventId};

    // ---- 4) Reinício: app, cliente e conexão novos sobre o MESMO arquivo ----
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    backend1.close();
    await storage1.close();
    final storage2 = SqlCipherVisitStorage(keyStore: SecureStorageDatabaseKeyStore(), databaseName: arquivo);
    final store2 = _StoreQueGuarda(SqlCipherTelemetryStore(storage2.database), gravados);
    expect({for (final e in await locais(store2)) e.eventId}, idsDoPasso3, reason: 'os 5 eventos sobrevivem ao reinício');
    expect(await storage2.forOwner(acsId).load(), hasLength(3), reason: 'as 3 visitas seguem pendentes');

    final backend2 = BackendClient(trustedCaBytes: ca, deviceIds: aparelho);
    addTearDown(backend2.close);
    await tester.pumpWidget(SinalAcsApp(
      backend: backend2,
      biometricGate: _SemBiometria(),
      visitStorage: storage2,
      telemetryStore: store2,
      networkProbe: connectivityProbe(),
      syncInterval: const Duration(hours: 2),
      alertFallbackInterval: const Duration(seconds: 5),
    ));

    // ---- 5) A rota volta; o ACS entra de novo e sincroniza ----
    // ignore: avoid_print
    print('E2E_RESTAURAR_BACKEND');
    await _esperarScript(tester);
    await _entrar(tester, cred);
    expect(backend2.session!.userId, acsId);
    await tester.tap(find.text('Visita'));
    await _ate(tester, () => find.text('Pendentes de sincronização: 3').evaluate().isNotEmpty,
        teto: const Duration(seconds: 20), oQue: 'fila restaurada do disco');
    await _tocar(tester, find.byKey(const Key('sync_visits')));
    await _ate(tester, () => find.text('Pendentes de sincronização: 0').evaluate().isNotEmpty,
        teto: const Duration(seconds: 60), oQue: 'sync depois do reinício');
    await _ateAsync(tester, () async => await store2.countForOwner(acsId) == 0,
        teto: const Duration(seconds: 60), oQue: 'flush da telemetria');
    expect(gravados, hasLength(7), reason: '3 visit_registered + 2 tentativas + 2 resultados');
    expect(gravados.where((e) => e.name == 'sync_result').last.payload['outcome'], 'synced');

    // ---- 6) Reenvio forçado dos mesmos registros: todos aceitos, sem duplicar ----
    final ack = await backend2.ingestTelemetry(gravados, expectedUserId: acsId);
    expect({for (final id in ack.accepted) id.toLowerCase()}, {for (final e in gravados) e.eventId.toLowerCase()});
    expect(ack.rejected, isEmpty);

    // ignore: avoid_print
    print('E2E_TELEMETRIA_OK eventos=${gravados.length}');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await storage2.close();
  });
}
