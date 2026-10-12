import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

import 'support/fakes.dart';

/// Reforço do escalonamento (#44): o backend republica o MESMO alerta com
/// `escalated: true`. O "sinal" de alerta novo neste app é `upsert` devolver
/// `true` (+ `notifyListeners`, que move o contador/banner); não há som nem
/// vibração próprios.
void main() {
  late AlertQueue queue;
  setUp(() => queue = AlertQueue(microAreaId: seedMicroAreaId));

  test('reforço de alerta não confirmado sobe ao topo e sinaliza', () {
    queue.upsert(testAlert(alertId: 'antigo', triggeredAt: DateTime.utc(2026, 9, 11, 8)));
    queue.upsert(testAlert(alertId: 'alvo', triggeredAt: DateTime.utc(2026, 9, 11, 9)));
    var avisos = 0;
    queue.addListener(() => avisos++);

    final sinalizou = queue.upsert(testAlert(alertId: 'alvo', triggeredAt: DateTime.utc(2026, 9, 11, 9), escalated: true));

    expect(sinalizou, isTrue);
    expect(avisos, 1);
    expect(queue.alerts.map((a) => a.alertId), ['alvo', 'antigo']);
    expect(queue.alerts.first.escalated, isTrue);
    expect(queue.alerts, hasLength(2));
  });

  test('reforço de alerta já confirmado é ignorado', () {
    queue.upsert(testAlert(alertId: 'a1'));
    queue.markAcknowledged('a1');
    var avisos = 0;
    queue.addListener(() => avisos++);

    expect(queue.upsert(testAlert(alertId: 'a1', escalated: true)), isFalse);

    expect(avisos, 0);
    expect(queue.alerts.single.acknowledged, isTrue);
    expect(queue.alerts.single.escalated, isFalse);
  });

  test('reforço de alerta desconhecido entra como alerta com rótulo', () {
    expect(queue.upsert(testAlert(alertId: 'novo', escalated: true)), isTrue);

    expect(queue.alerts.single.alertId, 'novo');
    expect(queue.alerts.single.escalated, isTrue);
    expect(queue.unacknowledgedCount, 1);
  });

  test('reforço repetido (QoS 1) não sinaliza duas vezes', () {
    queue.upsert(testAlert(alertId: 'a1'));
    expect(queue.upsert(testAlert(alertId: 'a1', escalated: true)), isTrue);
    var avisos = 0;
    queue.addListener(() => avisos++);

    expect(queue.upsert(testAlert(alertId: 'a1', escalated: true)), isFalse);
    // A reentrega do original (sem marcador) também não apaga o reforço.
    queue.upsert(testAlert(alertId: 'a1'));

    expect(queue.alerts.single.escalated, isTrue);
    expect(queue.alerts, hasLength(1));
  });

  test('envelope sem escalated continua igual (regressão)', () {
    final parsed = ReceivedMqttAlert.tryParse(
        '{"version":1,"alert_id":"a1","patient_id":"p","micro_area_id":"$seedMicroAreaId","risk_level":"red","location_hash":"h","triggered_at":"2026-09-01T12:00:00.000Z"}');
    expect(parsed?.escalated, isFalse);
    expect(PrioritizedAlert.fromMqtt(parsed!).escalated, isFalse);

    expect(queue.upsert(testAlert(alertId: 'a1')), isTrue);
    expect(queue.upsert(testAlert(alertId: 'a1')), isTrue); // reentrega comum, como antes
    expect(queue.alerts.single.escalated, isFalse);
  });

  test('chave desconhecida no envelope não quebra o parse', () {
    final parsed = ReceivedMqttAlert.tryParse(
        '{"version":1,"alert_id":"a1","patient_id":"p","micro_area_id":"m","risk_level":"red","location_hash":"h","triggered_at":"2026-09-01T12:00:00.000Z","escalated":true,"chave_futura":{"x":1},"outra":[1,2]}');

    expect(parsed, isNotNull);
    expect(parsed!.escalated, isTrue);
    // `escalated` com tipo errado não derruba nem vira reforço.
    final torto = ReceivedMqttAlert.tryParse(
        '{"version":1,"alert_id":"a1","patient_id":"p","micro_area_id":"m","risk_level":"red","location_hash":"h","triggered_at":"2026-09-01T12:00:00.000Z","escalated":"sim"}');
    expect(torto, isNotNull);
    expect(torto!.escalated, isFalse);
  });
}
