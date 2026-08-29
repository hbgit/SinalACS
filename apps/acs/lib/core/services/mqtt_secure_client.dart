import 'dart:convert';

class SecureMqttConfig {
  const SecureMqttConfig({
    required this.brokerHost,
    required this.port,
    required this.clientId,
    required this.topic,
    this.useTls = true,
    this.useWebSocket = true,
  });

  final String brokerHost;
  final int port;
  final String clientId;
  final String topic;
  final bool useTls;
  final bool useWebSocket;

  String get connectionUri {
    final scheme = useTls ? 'wss' : 'ws';
    final protocol = useWebSocket ? 'wss' : 'mqtt';
    final base = useWebSocket ? '$protocol://$brokerHost:$port' : '$brokerHost:$port';
    return useWebSocket ? base : '$scheme://$base';
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
    String? timestampOverride,
  }) : timestamp = timestampOverride ?? DateTime.now().toUtc().toIso8601String();

  final String alertId;
  final String patientId;
  final String riskLevel;
  final double latitude;
  final double longitude;
  final String microAreaId;
  final String timestamp;

  Map<String, dynamic> toJson() {
    return {
      'alert_id': alertId,
      'patient_id': patientId,
      'risk_level': riskLevel,
      'latitude': latitude,
      'longitude': longitude,
      'micro_area_id': microAreaId,
      'timestamp': timestamp,
      'mqtt_topic': '/alerts/$microAreaId',
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

class MqttSecureClient {
  const MqttSecureClient({required this.config});

  final SecureMqttConfig config;

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
