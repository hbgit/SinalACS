import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/geo/location_cell.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('deve mostrar a localização atual do ACS e alertas no mapa', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    queue.upsert(testAlert(alertId: 'alert-map-1', riskLevel: 'red', locationCell: testLocationCell));
    queue.upsert(testAlert(alertId: 'alert-map-2', riskLevel: 'yellow', locationCell: testLocationCell));

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: const LatLng(0, 0),
        apiKey: 'test-api-key',
      ),
    ));

    expect(find.text('Mapa operacional'), findsOneWidget);
    expect(find.text('Localização atual'), findsOneWidget);
    expect(find.textContaining('Vermelho'), findsOneWidget);
  });

  testWidgets('deve renderizar rota ativa quando há posição atual e alerta selecionado', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    final alert = testAlert(alertId: 'alert-map-route', riskLevel: 'red', locationCell: testLocationCell);
    queue.upsert(alert);

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: const LatLng(-15.79, -47.88),
        apiKey: 'test-api-key',
      ),
    ));

    await tester.tap(find.text('Traçar rota eficiente'));
    await tester.pump();

    expect(find.textContaining('Rota ativa'), findsOneWidget);
  });

  testWidgets('deve indicar rota concluída quando o ACS chegou ao destino', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    final alert = testAlert(alertId: 'alert-map-arrival', riskLevel: 'yellow', locationCell: testLocationCell);
    queue.upsert(alert);

    final destination = parseLocationCell(testLocationCell)!;

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: destination,
        apiKey: 'test-api-key',
      ),
    ));

    await tester.tap(find.text('Traçar rota eficiente'));
    await tester.pump();

    expect(find.textContaining('Rota concluída'), findsOneWidget);
    expect(find.text('Registrar visita no local'), findsOneWidget);
  });

  testWidgets('alerta sem célula não ganha marcador nem círculo de incerteza', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    queue.upsert(testAlert(alertId: 'alert-com-celula', riskLevel: 'red', locationCell: testLocationCell));
    // GPS indisponível no paciente: sem locationCell, nada deve ser desenhado
    // para este alerta — nunca uma posição fabricada a partir do hash.
    queue.upsert(testAlert(alertId: 'alert-sem-celula', riskLevel: 'red'));

    await tester.pumpWidget(MaterialApp(
      home: MapScreen(
        queue: queue,
        currentPosition: const LatLng(0, 0),
        apiKey: 'test-api-key',
      ),
    ));

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    final markerIds = map.markers.map((marker) => marker.markerId.value).toSet();
    final circleIds = map.circles.map((circle) => circle.circleId.value).toSet();

    expect(markerIds, contains('alert_alert-com-celula'));
    expect(markerIds, isNot(contains('alert_alert-sem-celula')));
    expect(circleIds, contains('cell_alert-com-celula'));
    expect(circleIds, isNot(contains('cell_alert-sem-celula')));
  });

  testWidgets('geofencing bloqueia o registro sem localização atual', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    queue.upsert(testAlert(alertId: 'alert-geofence-unavailable', riskLevel: 'yellow'));

    await tester.pumpWidget(MaterialApp(
      home: GeofencingScreen(queue: queue),
    ));

    expect(find.textContaining('Localização atual indisponível'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('geofence_visit'))).onPressed, isNull);
  });

  testWidgets('geofencing libera o registro quando o ACS chega ao destino', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    final alert = testAlert(alertId: 'alert-geofence-arrived', riskLevel: 'green', locationCell: testLocationCell);
    queue.upsert(alert);

    final destination = parseLocationCell(testLocationCell)!;
    PrioritizedAlert? selected;

    await tester.pumpWidget(MaterialApp(
      home: GeofencingScreen(
        queue: queue,
        currentPosition: destination,
        onVisit: (value) => selected = value,
      ),
    ));

    expect(find.text('Local alcançado. O registro da visita está liberado.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('geofence_visit'))).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('geofence_visit')));
    expect(selected?.alertId, alert.alertId);
  });

  testWidgets('geofencing bloqueia o registro quando o alerta não tem célula, mesmo com posição do ACS', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    // GPS indisponível no paciente: mesmo com o ACS posicionado, não há
    // destino contra o qual medir proximidade.
    queue.upsert(testAlert(alertId: 'alert-geofence-sem-celula', riskLevel: 'yellow'));

    await tester.pumpWidget(MaterialApp(
      home: GeofencingScreen(
        queue: queue,
        currentPosition: const LatLng(-15.79, -47.88),
      ),
    ));

    expect(find.textContaining('Localização do paciente indisponível'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('geofence_visit'))).onPressed, isNull);
  });
}
