import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';

/// Fusão da reserva por HTTP na fila (#80, R2): nunca remove, nunca duplica,
/// nunca desfaz ACK nem reforço, e só notifica quando algo mudou.
AcsOpenAlert _aberto(
  String id, {
  AlertStatus status = AlertStatus.pending,
  bool escalated = false,
  String microAreaId = seedMicroAreaId,
}) =>
    AcsOpenAlert(
      alertId: id,
      patientId: seedPatientId,
      microAreaId: microAreaId,
      riskLevel: RiskLevel.red,
      locationHash: 'hash-sintetico',
      triggeredAt: DateTime.utc(2026, 10, 17, 12),
      status: status,
      acknowledgedAt: status == AlertStatus.acknowledged ? DateTime.utc(2026, 10, 17, 12, 1) : null,
      escalated: escalated,
    );

PrioritizedAlert _do(AcsOpenAlert a) => PrioritizedAlert.fromServer(a);

void main() {
  late AlertQueue queue;
  late int notificacoes;

  setUp(() {
    queue = AlertQueue(microAreaId: seedMicroAreaId);
    notificacoes = 0;
    queue.addListener(() => notificacoes++);
  });

  test('alerta novo do servidor entra na fila e conta 1', () {
    expect(queue.mergeFromServer([_do(_aberto('a'))]), 1);
    expect(queue.alerts.single.alertId, 'a');
    expect(queue.alerts.single.riskLevel, 'red');
    expect(notificacoes, 1);
  });

  test('mesma resposta de novo não muda nada nem notifica', () {
    queue.mergeFromServer([_do(_aberto('a'))]);
    expect(queue.mergeFromServer([_do(_aberto('a'))]), 0);
    expect(notificacoes, 1);
  });

  test('outra microárea é ignorada', () {
    expect(queue.mergeFromServer([_do(_aberto('a', microAreaId: otherMicroAreaId))]), 0);
    expect(queue.isEmpty, isTrue);
    expect(notificacoes, 0);
  });

  test('servidor confirmado promove cartão local pendente', () {
    queue.upsert(_do(_aberto('a')));
    expect(queue.mergeFromServer([_do(_aberto('a', status: AlertStatus.acknowledged))]), 1);
    expect(queue.alerts.single.acknowledged, isTrue);
  });

  test('servidor pendente não desfaz ACK local', () {
    queue.upsert(_do(_aberto('a')));
    queue.markAcknowledged('a');
    expect(queue.mergeFromServer([_do(_aberto('a'))]), 0);
    expect(queue.alerts.single.acknowledged, isTrue);
  });

  test('reforço do servidor marca escalated; ausência do marcador não o tira', () {
    queue.upsert(_do(_aberto('a')));
    expect(queue.mergeFromServer([_do(_aberto('a', escalated: true))]), 1);
    expect(queue.alerts.single.escalated, isTrue);
    expect(queue.mergeFromServer([_do(_aberto('a'))]), 0);
    expect(queue.alerts.single.escalated, isTrue);
  });

  test('cartão ausente da resposta não é removido', () {
    queue.upsert(_do(_aberto('a')));
    expect(queue.mergeFromServer([]), 0);
    expect(queue.alerts, hasLength(1));
  });

  test('mergeFromServer depois de upsert do MQTT não duplica', () {
    queue.upsert(PrioritizedAlert.fromMqtt(ReceivedMqttAlert(
      alertId: 'x',
      patientId: seedPatientId,
      microAreaId: seedMicroAreaId,
      riskLevel: 'red',
      locationHash: 'hash-sintetico',
      triggeredAt: DateTime.utc(2026, 10, 17, 12),
    )));
    queue.mergeFromServer([_do(_aberto('x'))]);
    expect(queue.alerts, hasLength(1));
  });

  test('concluído localmente não volta a pendente', () {
    queue.upsert(_do(_aberto('a')));
    queue.markResolved('a');
    expect(queue.mergeFromServer([_do(_aberto('a', status: AlertStatus.acknowledged))]), 0);
    expect(queue.alerts.single.resolved, isTrue);
  });
}
