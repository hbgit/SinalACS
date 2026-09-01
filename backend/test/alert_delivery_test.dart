import 'dart:convert';

import 'package:sinalacs_backend/src/domain/entities/alert_delivery.dart';
import 'package:test/test.dart';

void main() {
  group('AlertDelivery', () {
    test('publica somente dados mínimos no tópico da microárea', () {
      final delivery = AlertDelivery(
        alertId: 'alert-123',
        patientId: 'patient-456',
        microAreaId: 'area-12',
        riskLevel: 'red',
        locationHash: '6gyf4bf',
        triggeredAt: DateTime.utc(2026, 9, 1, 12),
      );

      expect(delivery.topic, 'sinalacs/v1/microareas/area-12/alerts');
      expect(jsonDecode(delivery.toJson()), {
        'version': 1,
        'alert_id': 'alert-123',
        'patient_id': 'patient-456',
        'micro_area_id': 'area-12',
        'risk_level': 'red',
        'location_hash': '6gyf4bf',
        'triggered_at': '2026-09-01T12:00:00.000Z',
      });
    });
  });

  test('vincula o ACK ao alerta e ao ACS que o confirmou', () {
    final acknowledgement = AlertDeliveryAck(
      alertId: 'alert-123',
      acsId: 'acs-456',
      microAreaId: 'area-12',
      acknowledgedAt: DateTime.utc(2026, 9, 1, 12, 1),
    );

    expect(acknowledgement.topic, 'sinalacs/v1/alerts/alert-123/acks');
    expect(jsonDecode(acknowledgement.toJson())['acs_id'], 'acs-456');
  });

  test('ignora ACKs malformados ou com versão incompatível', () {
    expect(AlertDeliveryAck.tryParse('{"version":2}'), isNull);
    expect(AlertDeliveryAck.tryParse('{"version":1,"alert_id":"alert-123","acs_id":"acs-456","micro_area_id":"area-12","acknowledged_at":"not-a-date"}'), isNull);
  });
}