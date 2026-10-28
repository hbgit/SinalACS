import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_session_kicker.dart';
import 'package:test/test.dart';

import '../support/fake_mqtt_broker.dart';

/// Derrubada da sessão MQTT de um aparelho (#94): o backend conecta com o
/// client id do aparelho e o broker encerra a sessão anterior (takeover).
/// Broker falso do projeto, em TCP real (o mesmo da resiliência do
/// despachante).
AppConfig _config(int port) => AppConfig(
  mqttBroker: '127.0.0.1:$port',
  jwtSecret: 'test-secret',
  auditChainSecret: 'test-audit-chain-secret',
  healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
  cpfHashPepper: AppConfig.developmentCpfHashPepper,
  telemetryPseudonymKey: AppConfig.developmentTelemetryPseudonymKey,
  smsGateway: 'log',
  mqttUsername: null,
  mqttPassword: null,
  mqttUseTls: false,
  mqttCaCertificatePath: null,
  appEnv: 'development',
  enableDevLogin: true,
);

/// Um "aparelho" conectado com [clientId]; completa [caiu] quando a sessão cai.
Future<({MqttServerClient client, Completer<void> caiu})> _aparelho(
  int port,
  String clientId,
) async {
  final caiu = Completer<void>();
  final client = MqttServerClient.withPort('127.0.0.1', clientId, port)
    ..keepAlivePeriod = 60
    ..autoReconnect = false
    ..logging(on: false)
    ..onDisconnected = (() {
      if (!caiu.isCompleted) caiu.complete();
    })
    ..connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
  await client.connect();
  expect(client.connectionStatus?.state, MqttConnectionState.connected);
  return (client: client, caiu: caiu);
}

void main() {
  test('clientIdFor é a string que o app copia', () {
    expect(
      MqttSessionKicker.clientIdFor(acsId: 'acs-1', deviceId: 'dev-9'),
      'sinalacs-acs-acs-1-dev-9',
    );
  });

  test('kick derruba a sessão com o mesmo client id', () async {
    final broker = await FakeMqttBroker.start();
    addTearDown(broker.close);
    final id = MqttSessionKicker.clientIdFor(acsId: 'acs-1', deviceId: 'dev-1');
    final alvo = await _aparelho(broker.port, id);
    final outro = await _aparelho(
      broker.port,
      MqttSessionKicker.clientIdFor(acsId: 'acs-1', deviceId: 'dev-2'),
    );
    addTearDown(() {
      alvo.client.disconnect();
      outro.client.disconnect();
    });

    final logs = <String>[];
    await MqttSessionKicker(config: _config(broker.port), log: logs.add).kick(id);

    await alvo.caiu.future.timeout(const Duration(seconds: 2));
    expect(broker.takenOver, [id]);
    expect(outro.caiu.isCompleted, isFalse, reason: 'só o aparelho alvo cai');
    expect(logs, isEmpty);
  });

  test('broker fora do ar vira log, não exceção', () async {
    // Porta que acabou de ser liberada: conexão recusada.
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final porta = s.port;
    await s.close();

    final logs = <String>[];
    await MqttSessionKicker(config: _config(porta), log: logs.add).kick(
      'sinalacs-acs-a-b',
      timeout: const Duration(seconds: 2),
    );
    expect(logs, hasLength(1));
    expect(logs.single, contains('Exception'));
    expect(logs.single, isNot(contains('sinalacs-acs-a-b')),
        reason: 'o client id carrega o id do ACS; não vai ao log');
  });
}
