import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/geo/location_cell.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _patientId = '00000000-0000-4000-8000-000000000001';
const _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// Célula de teste com centro determinístico (ver
/// `apps/acs/test/location_cell_test.dart`).
const _testLocationCell = '-1580:-4783';

PrioritizedAlert _alert(String id) => PrioritizedAlert(
      alertId: id,
      patientId: _patientId,
      microAreaId: _microAreaId,
      riskLevel: 'yellow',
      locationHash: 'sem-local-$id',
      locationCell: _testLocationCell,
      triggeredAt: DateTime.utc(2026, 9, 12, 8),
    );

PrioritizedAlert _redAlert(String id) => PrioritizedAlert(
      alertId: id,
      patientId: _patientId,
      microAreaId: _microAreaId,
      riskLevel: 'red',
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
        apiKey: _googleMapsApiKey,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mapa operacional'), findsOneWidget);
    if (_googleMapsApiKey.isEmpty) {
      expect(find.textContaining('Mapa operacional indisponível sem chave'), findsOneWidget);
    } else {
      expect(find.byType(GoogleMap), findsOneWidget);
    }

    await tester.tap(find.text('Traçar rota eficiente'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Rota ativa'), findsOneWidget);
    queue.dispose();
  });

  testWidgets('mapa e geofencing liberam visita quando o ACS chega', (tester) async {
    final queue = AlertQueue(microAreaId: _microAreaId);
    final alert = _alert('map-arrived');
    queue.upsert(alert);
    final destination = parseLocationCell(_testLocationCell)!;
    PrioritizedAlert? selected;

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: destination,
        apiKey: _googleMapsApiKey,
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

  testWidgets('escalonamento mantém SAMU primário e encaminha alerta vermelho para visita', (tester) async {
    final alert = _redAlert('red-escalation-visit');
    PrioritizedAlert? selected;

    await tester.pumpWidget(MaterialApp(
      home: EscalationScreen(
        alert: alert,
        onVisit: (value) => selected = value,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ligar para o SAMU (192)'), findsOneWidget);
    expect(find.text('Iniciar rota de visita'), findsOneWidget);
    expect(find.textContaining('não substitui o acionamento do SAMU'), findsOneWidget);

    await tester.tap(find.byKey(const Key('escalation_visit')));
    expect(selected?.alertId, alert.alertId);
  });
}
