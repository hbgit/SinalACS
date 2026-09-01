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

  test('deve montar payload de confirmação do ACS para o alerta vermelho', () {
    final ack = MqttSecureAcknowledgementPayload(
      alertId: 'alert-123',
      acsId: 'acs-456',
      microAreaId: 'area-12',
      acknowledgedAt: DateTime.utc(2026, 9, 1, 12, 1),
    );

    final json = ack.toJson();
    expect(json['version'], 1);
    expect(json['alert_id'], 'alert-123');
    expect(json['acs_id'], 'acs-456');
    expect(json['micro_area_id'], 'area-12');
    expect(json['acknowledged_at'], '2026-09-01T12:01:00.000Z');
  });

  test('decodifica somente o envelope MQTT versionado', () {
    final alert = ReceivedMqttAlert.tryParse('''
      {"version":1,"alert_id":"alert-123","patient_id":"patient-42","micro_area_id":"area-12","risk_level":"red","location_hash":"6gyf4bf","triggered_at":"2026-09-01T12:00:00.000Z"}
    ''');

    expect(alert?.alertId, 'alert-123');
    expect(alert?.microAreaId, 'area-12');
    expect(ReceivedMqttAlert.tryParse('{"version":2}'), isNull);
  });
}
