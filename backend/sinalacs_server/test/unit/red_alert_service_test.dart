import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

class FakeAlertPublisher implements AlertPublisher {
  final List<AlertDelivery> published = [];

  @override
  Future<void> publish(AlertDelivery alert) async => published.add(alert);
}

class FakeAlertStore implements AlertStore {
  final List<AlertDelivery> saved = [];

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async => saved.add(alert);

  @override
  Future<bool> acknowledge({required String alertId, required String acsId, required String microAreaId, required AuditEvent audit}) async {
    audits.add(audit);
    return true;
  }

  final List<AuditEvent> audits = [];

  // Deduplicação agora vive no armazenamento, então o fake a implementa em
  // memória — mesma semântica, sem Postgres.
  final Map<String, RedAlertRecord> keys = {};

  @override
  Future<RedAlertRecord?> findByIdempotencyKey(String idempotencyKey) async =>
      keys[idempotencyKey];

  @override
  Future<void> rememberIdempotencyKey(RedAlertRecord record) async =>
      keys[record.idempotencyKey] = record;

  final Map<String, AlertStatusSnapshot> statusByPatient = {};

  @override
  Future<AlertStatusSnapshot?> latestForPatient(String patientId) async =>
      statusByPatient[patientId];

  /// Desfecho que o "banco" decide para o próximo `resolve` (#76).
  AlertResolveOutcome resolveOutcome = AlertResolveOutcome.resolved;
  final List<({String alertId, String microAreaId, DateTime now})> resolveCalls = [];

  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    resolveCalls.add((alertId: alertId, microAreaId: microAreaId, now: now));
    // Mesma regra do store real: inexistente/fora do território não grava.
    if (resolveOutcome != AlertResolveOutcome.notFound) {
      audits.add(auditFor(resolveOutcome));
    }
    final carimbo = switch (resolveOutcome) {
      AlertResolveOutcome.resolved || AlertResolveOutcome.alreadyResolved => now,
      _ => null,
    };
    return AlertResolveAttempt(resolveOutcome, resolvedAt: carimbo);
  }
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

  test('propaga locationCell quando informado', () async {
    final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());
    final record = await service.create(
      user: patient,
      idempotencyKey: 'key-1',
      locationHash: 'hash-1',
      locationCell: '-1580:-4783',
    );
    expect(record.delivery.locationCell, '-1580:-4783');
  });

  test('locationCell ausente não impede o alerta (GPS indisponível)', () async {
    final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());
    final record = await service.create(
      user: patient,
      idempotencyKey: 'key-2',
      locationHash: 'sem-local-00',
    );
    expect(record.delivery.locationCell, isNull);
  });

  test('rejeita locationCell com coordenada decimal em vez de célula inteira', () async {
    final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());

    expect(
      () async => service.create(
        user: patient,
        idempotencyKey: 'key-cell-decimal',
        locationHash: 'hash-decimal',
        locationCell: '-23.55:-46.63',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejeita locationCell com lixo arbitrário', () async {
    final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());

    expect(
      () async => service.create(
        user: patient,
        idempotencyKey: 'key-cell-lixo',
        locationHash: 'hash-lixo',
        locationCell: 'nao-e-uma-celula',
      ),
      throwsA(isA<ArgumentError>()),
    );
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

  group('resolve (#76)', () {
    const acs = AuthenticatedUser(
      id: 'acs-001',
      role: UserRole.acs,
      microAreaId: 'area-12',
      deviceId: 'device-001',
    );
    final agora = DateTime.utc(2026, 10, 16, 14);

    RedAlertService servico(FakeAlertStore store) => RedAlertService(
          store: store,
          outbox: FakeAlertOutbox(),
          clock: () => agora,
        );

    test('conclui no território do token e audita resolved', () async {
      final store = FakeAlertStore();

      final r = await servico(store).resolve(user: acs, alertId: 'alerta-1');

      expect(r.outcome, AlertResolveOutcome.resolved);
      expect(r.resolvedAt, agora);
      expect(store.resolveCalls.single.microAreaId, 'area-12');
      expect(store.resolveCalls.single.now, agora);
      final audit = store.audits.single;
      expect(audit.userId, 'acs-001');
      expect(audit.actionType, 'write');
      expect(audit.resourceType, 'alert');
      expect(audit.resourceId, 'alerta-1');
      expect(audit.result, 'resolved');
    });

    test('repetir a conclusão é idempotente e audita already_resolved', () async {
      final store = FakeAlertStore()..resolveOutcome = AlertResolveOutcome.alreadyResolved;

      final r = await servico(store).resolve(user: acs, alertId: 'alerta-1');

      expect(r.outcome, AlertResolveOutcome.alreadyResolved);
      expect(store.audits.single.result, 'already_resolved');
    });

    test('alerta ainda pending é recusado com a mensagem e a recusa é auditada', () async {
      final store = FakeAlertStore()..resolveOutcome = AlertResolveOutcome.notAcknowledged;

      await expectLater(
        servico(store).resolve(user: acs, alertId: 'alerta-1'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          RedAlertService.notAcknowledgedMessage,
        )),
      );
      expect(store.audits.single.result, 'denied_not_acknowledged');
    });

    test('alerta inexistente ou de outra microárea devolve notFound sem auditar', () async {
      final store = FakeAlertStore()..resolveOutcome = AlertResolveOutcome.notFound;

      final r = await servico(store).resolve(user: acs, alertId: 'alerta-1');

      expect(r.outcome, AlertResolveOutcome.notFound);
      expect(r.resolvedAt, isNull);
      expect(store.audits, isEmpty);
    });

    test('paciente não conclui atendimento', () async {
      final store = FakeAlertStore();
      const paciente = AuthenticatedUser(
        id: 'paciente-1',
        role: UserRole.patient,
        microAreaId: 'area-12',
        deviceId: 'device-1',
      );

      await expectLater(
        servico(store).resolve(user: paciente, alertId: 'alerta-1'),
        throwsA(isA<StateError>()),
      );
      expect(store.resolveCalls, isEmpty);
    });

    test('ACS sem microárea não conclui atendimento', () async {
      final store = FakeAlertStore();
      const semArea = AuthenticatedUser(
        id: 'acs-002',
        role: UserRole.acs,
        microAreaId: null,
        deviceId: 'device-2',
      );

      await expectLater(
        servico(store).resolve(user: semArea, alertId: 'alerta-1'),
        throwsA(isA<StateError>()),
      );
      expect(store.resolveCalls, isEmpty);
    });

    test('identificador vazio é recusado antes do store', () async {
      final store = FakeAlertStore();

      await expectLater(
        servico(store).resolve(user: acs, alertId: '  '),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.resolveCalls, isEmpty);
    });
  });

  group('statusFor (RF05)', () {
    test('devolve o status guardado para o paciente do token, não por parâmetro', () async {
      final store = FakeAlertStore()
        ..statusByPatient['paciente-1'] = AlertStatusSnapshot(
          alertId: 'alerta-1',
          riskLevel: RiskLevel.red,
          status: AlertStatus.pending,
          triggeredAt: DateTime.utc(2026, 9, 18, 9),
        );
      final service = RedAlertService(store: store, outbox: FakeAlertOutbox());

      final status = await service.statusFor(
        user: const AuthenticatedUser(
          id: 'paciente-1',
          role: UserRole.patient,
          microAreaId: 'area-1',
          deviceId: 'device-1',
        ),
      );

      expect(status?.alertId, 'alerta-1');
      expect(status?.status, AlertStatus.pending);
    });

    test('paciente que nunca disparou alerta recebe null, não erro', () async {
      final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());

      final status = await service.statusFor(
        user: const AuthenticatedUser(
          id: 'paciente-sem-alerta',
          role: UserRole.patient,
          microAreaId: 'area-1',
          deviceId: 'device-1',
        ),
      );

      expect(status, isNull);
    });

    test('um ACS não pode consultar status de paciente', () async {
      final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());

      expect(
        () => service.statusFor(
          user: const AuthenticatedUser(
            id: 'acs-1',
            role: UserRole.acs,
            microAreaId: 'area-1',
            deviceId: 'device-1',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('acknowledge entrega ao store o evento de auditoria, sem PII (#44)', () async {
      final store = FakeAlertStore();
      final service = RedAlertService(store: store, outbox: FakeAlertOutbox());

      final ok = await service.acknowledge(
        user: const AuthenticatedUser(
          id: 'acs-1',
          role: UserRole.acs,
          microAreaId: 'area-1',
          deviceId: 'device-1',
        ),
        alertId: 'alerta-1',
      );

      expect(ok, isTrue);
      final e = store.audits.single;
      expect(
        [e.userId, e.actionType, e.resourceType, e.resourceId, e.result],
        ['acs-1', 'write', 'alert', 'alerta-1', 'acknowledged'],
      );
    });

    test(
      'ACK que chega por MQTT (sentinela de server.dart) é auditado como '
      'acknowledged_mqtt, não como o ACK autenticado do RPC (F3)',
      () async {
        final store = FakeAlertStore();
        final service = RedAlertService(store: store, outbox: FakeAlertOutbox());

        final ok = await service.acknowledge(
          user: const AuthenticatedUser(
            id: 'acs-1',
            role: UserRole.acs,
            microAreaId: 'area-1',
            deviceId: 'mqtt',
          ),
          alertId: 'alerta-1',
        );

        expect(ok, isTrue);
        final e = store.audits.single;
        expect(
          [e.userId, e.actionType, e.resourceType, e.resourceId, e.result],
          ['acs-1', 'write', 'alert', 'alerta-1', 'acknowledged_mqtt'],
        );
      },
    );
  });
}