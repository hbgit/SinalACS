/// Verificação do ciclo completo do alerta vermelho, com o código de rede real
/// do app do ACS.
///
/// Roda na VM, sem emulador, e prova o caminho que nenhum teste hermético pode
/// provar: paciente cria o alerta pelo RPC → o backend publica no broker → o
/// ACS recebe pelo MQTT com TLS → confirma pelo RPC.
///
/// Pré-requisitos:
///   · `docker compose up` com o database-seed concluído;
///   · `./scripts/dev/sync_dev_ca.sh` (a CA é regerada, não versionada).
///
///   cd apps/acs
///   dart run tool/live_check.dart
///   dart run tool/live_check.dart --host http://10.0.2.2:8080/ --broker 10.0.2.2
///   dart run tool/live_check.dart --mqtt-password "$MQTT_ACS_PASSWORD"
library;

import 'dart:async';
import 'dart:io';

import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

String _arg(List<String> args, String name, String fallback) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

Future<void> main(List<String> args) async {
  final host = _arg(args, 'host', 'http://localhost:8080/');
  final brokerHost = _arg(args, 'broker', 'localhost');
  final caPath = _arg(args, 'ca', '../../infra/docker/mosquitto/runtime/certs/ca.crt');

  final backend = BackendClient(host: host);
  // O paciente usa o cliente gerado diretamente: aqui ele só encena o disparo
  // para que o ACS tenha o que receber.
  final patientClient = api.Client(host)..connectivityMonitor = null;

  stdout.writeln('ACS → $host   broker → $brokerHost:8883');
  MqttSecureClient? mqtt;

  try {
    final session = await backend.login();
    final microAreaId = session.microAreaId!;
    stdout.writeln('  login .............. papel=${session.role} microárea=$microAreaId');

    // Usa o MqttSecureClient direto em vez da AlertQueue: a fila depende de
    // ChangeNotifier (Flutter) e este script roda na VM. A ordenação e o filtro
    // de microárea da fila são cobertos pelos testes herméticos.
    // Acumula TUDO que chegar e espera depois pelo alerta específico criado
    // aqui. Com sessão persistente (cleanSession = false) e clientId estável, o
    // broker entrega primeiro o que ficou pendente de execuções anteriores —
    // comportamento desejado, e a razão de um alerta não sumir enquanto o ACS
    // está sem sinal. Casar com "o primeiro que chegar" daria OK para o alerta
    // errado, inclusive se o novo nunca chegasse.
    final inbox = <String, ReceivedMqttAlert>{};

    mqtt = MqttSecureClient(
      config: SecureMqttConfig(
        brokerHost: brokerHost,
        port: 8883,
        clientId: 'sinalacs-acs-livecheck-${session.userId}',
        topic: alertTopicFor(microAreaId),
        // Default vem do BackendConfig (não de literais soltos aqui), mas a
        // senha do broker local é gerada por scripts/dev/bootstrap_env.sh e é
        // diferente a cada máquina — por isso o --mqtt-password, que
        // scripts/qa/e2e.sh preenche a partir do .env.
        username: _arg(args, 'mqtt-user', BackendConfig.mqttUsername),
        password: _arg(args, 'mqtt-password', BackendConfig.mqttPassword),
        caCertificate: File(caPath).readAsBytesSync(),
      ),
    );

    await mqtt.connect(onAlert: (alert) => inbox[alert.alertId] = alert);
    stdout.writeln('  broker ............. conectado com TLS, assinando ${alertTopicFor(microAreaId)}');

    // Dispara pelo lado do paciente.
    final patientLogin = await patientClient.auth.developmentLogin(role: 'patient');
    final created = await patientClient.alerts.createRedAlert(
      accessToken: patientLogin.accessToken,
      idempotencyKey: 'acs-live-check-${DateTime.now().millisecondsSinceEpoch}',
      locationHash: 'sem-local-00',
    );
    stdout.writeln('  alerta criado ...... ${created.alertId} (publicado=${created.published})');

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!inbox.containsKey(created.alertId) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final alert = inbox[created.alertId];
    if (alert == null) {
      throw TimeoutException('o alerta ${created.alertId} não chegou pelo broker');
    }
    stdout.writeln('  recebido pelo MQTT . ${alert.alertId} risco=${alert.riskLevel}');
    final backlog = inbox.length - 1;
    if (backlog > 0) {
      stdout.writeln('  backlog da sessão .. $backlog alerta(s) pendente(s) reentregue(s)');
    }

    final ack = await backend.acknowledge(alertId: alert.alertId);
    stdout.writeln('  ACK ................ acknowledged=${ack.acknowledged} status=${ack.status?.name}');
    if (!ack.acknowledged) {
      stderr.writeln('  ERRO: a central não confirmou o recebimento.');
      exitCode = 1;
    }

    // Sincronização de visita, pelo endpoint novo.
    final localId = '00000000-0000-4000-8000-${DateTime.now().millisecondsSinceEpoch % 1000000000000}';
    final synced = await backend.syncVisits([
      api.VisitSyncEntry(
        localId: localId.padRight(36, '0').substring(0, 36),
        patientId: alert.patientId,
        scheduledAt: DateTime.now().toUtc(),
        status: 'realizada',
        riskLevelBefore: api.RiskLevel.red,
        notes: const {},
        version: 0,
      ),
    ]);
    stdout.writeln('  visita sincronizada  ${synced.single.syncStatus.name} '
        'versão=${synced.single.serverVersion}');
    if (synced.single.syncStatus != api.SyncStatus.synced) {
      stderr.writeln('  ERRO: a visita não sincronizou (${synced.single.message}).');
      exitCode = 1;
    }

    stdout.writeln(exitCode == 0
        ? '\nOK — o ciclo do alerta vermelho fecha ponta a ponta pelos apps.'
        : '\nFALHOU.');
  } on BackendFailure catch (failure) {
    stderr.writeln('  falhou: ${failure.message}');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('  falhou: $error');
    exitCode = 1;
  } finally {
    mqtt?.disconnect();
    backend.close();
    patientClient.close();
  }
}
