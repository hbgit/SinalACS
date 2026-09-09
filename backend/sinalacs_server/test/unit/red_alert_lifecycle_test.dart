import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

class RecordingPublisher implements AlertPublisher {
  final List<AlertDelivery> published = [];

  @override
  void publish(AlertDelivery alert) => published.add(alert);
}

class RecordingStore implements AlertStore {
  final List<AlertDelivery> saved = [];
  final Set<String> acknowledgedAlertIds = <String>{};

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async => saved.add(alert);

  @override
  Future<bool> acknowledge({required String alertId, required String acsId, required String microAreaId}) async {
    if (alertId.trim().isEmpty) return false;
    acknowledgedAlertIds.add(alertId);
    return true;
  }

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
  group('Red alert lifecycle', () {
    test('paciente cria alerta e ACS confirma recebimento da mesma microárea', () async {
      final auth = DevelopmentAuthService(secret: 'test-secret');
      final publisher = RecordingPublisher();
      final outbox = FakeAlertOutbox();
      final store = RecordingStore();
      final service = RedAlertService(store: store, outbox: outbox, clock: () => DateTime.utc(2026, 9, 1, 12));

      final patient = AuthenticatedUser(
        id: 'patient-001',
        role: UserRole.patient,
        microAreaId: 'area-12',
        deviceId: 'device-001',
      );
      final acs = AuthenticatedUser(
        id: 'acs-001',
        role: UserRole.acs,
        microAreaId: 'area-12',
        deviceId: 'device-acs-001',
      );

      final token = auth.issueToken(patient, now: DateTime.utc(2026, 9, 1, 12, 1));
      final verifiedPatient = auth.verifyToken(token, now: DateTime.utc(2026, 9, 1, 12, 2));
      expect(verifiedPatient?.id, patient.id);
      expect(verifiedPatient?.microAreaId, 'area-12');

      final created = await service.create(
        user: patient,
        idempotencyKey: 'req-lifecycle-001',
        locationHash: '6gyf4bf',
      );

      expect(created.delivery.riskLevel, 'red');
      expect(created.delivery.microAreaId, 'area-12');
      expect(store.saved, hasLength(1));
      // O serviço enfileira; a publicação só acontece quando o drenador roda,
      // que é o que garante que nada é entregue antes do commit.
      expect(outbox.enqueued, hasLength(1));
      expect(publisher.published, isEmpty);

      final dispatcher =
          AlertOutboxDispatcher(outbox: outbox, publisher: publisher);
      expect(await dispatcher.drainOnce(), 1);
      expect(publisher.published, hasLength(1));

      final acknowledged = await service.acknowledge(user: acs, alertId: created.delivery.alertId);
      expect(acknowledged, isTrue);
      expect(store.acknowledgedAlertIds, contains(created.delivery.alertId));
    });
  });
}
