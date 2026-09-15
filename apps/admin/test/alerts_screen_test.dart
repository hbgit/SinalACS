import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

void main() {
  testWidgets('deve filtrar alertas por microárea sem permitir reclassificação de risco', (tester) async {
    await tester.pumpWidget(SinalAdminApp());
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();

    expect(find.text('Alertas da UBS'), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('alerts_micro_area_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Microárea 12 — Zona Rural').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('alert_alert-1')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-2')), findsOneWidget);
    expect(find.byKey(const Key('alert_alert-3')), findsNothing);

    // Consulta somente leitura: não há dropdown/campo para alterar RiskLevel.
    expect(find.byType(DropdownButtonFormField<RiskLevel>), findsNothing);
  });
}
