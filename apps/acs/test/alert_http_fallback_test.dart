import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_http_fallback.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';

void main() {
  AcsOpenAlert aberto(String id) => AcsOpenAlert(
        alertId: id,
        patientId: seedPatientId,
        microAreaId: seedMicroAreaId,
        riskLevel: RiskLevel.red,
        locationHash: 'hash-sintetico',
        triggeredAt: DateTime.utc(2026, 10, 17, 12),
        status: AlertStatus.pending,
        escalated: false,
      );

  test('poll funde a resposta do backend', () async {
    final backend = FakeAcsBackend()..openAlertsResult = [aberto('x')];
    final queue = AlertQueue(microAreaId: seedMicroAreaId);

    expect(await AlertHttpFallback(backend: backend, queue: queue).poll(), 1);
    expect(queue.alerts.single.alertId, 'x');
    expect(backend.openAlertsCalls, 1);
  });

  test('falha do backend sobe como BackendFailure e não mexe na fila', () async {
    final backend = FakeAcsBackend()..openAlertsFailure = const BackendFailure('Sem conexão com o servidor.');
    final queue = AlertQueue(microAreaId: seedMicroAreaId);

    await expectLater(
      AlertHttpFallback(backend: backend, queue: queue).poll(),
      throwsA(isA<BackendFailure>()),
    );
    expect(queue.isEmpty, isTrue);
  });
}
