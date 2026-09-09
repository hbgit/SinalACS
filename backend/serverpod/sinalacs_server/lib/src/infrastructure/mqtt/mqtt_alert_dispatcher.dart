import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';

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
  Future<void> Function(AlertDeliveryAck ack)? _onAcknowledgement;
  Duration _backoff = _initialBackoff;
  bool _reconnecting = false;
  bool _closed = false;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({
    Future<void> Function(AlertDeliveryAck ack)? onAcknowledgement,
  }) async {
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

    // A subscription e o cliente anteriores precisam ser descartados antes de
    // assumir os novos: sem isso, cada reconexão deixava um listener vivo no
    // cliente antigo, e uma tempestade de reconexão passava a disparar o
    // callback de ACK em duplicata para a mesma mensagem.
    await _teardownCurrentConnection();

    _subscription = client.updates?.listen(_handleMessages);
    _client = client;
    _backoff = _initialBackoff;
  }

  Future<void> _handleMessages(
    List<MqttReceivedMessage<MqttMessage>> messages,
  ) async {
    final handler = _onAcknowledgement;
    if (handler == null) return;

    for (final message in messages) {
      final payload = message.payload as MqttPublishMessage;
      final body =
          MqttPublishPayload.bytesToStringAsString(payload.payload.message);
      final ack = _decodeAck(body);
      if (ack == null) continue;

      // O callback é assíncrono e antes era invocado sem await, então qualquer
      // falha ao registrar o ACK virava erro assíncrono não tratado. Um ACK
      // perdido em silêncio deixa um alerta vermelho eternamente pendente
      // (INV-03), por isso a falha é aguardada e registrada.
      try {
        await handler(ack);
      } catch (error, stackTrace) {
        stderr.writeln(
          'Falha ao processar ACK do alerta ${ack.alertId}: $error\n$stackTrace',
        );
      }
    }
  }

  Future<void> _teardownCurrentConnection() async {
    final previousSubscription = _subscription;
    final previousClient = _client;
    _subscription = null;
    _client = null;
    await previousSubscription?.cancel();
    previousClient?.disconnect();
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
    await _teardownCurrentConnection();
  }

  AlertDeliveryAck? _decodeAck(String body) => AlertDeliveryAck.tryParse(body);

  ({String host, int port}) _parseBroker(String value) {
    final uri = Uri.parse(value.contains('://') ? value : 'mqtt://$value');
    return (host: uri.host, port: uri.hasPort ? uri.port : 1883);
  }
}
