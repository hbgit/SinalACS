import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('deve mostrar a localização atual do ACS e alertas no mapa', (tester) async {
    final queue = AlertQueue(microAreaId: seedMicroAreaId);
    queue.upsert(testAlert(alertId: 'alert-map-1', riskLevel: 'red'));
    queue.upsert(testAlert(alertId: 'alert-map-2', riskLevel: 'yellow'));

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
    final alert = testAlert(alertId: 'alert-map-route', riskLevel: 'red');
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
    final alert = testAlert(alertId: 'alert-map-arrival', riskLevel: 'yellow');
    queue.upsert(alert);

    final hash = alert.locationHash;
    final seed = hash.codeUnits.fold<int>(0, (sum, code) => sum + code) % 1000;
    final destination = LatLng(
      -15.7942 + ((seed % 7) * 0.0025),
      -47.8828 + (((seed ~/ 7) % 9) * 0.0035),
    );

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
    final alert = testAlert(alertId: 'alert-geofence-arrived', riskLevel: 'green');
    queue.upsert(alert);

    final destination = MapScreen.alertPositionFor(alert);
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
}
