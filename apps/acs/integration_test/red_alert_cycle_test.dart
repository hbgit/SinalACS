/// Ciclo do alerta vermelho ponta a ponta, com a stack local de pé.
///
/// Prova o caminho que nenhum teste hermético alcança: o backend publica no
/// broker e o app do ACS recebe pelo MQTT com TLS.
///
/// Pré-requisitos:
///   · `docker compose up` com o database-seed concluído;
///   · `./scripts/dev/sync_dev_ca.sh` — a CA do broker é asset do app e é
///     regerada, não versionada.
///
/// O caminho pronto é `./scripts/qa/e2e.sh --emulator`, que sobe a stack e
/// preenche os dart-defines a partir do `.env`. À mão:
///
///   flutter test integration_test \
///     --dart-define=SINALACS_HOST=http://10.0.2.2:8080/ \
///     --dart-define=SINALACS_MQTT_HOST=10.0.2.2 \
///     --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD"
///
/// A senha é obrigatória: ela não tem default no `BackendConfig`.
///
/// PRIVACIDADE: só os UUIDs sintéticos do seed.
library;

import 'dart:async';

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
const otherMicroAreaId = '00000000-0000-4000-8000-000000000099';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Sem a senha, a assinatura do tópico falha depois do timeout do broker e
    // o motivo real — o comando de compilação — não aparece em lugar nenhum.
    if (BackendConfig.mqttPasswordMissing) {
      fail(
        'Compile com --dart-define=SINALACS_MQTT_PASSWORD (o valor está em '
        'MQTT_ACS_PASSWORD no .env). O caminho pronto é '
        './scripts/qa/e2e.sh --emulator.',
      );
    }
  });

  late BackendClient backend;
  late api.Client patientClient;

  setUp(() {
    backend = BackendClient();
    // O paciente entra em cena só para dar ao ACS o que receber.
    patientClient = api.Client(
      const String.fromEnvironment('SINALACS_HOST', defaultValue: 'http://10.0.2.2:8080/'),
    )..connectivityMonitor = null;
  });

  tearDown(() {
    backend.close();
    patientClient.close();
  });

  Future<String> createRedAlertAsPatient() async {
    final login = await patientClient.auth.developmentLogin(role: 'patient');
    final created = await patientClient.alerts.createRedAlert(
      accessToken: login.accessToken,
      idempotencyKey: 'integ-${DateTime.now().microsecondsSinceEpoch}',
      locationHash: 'sem-local-00',
    );
    return created.alertId;
  }

  test('o ACS autentica e recebe a própria microárea', () async {
    // `developmentLogin` e não o login institucional: este arquivo roda contra
    // a stack local com `ENABLE_DEV_LOGIN=true` e não carrega a senha do ACS
    // (RF07) — o caminho com matrícula e senha é coberto pelo widget test e
    // pelo teste de renovação de sessão, sem senha real em código de teste.
    final session = await backend.developmentLogin(role: 'acs');

    expect(session.role, 'acs');
    expect(session.microAreaId, seedMicroAreaId);
  });

  test('o alerta publicado pelo backend chega ao ACS pelo broker e é confirmado', () async {
    final session = await backend.developmentLogin(role: 'acs');
    final microAreaId = session.microAreaId!;

    final queue = AlertQueue(microAreaId: microAreaId);
    final feed = MqttAlertFeed(queue: queue);

    /// Espera o alerta ESPECÍFICO criado pelo teste.
    ///
    /// Não serve olhar `alerts.first`: com sessão persistente o broker
    /// reentrega o que ficou pendente de execuções anteriores, e a fila ordena
    /// por antiguidade — o primeiro seria justamente o alerta antigo do
    /// backlog.
    Future<PrioritizedAlert> waitFor(String alertId, {Duration timeout = const Duration(seconds: 20)}) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        for (final alert in queue.alerts) {
          if (alert.alertId == alertId) return alert;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw TimeoutException('o alerta $alertId não chegou pelo broker');
    }

    // Conecta com TLS usando a CA do asset. Falhar aqui aponta para o
    // certificado sem SAN ou para a ACL do broker.
    await feed.start(microAreaId: microAreaId, acsId: session.userId);
    expect(feed.isConnected, isTrue, reason: 'o ACS não conectou ao broker');

    try {
      final alertId = await createRedAlertAsPatient();

      final alert = await waitFor(alertId);
      expect(alert.alertId, alertId);
      expect(alert.riskLevel, 'red');
      expect(alert.microAreaId, microAreaId);

      final ack = await backend.acknowledge(alertId: alert.alertId);
      expect(ack.acknowledged, isTrue);
      expect(ack.status, api.AlertStatus.acknowledged);
    } finally {
      feed.stop();
      queue.dispose();
    }
  });

  test('a fila recusa alerta de fora da microárea do ACS', () async {
    // Territorialização é invariante. A ACL do broker é a primeira barreira; a
    // fila é a segunda.
    final queue = AlertQueue(microAreaId: seedMicroAreaId);

    final accepted = queue.upsert(PrioritizedAlert(
      alertId: 'alerta-de-outra-area',
      patientId: seedPatientId,
      microAreaId: otherMicroAreaId,
      riskLevel: 'red',
      locationHash: 'sem-local-00',
      triggeredAt: DateTime.now().toUtc(),
    ));

    expect(accepted, isFalse);
    expect(queue.isEmpty, isTrue);
    queue.dispose();
  });

  test('confirmar um alerta inexistente devolve acknowledged: false, não erro', () async {
    await backend.developmentLogin(role: 'acs');

    final ack = await backend.acknowledge(
      alertId: '00000000-0000-4000-8000-0000000000ff',
    );

    expect(ack.acknowledged, isFalse);
  });

  test('a fila offline de visitas sincroniza contra o servidor', () async {
    await backend.developmentLogin(role: 'acs');

    final queue = OfflineVisitQueue(
      synchronizer: BackendVisitSynchronizer(backend: backend),
    );

    await queue.add(OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      outcome: 'realizada',
    ));

    final result = await queue.sync();

    expect(result.kind, SyncOutcomeKind.synced);
    expect(queue.pendingCount, 0);
    expect(queue.syncedCount, 1);
  });

  test('a visita confirmada SAI do disco criptografado', () async {
    // O único lugar onde retenção, criptografia real e servidor real se
    // encontram: o teste hermético não tem SQLCipher, e o de criptografia não
    // tem servidor. Minimização (LGPD-RF07 / seção 5.6 de spec/lgpd_design.md):
    // o que já chegou ao servidor não continua num aparelho que pode ser
    // perdido ou roubado.
    const nome = 'sinalacs_retencao_probe.db';
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);

    await backend.developmentLogin(role: 'acs');

    final store = SqlCipherVisitStore(
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: nome,
    );
    final queue = OfflineVisitQueue(
      store: store,
      synchronizer: BackendVisitSynchronizer(backend: backend),
    );

    await queue.add(OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      outcome: 'realizada',
    ));
    expect(await store.load(), hasLength(1), reason: 'a visita não foi gravada');

    final result = await queue.sync();

    expect(result.kind, SyncOutcomeKind.synced, reason: result.message);
    expect(queue.syncedCount, 1);
    expect(await store.load(), isEmpty, reason: 'a visita continua no aparelho');

    await store.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);
  });

  test('reenviar a mesma visita não a duplica no servidor', () async {
    await backend.developmentLogin(role: 'acs');

    // `version` fica no padrão 1, que é a versão com que o servidor grava todo
    // insert. Enviar 0 fazia o reenvio cair na regra de atualização
    // (`entry.version == existing.version - 1`) e subir para 2 — o oposto da
    // idempotência que este teste existe para provar.
    final visit = OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      outcome: 'realizada',
    );

    final synchronizer = BackendVisitSynchronizer(backend: backend);

    final first = await synchronizer.push([visit]);
    // Mesmo localId, mesma versão: é o retry de quem não viu a resposta.
    final retry = await synchronizer.push([visit]);

    expect(first.single.status, 'synced');
    expect(retry.single.status, 'synced');
    expect(retry.single.serverVersion, first.single.serverVersion);
  });
}
