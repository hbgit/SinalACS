/// Smoke do app do ACS no dispositivo — o único arquivo que a CI roda.
///
/// Um teste só, de propósito: cada arquivo de `integration_test/` custa um
/// build e um `adb install` do APK no emulador da CI, e é isso que domina o
/// tempo do job `android-e2e`. Aqui fica encadeado o que só o aparelho prova:
///
///   1. o ACS autentica e recebe a própria microárea;
///   2. o alerta vermelho publicado pelo backend chega pelo MQTT com TLS (CA do
///      asset) e é confirmado — alerta vermelho nunca some em silêncio;
///   3. a visita gravada no SQLCipher real não aparece legível no arquivo do
///      banco (INV-04);
///   4. a fila offline sincroniza contra o servidor e a visita confirmada sai
///      do disco (minimização, LGPD-RF07).
///
/// O resto da bateria — chave errada, migração v1, chave perdida, fila
/// recusando outra microárea, ACK inexistente, reenvio idempotente, mapa —
/// continua em `red_alert_cycle_test.dart`, `encrypted_storage_test.dart` e
/// `map_flow_test.dart`, rodados por `./scripts/qa/e2e.sh --emulator --full`.
///
/// Mesmos pré-requisitos e `--dart-define` de `red_alert_cycle_test.dart`.
///
/// PRIVACIDADE: só os UUIDs sintéticos do seed e um marcador sintético.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

const seedMicroAreaId = '00000000-0000-4000-8000-000000000003';
const seedPatientId = '00000000-0000-4000-8000-000000000001';

/// Marcador sintético que precisa NÃO aparecer no arquivo do banco.
const marcador = 'MARCADOR-SINTETICO-NAO-DEVE-VAZAR';

const databaseName = 'sinalacs_smoke_probe.db';

/// Mesma leitura de `red_alert_cycle_test.dart`. A CA do broker é outra, e o
/// `MqttAlertFeed` a carrega sozinho.
Future<List<int>?> _devRpcCaBytes() async {
  try {
    final data = await rootBundle.load(BackendConfig.rpcCaAsset);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('smoke: alerta pelo broker, visita cifrada no disco e sincronizada', () async {
    if (BackendConfig.mqttPasswordMissing) {
      fail(
        'Compile com --dart-define=SINALACS_MQTT_PASSWORD (o valor está em '
        'MQTT_ACS_PASSWORD no .env). O caminho pronto é '
        './scripts/qa/e2e.sh --emulator.',
      );
    }
    final caBytes = await _devRpcCaBytes();
    if (caBytes == null) {
      fail(
        'A CA do RPC não está no bundle (${BackendConfig.rpcCaAsset}). Rode '
        './scripts/dev/sync_dev_ca.sh com a stack de pé.',
      );
    }

    final backend = BackendClient(trustedCaBytes: caBytes);
    addTearDown(backend.close);
    // O paciente entra em cena só para dar ao ACS o que receber.
    final patientClient = api.Client(
      const String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/'),
      securityContext: SecurityContext()..setTrustedCertificatesBytes(caBytes),
    )..connectivityMonitor = null;
    addTearDown(patientClient.close);

    // 1. Login e microárea.
    final session = await backend.developmentLogin(role: 'acs');
    expect(session.role, 'acs');
    expect(session.microAreaId, seedMicroAreaId);
    final microAreaId = session.microAreaId!;

    // 2. Alerta vermelho pelo broker, com ACK.
    final alertQueue = AlertQueue(microAreaId: microAreaId);
    final feed = MqttAlertFeed(queue: alertQueue);
    await feed.start(microAreaId: microAreaId, acsId: session.userId);
    expect(feed.isConnected, isTrue, reason: 'o ACS não conectou ao broker');

    try {
      final login = await patientClient.auth.developmentLogin(role: 'patient');
      final created = await patientClient.alerts.createRedAlert(
        accessToken: login.accessToken,
        idempotencyKey: 'smoke-${DateTime.now().microsecondsSinceEpoch}',
        locationHash: 'sem-local-00',
      );

      // Espera o alerta ESPECÍFICO: o broker reentrega backlog de execuções
      // anteriores, e a fila ordena por antiguidade.
      PrioritizedAlert? alert;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (alert == null && DateTime.now().isBefore(deadline)) {
        for (final candidate in alertQueue.alerts) {
          if (candidate.alertId == created.alertId) alert = candidate;
        }
        if (alert == null) await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (alert == null) {
        throw TimeoutException('o alerta ${created.alertId} não chegou pelo broker');
      }
      expect(alert.riskLevel, 'red');
      expect(alert.microAreaId, microAreaId);

      final ack = await backend.acknowledge(alertId: alert.alertId);
      expect(ack.acknowledged, isTrue);
      expect(ack.status, api.AlertStatus.acknowledged);
    } finally {
      feed.stop();
      alertQueue.dispose();
    }

    // 3. Visita gravada no SQLCipher real, ilegível no arquivo.
    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
    addTearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(databaseName));
    final store = SqlCipherVisitStore(
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: databaseName,
    );
    final visitQueue = OfflineVisitQueue(
      store: store,
      synchronizer: BackendVisitSynchronizer(backend: backend),
    );
    await visitQueue.add(OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      outcome: 'realizada',
      notes: marcador,
    ));
    // Fechar garante que tudo foi para o disco; o store reabre sozinho depois.
    await store.close();

    final bytes = await File(await EncryptedLocalDatabase.pathFor(databaseName)).readAsBytes();
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'),
        reason: 'o banco está em texto plano — viola o INV-04 do PRD');
    final conteudo = String.fromCharCodes(bytes);
    expect(conteudo.contains(marcador), isFalse,
        reason: 'o conteúdo da visita aparece legível no arquivo do banco');
    expect(conteudo.contains(seedPatientId), isFalse,
        reason: 'o identificador do paciente aparece legível no arquivo do banco');

    // 4. Sincroniza e a visita confirmada sai do aparelho.
    final result = await visitQueue.sync();
    expect(result.kind, SyncOutcomeKind.synced, reason: result.message);
    expect(visitQueue.pendingCount, 0);
    expect(await store.load(), isEmpty, reason: 'a visita continua no aparelho');
    await store.close();
  });
}
