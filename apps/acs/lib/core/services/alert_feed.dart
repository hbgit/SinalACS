import 'package:flutter/services.dart' show rootBundle;
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

/// Liga o broker à [AlertQueue].
///
/// É a única peça que sabe montar a configuração MQTT a partir da sessão: o
/// tópico depende da microárea do ACS autenticado, então não dá para fixá-lo em
/// tempo de compilação.
abstract class AlertFeed {
  Future<void> start({required String microAreaId, required String acsId});

  void stop();

  bool get isConnected;
}

class MqttAlertFeed implements AlertFeed {
  MqttAlertFeed({
    required this.queue,
    this.onConnectionChanged,
  });

  final AlertQueue queue;
  final void Function(bool connected)? onConnectionChanged;

  MqttSecureClient? _client;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> start({
    required String microAreaId,
    required String acsId,
  }) async {
    final caCertificate = await rootBundle.load(BackendConfig.mqttCaAsset);

    final client = MqttSecureClient(
      config: SecureMqttConfig(
        brokerHost: BackendConfig.mqttHost,
        port: BackendConfig.mqttPort,
        // Estável por ACS: é o que permite ao broker restaurar a sessão
        // persistente e reentregar o que chegou enquanto o aparelho estava
        // offline. Um id aleatório aqui descartaria esses alertas.
        clientId: 'sinalacs-acs-$acsId',
        topic: alertTopicFor(microAreaId),
        username: BackendConfig.mqttUsername,
        password: BackendConfig.mqttPassword,
        caCertificate: caCertificate.buffer.asUint8List(),
      ),
    );

    await client.connect(
      onAlert: (alert) => queue.upsert(PrioritizedAlert.fromMqtt(alert)),
      onConnectionChanged: (connected) {
        _connected = connected;
        onConnectionChanged?.call(connected);
      },
    );

    _client = client;
    _connected = client.isConnected;
    onConnectionChanged?.call(_connected);
  }

  @override
  void stop() {
    _client?.disconnect();
    _client = null;
    _connected = false;
  }
}
