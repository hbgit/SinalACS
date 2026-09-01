import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class SecureMqttConfig {
  const SecureMqttConfig({
    required this.brokerHost,
    required this.port,
    required this.clientId,
    required this.topic,
    this.useTls = true,
    this.useWebSocket = true,
    this.username,
    this.password,
    this.caCertificatePath,
  });

  final String brokerHost;
  final int port;
  final String clientId;
  final String topic;
  final bool useTls;
  final bool useWebSocket;
  final String? username;
  final String? password;
  final String? caCertificatePath;

  String get connectionUri {
    if (useWebSocket) {
      final scheme = useTls ? 'wss' : 'ws';
      return '$scheme://$brokerHost:$port';
    }

    final scheme = useTls ? 'ssl' : 'tcp';
    return '$scheme://$brokerHost:$port';
  }
}

class ReceivedMqttAlert {
  const ReceivedMqttAlert({
    required this.alertId,
    required this.patientId,
    required this.microAreaId,
    required this.riskLevel,
    required this.locationHash,
    required this.triggeredAt,
  });

  final String alertId;
  final String patientId;
  final String microAreaId;
  final String riskLevel;
  final String locationHash;
  final DateTime triggeredAt;

  static ReceivedMqttAlert? tryParse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['version'] != 1) return null;

      final triggeredAtRaw = json['triggered_at'] as String? ?? json['timestamp'] as String?;
      if (triggeredAtRaw == null) return null;

      return ReceivedMqttAlert(
        alertId: json['alert_id'] as String,
        patientId: json['patient_id'] as String,
        microAreaId: json['micro_area_id'] as String,
        riskLevel: json['risk_level'] as String,
        locationHash: (json['location_hash'] as String?) ?? (json['location_hash'] ?? 'unknown') as String,
        triggeredAt: DateTime.parse(triggeredAtRaw),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class MqttSecureAlertPayload {
  MqttSecureAlertPayload({
    required this.alertId,
    required this.patientId,
    required this.riskLevel,
    required this.latitude,
    required this.longitude,
    required this.microAreaId,
    String? locationHash,
    String? timestampOverride,
  })  : locationHash = locationHash ?? _defaultLocationHash(latitude, longitude),
        timestamp = timestampOverride ?? DateTime.now().toUtc().toIso8601String();

  final String alertId;
  final String patientId;
  final String riskLevel;
  final double latitude;
  final double longitude;
  final String microAreaId;
  final String locationHash;
  final String timestamp;

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'alert_id': alertId,
      'patient_id': patientId,
      'risk_level': riskLevel,
      'latitude': latitude,
      'longitude': longitude,
      'micro_area_id': microAreaId,
      'location_hash': locationHash,
      'triggered_at': timestamp,
      'timestamp': timestamp,
      'mqtt_topic': '/alerts/$microAreaId',
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static String _defaultLocationHash(double latitude, double longitude) {
    final normalized = '${latitude.toStringAsFixed(6)}:${longitude.toStringAsFixed(6)}';
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes).toString();
    return digest.substring(0, 12);
  }
}

class MqttSecureAcknowledgementPayload {
  const MqttSecureAcknowledgementPayload({
    required this.alertId,
    required this.acsId,
    required this.microAreaId,
    required this.acknowledgedAt,
  });

  final String alertId;
  final String acsId;
  final String microAreaId;
  final DateTime acknowledgedAt;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'alert_id': alertId,
        'acs_id': acsId,
        'micro_area_id': microAreaId,
        'acknowledged_at': acknowledgedAt.toUtc().toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());
}

class MqttSecureClient {
  MqttSecureClient({required this.config});

  final SecureMqttConfig config;
  MqttServerClient? _client;

  Future<void> connect({required void Function(ReceivedMqttAlert alert) onAlert}) async {
    if (config.useWebSocket) {
      throw UnsupportedError('O transporte WebSocket será configurado pelo gateway de produção.');
    }

    final client = MqttServerClient.withPort(config.brokerHost, config.clientId, config.port)
      ..keepAlivePeriod = 30
      ..secure = config.useTls
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(config.clientId)
          .withWillQos(MqttQos.atLeastOnce);
    if (config.useTls && config.caCertificatePath != null) {
      client.securityContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(config.caCertificatePath!);
    }

    await client.connect(config.username, config.password);
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('Não foi possível conectar ao broker MQTT.');
    }

    client.subscribe(config.topic, MqttQos.atLeastOnce);
    client.updates?.listen((messages) {
      for (final message in messages) {
        final publish = message.payload as MqttPublishMessage;
        final body = MqttPublishPayload.bytesToStringAsString(publish.payload.message);
        final alert = ReceivedMqttAlert.tryParse(body);
        if (alert != null && alert.microAreaId == _microAreaFromTopic(config.topic)) {
          onAlert(alert);
        }
      }
    });
    _client = client;
  }

  void disconnect() => _client?.disconnect();

  String _microAreaFromTopic(String topic) {
    final segments = topic.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.length >= 2 && segments.contains('microareas')) {
      final index = segments.indexOf('microareas');
      if (index + 1 < segments.length) return segments[index + 1];
    }
    if (segments.length >= 2 && segments.contains('alerts')) {
      final index = segments.indexOf('alerts');
      if (index + 1 < segments.length) return segments[index + 1];
    }
    return segments.isEmpty ? '' : segments.last;
  }

  MqttSecureAlertPayload buildAlertPayload({
    required String patientId,
    required String riskLevel,
    required double latitude,
    required double longitude,
    required String microAreaId,
  }) {
    return MqttSecureAlertPayload(
      alertId: 'alert-${DateTime.now().microsecondsSinceEpoch}',
      patientId: patientId,
      riskLevel: riskLevel,
      latitude: latitude,
      longitude: longitude,
      microAreaId: microAreaId,
    );
  }
}
