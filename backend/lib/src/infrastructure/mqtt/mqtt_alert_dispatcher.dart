import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sinalacs_backend/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_backend/src/config/app_config.dart';
import 'package:sinalacs_backend/src/domain/entities/alert_delivery.dart';

class MqttUnavailableException implements Exception {
  const MqttUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MqttAlertDispatcher implements AlertPublisher {
  MqttAlertDispatcher({required AppConfig config}) : _config = config;

  static const _initialBackoff = Duration(seconds: 2);
  static const _maxBackoff = Duration(seconds: 60);

  final AppConfig _config;
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;
  void Function(AlertDeliveryAck ack)? _onAcknowledgement;
  Duration _backoff = _initialBackoff;
  bool _reconnecting = false;
  bool _closed = false;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({void Function(AlertDeliveryAck ack)? onAcknowledgement}) async {
    _onAcknowledgement = onAcknowledgement;
    try {
      await _connectOnce();
    } catch (error) {
      stderr.writeln('Falha ao conectar ao broker MQTT: $error. Tentando novamente em segundo plano...');
      unawaited(_reconnectWithBackoff());
    }
  }

  Future<void> _connectOnce() async {
    final broker = _parseBroker(_config.mqttBroker);
    final clientId = 'sinalacs-backend-${DateTime.now().microsecondsSinceEpoch}';
    final client = MqttServerClient.withPort(broker.host, clientId, broker.port)
      ..keepAlivePeriod = 30
      ..secure = _config.mqttUseTls
      ..autoReconnect = false
      ..onDisconnected = _handleDisconnected
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
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
        if (ack != null) _onAcknowledgement?.call(ack);
      }
    });
    _client = client;
    _backoff = _initialBackoff;
  }

  void _handleDisconnected() {
    if (_closed || _reconnecting) return;
    unawaited(_reconnectWithBackoff());
  }

  Future<void> _reconnectWithBackoff() async {
    _reconnecting = true;
    while (!_closed) {
      await Future<void>.delayed(_backoff);
      try {
        await _connectOnce();
        break;
      } catch (error) {
        stderr.writeln('Falha ao reconectar ao broker MQTT: $error.');
        _backoff = Duration(seconds: min(_backoff.inSeconds * 2, _maxBackoff.inSeconds));
      }
    }
    _reconnecting = false;
  }

  @override
  void publish(AlertDelivery alert) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) {
      throw const MqttUnavailableException('O dispatcher MQTT não está conectado.');
    }

    final payload = MqttClientPayloadBuilder()..addString(alert.toJson());
    client.publishMessage(alert.topic, MqttQos.atLeastOnce, payload.payload!);
  }

  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    _client?.disconnect();
  }

  AlertDeliveryAck? _decodeAck(String body) => AlertDeliveryAck.tryParse(body);

  ({String host, int port}) _parseBroker(String value) {
    final uri = Uri.parse(value.contains('://') ? value : 'mqtt://$value');
    return (host: uri.host, port: uri.hasPort ? uri.port : 1883);
  }
}
