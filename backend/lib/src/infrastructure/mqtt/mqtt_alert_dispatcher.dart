import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sinalacs_backend/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_backend/src/config/app_config.dart';
import 'package:sinalacs_backend/src/domain/entities/alert_delivery.dart';

class MqttAlertDispatcher implements AlertPublisher {
  MqttAlertDispatcher({required AppConfig config}) : _config = config;

  final AppConfig _config;
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;

  Future<void> connect({void Function(AlertDeliveryAck ack)? onAcknowledgement}) async {
    final broker = _parseBroker(_config.mqttBroker);
    final client = MqttServerClient.withPort(
      broker.host,
      'sinalacs-backend-${DateTime.now().microsecondsSinceEpoch}',
      broker.port,
    )
      ..keepAlivePeriod = 30
      ..secure = _config.mqttUseTls
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier('sinalacs-backend')
          .withWillQos(MqttQos.atLeastOnce);

    if (_config.mqttUseTls && _config.mqttCaCertificatePath != null) {
      client.securityContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(_config.mqttCaCertificatePath!);
    }

    await client.connect(_config.mqttUsername, _config.mqttPassword);
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('Não foi possível conectar ao broker MQTT.');
    }

    client.subscribe('sinalacs/v1/alerts/+/acks', MqttQos.atLeastOnce);
    _subscription = client.updates?.listen((messages) {
      for (final message in messages) {
        final payload = message.payload as MqttPublishMessage;
        final body = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
        final ack = _decodeAck(body);
        if (ack != null) onAcknowledgement?.call(ack);
      }
    });
    _client = client;
  }

  @override
  void publish(AlertDelivery alert) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('O dispatcher MQTT não está conectado.');
    }

    final payload = MqttClientPayloadBuilder()..addString(alert.toJson());
    client.publishMessage(alert.topic, MqttQos.atLeastOnce, payload.payload!);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _client?.disconnect();
  }

  AlertDeliveryAck? _decodeAck(String body) => AlertDeliveryAck.tryParse(body);

  ({String host, int port}) _parseBroker(String value) {
    final uri = Uri.parse(value.contains('://') ? value : 'mqtt://$value');
    return (host: uri.host, port: uri.hasPort ? uri.port : 1883);
  }
}