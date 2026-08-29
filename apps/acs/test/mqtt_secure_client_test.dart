import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

void main() {
  test('deve montar payload de alerta com metadados críticos do paciente', () {
    final payload = MqttSecureAlertPayload(
      alertId: 'alert-123',
      patientId: 'patient-42',
      riskLevel: 'VERMELHO',
      latitude: -23.5505,
      longitude: -46.6333,
      microAreaId: 'microarea-01',
    );

    final json = payload.toJson();

    expect(json['alert_id'], 'alert-123');
    expect(json['patient_id'], 'patient-42');
    expect(json['risk_level'], 'VERMELHO');
    expect(json['micro_area_id'], 'microarea-01');
    expect(json['mqtt_topic'], '/alerts/microarea-01');
  });

  test('deve criar configuração MQTT segura com TLS e WSS', () {
    const config = SecureMqttConfig(
      brokerHost: 'broker.sinalacs.local',
      port: 8883,
      clientId: 'acs-client-01',
      topic: '/alerts/microarea-01',
      useTls: true,
      useWebSocket: true,
    );

    expect(config.useTls, isTrue);
    expect(config.useWebSocket, isTrue);
    expect(config.connectionUri, contains('wss://'));
    expect(config.connectionUri, contains('8883'));
    expect(config.connectionUri, contains('broker.sinalacs.local'));
  });
}
