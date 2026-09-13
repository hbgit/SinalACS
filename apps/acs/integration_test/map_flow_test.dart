import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _patientId = '00000000-0000-4000-8000-000000000001';

PrioritizedAlert _alert(String id) => PrioritizedAlert(
      alertId: id,
      patientId: _patientId,
      microAreaId: _microAreaId,
      riskLevel: 'yellow',
      locationHash: 'sem-local-$id',
      triggeredAt: DateTime.utc(2026, 9, 12, 8),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mapa operacional mantém rota ativa no emulador', (tester) async {
    final queue = AlertQueue(microAreaId: _microAreaId);
    queue.upsert(_alert('map-active'));

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: const LatLng(-15.79, -47.88),
        apiKey: '',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mapa operacional'), findsOneWidget);
    expect(find.textContaining('Mapa operacional indisponível sem chave'), findsOneWidget);

    await tester.tap(find.text('Traçar rota eficiente'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Rota ativa'), findsOneWidget);
    queue.dispose();
  });

  testWidgets('mapa e geofencing liberam visita quando o ACS chega', (tester) async {
    final queue = AlertQueue(microAreaId: _microAreaId);
    final alert = _alert('map-arrived');
    queue.upsert(alert);
    final destination = MapScreen.alertPositionFor(alert);
    PrioritizedAlert? selected;

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: destination,
        apiKey: '',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Traçar rota eficiente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rota concluída'), findsOneWidget);
    expect(find.byKey(const Key('visit_at_destination')), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: GeofencingScreen(
        queue: queue,
        currentPosition: destination,
        onVisit: (value) => selected = value,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Local alcançado. O registro da visita está liberado.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('geofence_visit')));
    expect(selected?.alertId, alert.alertId);
    queue.dispose();
  });
}
