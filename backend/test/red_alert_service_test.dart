import 'package:sinalacs_backend/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_backend/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_backend/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_backend/src/domain/enums/user_role.dart';
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
}

void main() {
  final patient = AuthenticatedUser(
    id: 'patient-001',
    role: UserRole.patient,
    microAreaId: 'area-12',
    deviceId: 'device-001',
  );

  test('publica alerta vermelho uma única vez para a microárea do paciente', () async {
    final publisher = FakeAlertPublisher();
    final store = FakeAlertStore();
    final service = RedAlertService(
      publisher: publisher,
      store: store,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    final first = await service.create(user: patient, idempotencyKey: 'request-001', locationHash: '6gyf4bf');
    final duplicate = await service.create(user: patient, idempotencyKey: 'request-001', locationHash: '6gyf4bf');

    expect(first.delivery.microAreaId, 'area-12');
    expect(first.delivery.riskLevel, 'red');
    expect(duplicate.delivery.alertId, first.delivery.alertId);
    expect(store.saved, hasLength(1));
    expect(publisher.published, hasLength(1));
  });

  test('rejeita usuários que não sejam pacientes territorializados', () async {
    final publisher = FakeAlertPublisher();
    final service = RedAlertService(publisher: publisher, store: FakeAlertStore());
    final acs = AuthenticatedUser(id: 'acs-001', role: UserRole.acs, microAreaId: 'area-12', deviceId: 'device-001');

    expect(
      () async => service.create(user: acs, idempotencyKey: 'request-001', locationHash: '6gyf4bf'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejeita reutilização de idempotência com localização diferente', () async {
    final publisher = FakeAlertPublisher();
    final service = RedAlertService(
      publisher: publisher,
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
    final publisher = FakeAlertPublisher();
    final service = RedAlertService(publisher: publisher, store: FakeAlertStore());
    final acs = AuthenticatedUser(id: 'acs-001', role: UserRole.acs, microAreaId: 'area-12', deviceId: 'device-001');

    expect(
      () async => service.acknowledge(user: acs, alertId: ''),
      throwsA(isA<ArgumentError>()),
    );
  });
}