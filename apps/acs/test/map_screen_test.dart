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
}
