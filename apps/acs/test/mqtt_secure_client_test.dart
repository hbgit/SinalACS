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
    // Precisa ser o MESMO namespace de AlertDelivery.topicPrefix no servidor e
    // da ACL do broker. Este teste antes afirmava '/alerts/microarea-01', um
    // namespace que não existe em nenhum dos dois lados.
    expect(json['mqtt_topic'], 'sinalacs/v1/microareas/microarea-01/alerts');
  });

  test('deve montar os tópicos no namespace acordado com o backend', () {
    expect(
      alertTopicFor('00000000-0000-4000-8000-000000000003'),
      'sinalacs/v1/microareas/00000000-0000-4000-8000-000000000003/alerts',
    );
    expect(ackTopicFor('alert-123'), 'sinalacs/v1/alerts/alert-123/acks');
  });

  test('deve usar TCP/TLS por padrão, que é o único listener do broker', () {
    const config = SecureMqttConfig(
      brokerHost: 'broker.sinalacs.local',
      port: 8883,
      clientId: 'acs-client-01',
      topic: 'sinalacs/v1/microareas/microarea-01/alerts',
    );

    expect(config.useTls, isTrue);
    // O default era WebSocket, o que fazia connect() lançar UnsupportedError na
    // configuração padrão — o cliente se autodesabilitava.
    expect(config.useWebSocket, isFalse);
    expect(config.connectionUri, 'ssl://broker.sinalacs.local:8883');
  });

  test('deve montar URI WebSocket quando explicitamente pedido', () {
    const config = SecureMqttConfig(
      brokerHost: 'broker.sinalacs.local',
      port: 8883,
      clientId: 'acs-client-01',
      topic: 'sinalacs/v1/microareas/microarea-01/alerts',
      useWebSocket: true,
    );

    expect(config.connectionUri, contains('wss://'));
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
