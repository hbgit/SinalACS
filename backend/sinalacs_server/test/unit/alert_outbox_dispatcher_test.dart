import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:test/test.dart';

class _FlakyPublisher implements AlertPublisher {
  _FlakyPublisher({this.failures = 0});

  int failures;
  final List<AlertDelivery> published = [];

  @override
  void publish(AlertDelivery alert) {
    if (failures > 0) {
      failures--;
      throw Exception('broker indisponível');
    }
    published.add(alert);
  }
}

class _RecordingOutbox implements AlertOutbox {
  final List<AlertDelivery> enqueued = [];
  final Set<String> publishedIds = {};
  final Map<String, DateTime> retryAt = {};
  final Map<String, String> errors = {};
  var attemptsByEntry = <String, int>{};

  @override
  Future<void> enqueue(AlertDelivery alert) async => enqueued.add(alert);

  @override
  Future<List<PendingDelivery>> claimDue({int limit = 32}) async {
    final due = <PendingDelivery>[];
    for (final alert in enqueued) {
      final id = 'entry-${alert.alertId}';
      if (publishedIds.contains(id)) continue;
      attemptsByEntry[id] = (attemptsByEntry[id] ?? 0) + 1;
      due.add(PendingDelivery(
        entryId: id,
        delivery: alert,
        attempts: attemptsByEntry[id]!,
      ));
      if (due.length >= limit) break;
    }
    return due;
  }

  @override
  Future<void> markPublished(String entryId) async => publishedIds.add(entryId);

  @override
  Future<void> markFailed(
    String entryId,
    String error,
    DateTime nextAttemptAt,
  ) async {
    errors[entryId] = error;
    retryAt[entryId] = nextAttemptAt;
  }
}

AlertDelivery _delivery(String id) => AlertDelivery(
      alertId: id,
      patientId: 'patient-001',
      microAreaId: 'area-12',
      riskLevel: 'red',
      locationHash: '6gyf4bf',
      triggeredAt: DateTime.utc(2026, 9, 1, 12),
    );

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);

  test('publica as entregas pendentes e marca cada uma', () async {
    final outbox = _RecordingOutbox();
    final publisher = _FlakyPublisher();
    await outbox.enqueue(_delivery('alerta-1'));
    await outbox.enqueue(_delivery('alerta-2'));

    final dispatcher = AlertOutboxDispatcher(
      outbox: outbox,
      publisher: publisher,
      clock: () => now,
    );

    expect(await dispatcher.drainOnce(), 2);
    expect(publisher.published, hasLength(2));
    expect(outbox.publishedIds, hasLength(2));
  });

  test('falha de publicação não propaga e agenda retentativa com backoff',
      () async {
    final outbox = _RecordingOutbox();
    // Falha nas duas primeiras tentativas, sucede na terceira.
    final publisher = _FlakyPublisher(failures: 2);
    await outbox.enqueue(_delivery('alerta-1'));

    final dispatcher = AlertOutboxDispatcher(
      outbox: outbox,
      publisher: publisher,
      clock: () => now,
    );

    // Primeira rodada: falha, sem lançar, e agenda para 2s à frente.
    expect(await dispatcher.drainOnce(), 0);
    expect(publisher.published, isEmpty);
    expect(outbox.errors['entry-alerta-1'], contains('broker indisponível'));
    expect(outbox.retryAt['entry-alerta-1'], now.add(const Duration(seconds: 2)));

    // Segunda rodada: falha de novo, e o backoff dobra.
    expect(await dispatcher.drainOnce(), 0);
    expect(outbox.retryAt['entry-alerta-1'], now.add(const Duration(seconds: 4)));

    // Terceira: publica e marca. Um alerta vermelho não se perde por o broker
    // ter estado fora do ar (INV-03).
    expect(await dispatcher.drainOnce(), 1);
    expect(publisher.published, hasLength(1));
    expect(outbox.publishedIds, contains('entry-alerta-1'));
  });

  test('o backoff respeita o teto de 60 segundos', () async {
    final outbox = _RecordingOutbox();
    final publisher = _FlakyPublisher(failures: 100);
    await outbox.enqueue(_delivery('alerta-1'));

    final dispatcher = AlertOutboxDispatcher(
      outbox: outbox,
      publisher: publisher,
      clock: () => now,
    );

    for (var i = 0; i < 10; i++) {
      await dispatcher.drainOnce();
    }

    expect(
      outbox.retryAt['entry-alerta-1'],
      now.add(AlertOutboxDispatcher.maxBackoff),
    );
  });

  test('publishNow devolve false quando o broker está fora', () async {
    final outbox = _RecordingOutbox();
    final publisher = _FlakyPublisher(failures: 1);
    await outbox.enqueue(_delivery('alerta-1'));

    final dispatcher = AlertOutboxDispatcher(
      outbox: outbox,
      publisher: publisher,
      clock: () => now,
    );

    // Não lança: o alerta já está gravado, e a varredura assume a entrega.
    expect(await dispatcher.publishNow('alerta-1'), isFalse);
    expect(await dispatcher.publishNow('alerta-1'), isTrue);
  });
}
