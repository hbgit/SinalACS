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
///
/// `--mqtt-password` é obrigatório: a senha do broker não tem default.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

String _arg(List<String> args, String name, String fallback) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

int _intArg(List<String> args, String name, int fallback) {
  final value = _arg(args, name, '$fallback');
  return int.tryParse(value) ?? fallback;
}

void _emitMetric(
  bool enabled,
  String event, {
  Map<String, Object?> extra = const {},
}) {
  if (!enabled) return;
  stdout.writeln('METRIC ${jsonEncode(<String, Object?>{
    'event': event,
    'at': DateTime.now().toUtc().toIso8601String(),
    ...extra,
  })}');
}

Future<void> main(List<String> args) async {
  final host = _arg(args, 'host', 'http://localhost:8080/');
  final brokerHost = _arg(args, 'broker', 'localhost');
  final caPath = _arg(args, 'ca', '../../infra/docker/mosquitto/runtime/certs/ca.crt');
  final emitMetrics = args.contains('--emit-metrics');
  final visitCount = _intArg(args, 'visit-count', 1).clamp(1, 1000);

  // A senha do broker não tem default no BackendConfig: é um segredo por
  // máquina. Sem esta guarda, quem rodasse à mão ganharia um timeout mudo em
  // vez de saber o que faltou.
  final mqttPassword = _arg(args, 'mqtt-password', BackendConfig.mqttPassword);
  if (mqttPassword.isEmpty) {
    stderr.writeln('erro: a senha do broker não foi informada.');
    stderr.writeln(r'Use: dart run tool/live_check.dart --mqtt-password "$MQTT_ACS_PASSWORD"');
    stderr.writeln('O valor vem do .env; scripts/qa/e2e.sh já faz isso por você.');
    exitCode = 2;
    return;
  }

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
        // A senha do broker local é gerada por scripts/dev/bootstrap_env.sh e
        // é diferente a cada máquina — por isso o --mqtt-password obrigatório,
        // que scripts/qa/e2e.sh preenche a partir do .env.
        username: _arg(args, 'mqtt-user', BackendConfig.mqttUsername),
        password: mqttPassword,
        caCertificate: File(caPath).readAsBytesSync(),
      ),
    );

    await mqtt.connect(onAlert: (alert) => inbox[alert.alertId] = alert);
    stdout.writeln('  broker ............. conectado com TLS, assinando ${alertTopicFor(microAreaId)}');

    // Dispara pelo lado do paciente.
    final patientLogin = await patientClient.auth.developmentLogin(role: 'patient');
    _emitMetric(
      emitMetrics,
      'alert_triggered',
      extra: <String, Object?>{'visit_count': visitCount},
    );
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
    _emitMetric(
      emitMetrics,
      'alert_received_acs',
      extra: <String, Object?>{'visit_count': visitCount},
    );
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

    // Sincronização de visita pela FILA de produção, não por um VisitSyncEntry
    // montado à mão: é isto que pega uma fila sem sincronizador ligado, um
    // patientId errado ou um localId malformado — tudo o que o app faz sozinho.
    // O único pedaço fora do caminho real é o store: SQLCipher não abre na VM.
    final queue = OfflineVisitQueue(
      store: InMemoryVisitStore(),
      synchronizer: BackendVisitSynchronizer(backend: backend),
    );
    for (var index = 0; index < visitCount; index++) {
      await queue.add(OfflineVisitRecord(
        patientId: alert.patientId,
        risk: alert.riskLevel,
        status: 'PENDENTE',
        outcome: 'realizada',
        notes: visitCount == 1 ? '' : 'lote ${index + 1}/$visitCount',
      ));
    }

    _emitMetric(
      emitMetrics,
      'sync_attempt',
      extra: <String, Object?>{'visit_count': visitCount},
    );
    final synced = await queue.sync();
    _emitMetric(
      emitMetrics,
      'sync_result',
      extra: <String, Object?>{
        'visit_count': visitCount,
        'kind': synced.kind.name,
        'processed': synced.processed,
        'pending_count': queue.pendingCount,
      },
    );
    stdout.writeln('  visita sincronizada  ${synced.kind.name} '
        'processadas=${synced.processed} pendentes=${queue.pendingCount}');
    if (synced.kind != SyncOutcomeKind.synced || queue.pendingCount != 0) {
      stderr.writeln('  ERRO: a visita não sincronizou (${synced.message}).');
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
