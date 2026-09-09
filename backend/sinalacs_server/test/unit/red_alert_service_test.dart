import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

class FakeAlertPublisher implements AlertPublisher {
  final List<AlertDelivery> published = [];

  @override
  void publish(AlertDelivery alert) => published.add(alert);
}

class FakeAlertStore implements AlertStore {
  final List<AlertDelivery> saved = [];

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async => saved.add(alert);

  @override
  Future<bool> acknowledge({required String alertId, required String acsId, required String microAreaId}) async => true;

  // Deduplicação agora vive no armazenamento, então o fake a implementa em
  // memória — mesma semântica, sem Postgres.
  final Map<String, RedAlertRecord> keys = {};

  @override
  Future<RedAlertRecord?> findByIdempotencyKey(String idempotencyKey) async =>
      keys[idempotencyKey];

  @override
  Future<void> rememberIdempotencyKey(RedAlertRecord record) async =>
      keys[record.idempotencyKey] = record;
}


/// Outbox em memória. Substitui o antigo FakeAlertPublisher no papel de
/// "onde a entrega foi parar": o serviço agora enfileira em vez de publicar.
class FakeAlertOutbox implements AlertOutbox {
  final List<AlertDelivery> enqueued = [];
  final List<PendingDelivery> claimed = [];
  final Set<String> published = {};
  final Map<String, String> failures = {};
  var _nextId = 0;

  @override
  Future<void> enqueue(AlertDelivery alert) async => enqueued.add(alert);

  @override
  Future<List<PendingDelivery>> claimDue({int limit = 32}) async {
    final due = enqueued
        .where((a) => !published.contains(a.alertId))
        .take(limit)
        .map((a) => PendingDelivery(
              entryId: 'entry-${_nextId++}',
              delivery: a,
              attempts: 1,
            ))
        .toList();
    claimed.addAll(due);
    return due;
  }

  @override
  Future<void> markPublished(String entryId) async {
    final entry = claimed.firstWhere((e) => e.entryId == entryId);
    published.add(entry.delivery.alertId);
  }

  @override
  Future<void> markFailed(
    String entryId,
    String error,
    DateTime nextAttemptAt,
  ) async =>
      failures[entryId] = error;
}

void main() {
  final patient = AuthenticatedUser(
    id: 'patient-001',
    role: UserRole.patient,
    microAreaId: 'area-12',
    deviceId: 'device-001',
  );

  test('publica alerta vermelho uma única vez para a microárea do paciente', () async {
    final outbox = FakeAlertOutbox();
    final store = FakeAlertStore();
    final service = RedAlertService(
      outbox: outbox,
      store: store,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final first = await service.create(user: patient, idempotencyKey: 'request-001', locationHash: '6gyf4bf');
    final duplicate = await service.create(user: patient, idempotencyKey: 'request-001', locationHash: '6gyf4bf');

    expect(first.delivery.microAreaId, 'area-12');
    expect(first.delivery.riskLevel, 'red');
    expect(duplicate.delivery.alertId, first.delivery.alertId);
    expect(store.saved, hasLength(1));
    // O serviço enfileira em vez de publicar: uma entrada por alerta, e a
    // segunda chamada com a mesma chave não gera outra.
    expect(outbox.enqueued, hasLength(1));
  });

  test('rejeita usuários que não sejam pacientes territorializados', () async {
    final service =
        RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());
    final acs = AuthenticatedUser(id: 'acs-001', role: UserRole.acs, microAreaId: 'area-12', deviceId: 'device-001');

    expect(
      () async => service.create(user: acs, idempotencyKey: 'request-001', locationHash: '6gyf4bf'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejeita reutilização de idempotência com localização diferente', () async {
    final outbox = FakeAlertOutbox();
    final service = RedAlertService(
      outbox: outbox,
      store: FakeAlertStore(),
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    await service.create(user: patient, idempotencyKey: 'request-duplicate', locationHash: '6gyf4bf');

    expect(
      () async => service.create(user: patient, idempotencyKey: 'request-duplicate', locationHash: '9abc123'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejeita confirmação com identificador de alerta vazio', () async {
    final service =
        RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());
    final acs = AuthenticatedUser(id: 'acs-001', role: UserRole.acs, microAreaId: 'area-12', deviceId: 'device-001');

    expect(
      () async => service.acknowledge(user: acs, alertId: ''),
      throwsA(isA<ArgumentError>()),
    );
  });
}