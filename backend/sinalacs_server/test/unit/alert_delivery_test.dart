import 'dart:convert';

import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
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

    test('inclui location_cell quando presente, omite quando ausente', () {
      final comCelula = AlertDelivery(
        alertId: 'alert-123',
        patientId: 'patient-456',
        microAreaId: 'area-12',
        riskLevel: 'red',
        locationHash: '6gyf4bf',
        locationCell: '-1580:-4783',
        triggeredAt: DateTime.utc(2026, 9, 1, 12),
      );
      expect(jsonDecode(comCelula.toJson())['location_cell'], '-1580:-4783');

      final semCelula = AlertDelivery(
        alertId: 'alert-124',
        patientId: 'patient-456',
        microAreaId: 'area-12',
        riskLevel: 'red',
        locationHash: 'sem-local-00',
        triggeredAt: DateTime.utc(2026, 9, 1, 12),
      );
      expect(jsonDecode(semCelula.toJson()).containsKey('location_cell'), isFalse);
    });

    test('tryParse aceita envelope sem location_cell (compatibilidade)', () {
      final body = jsonEncode({
        'version': 1,
        'alert_id': 'alert-123',
        'patient_id': 'patient-456',
        'micro_area_id': 'area-12',
        'risk_level': 'red',
        'location_hash': '6gyf4bf',
        'triggered_at': '2026-09-01T12:00:00.000Z',
      });
      final parsed = AlertDelivery.tryParse(body);
      expect(parsed, isNotNull);
      expect(parsed!.locationCell, isNull);
    });
  });

  test('reforço de escalonamento (#44): marcador aditivo, sobrevive ao outbox', () {
    final base = AlertDelivery(
      alertId: 'alert-123',
      patientId: 'patient-456',
      microAreaId: 'area-12',
      riskLevel: 'red',
      locationHash: '6gyf4bf',
      triggeredAt: DateTime.utc(2026, 9, 1, 12),
    );
    // Entrega comum: o envelope não muda (sem a chave).
    expect(jsonDecode(base.toJson()).containsKey('escalated'), isFalse);
    expect(AlertDelivery.tryParse(base.toJson())!.escalated, isFalse);

    final reforco = AlertDelivery(
      alertId: base.alertId,
      patientId: base.patientId,
      microAreaId: base.microAreaId,
      riskLevel: base.riskLevel,
      locationHash: base.locationHash,
      triggeredAt: base.triggeredAt,
      escalated: true,
    );
    final json = jsonDecode(reforco.toJson()) as Map<String, dynamic>;
    expect(json['escalated'], isTrue);
    expect(json['version'], 1, reason: 'aditivo: o app do ACS segue lendo v1');
    expect(json.keys.toSet(), {
      'version',
      'alert_id',
      'patient_id',
      'micro_area_id',
      'risk_level',
      'location_hash',
      'triggered_at',
      'escalated',
    });
    // O drenador reidrata o payload gravado e republica: o marcador não se perde.
    final reidratado = AlertDelivery.tryParse(reforco.toJson())!;
    expect(reidratado.escalated, isTrue);
    expect(jsonDecode(reidratado.toJson())['escalated'], isTrue);
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