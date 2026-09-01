import 'package:sinalacs_backend/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_backend/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_backend/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_backend/src/domain/enums/user_role.dart';
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
}

void main() {
  group('Red alert lifecycle', () {
    test('paciente cria alerta e ACS confirma recebimento da mesma microárea', () async {
      final auth = DevelopmentAuthService(secret: 'test-secret');
      final publisher = RecordingPublisher();
      final store = RecordingStore();
      final service = RedAlertService(publisher: publisher, store: store, clock: () => DateTime.utc(2026, 9, 1, 12));

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
      expect(publisher.published, hasLength(1));

      final acknowledged = await service.acknowledge(user: acs, alertId: created.delivery.alertId);
      expect(acknowledged, isTrue);
      expect(store.acknowledgedAlertIds, contains(created.delivery.alertId));
    });
  });
}
