import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';

void main() {
  testWidgets('deve registrar e exibir o próprio acesso do admin às telas sensíveis', (tester) async {
    await tester.pumpWidget(SinalAdminApp());
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    // Visitar Microáreas e Alertas antes da Auditoria — cada visita deve gerar
    // uma entrada própria via AdminDataSource.recordAccess (PRD §4.2.2).
    await tester.tap(find.text('Microáreas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auditoria').last);
    await tester.pumpAndSettle();

    expect(find.text('Logs de auditoria'), findsOneWidget);
    expect(find.text('view • micro_areas'), findsOneWidget);
    expect(find.text('view • alerts'), findsOneWidget);
    expect(find.text('view • audit_logs'), findsOneWidget);
    expect(find.textContaining('admin.dev (Administrador)'), findsWidgets);
  });
}
