import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';

void main() {
  testWidgets('deve listar microáreas com o ACS vinculado, somente leitura', (tester) async {
    await tester.pumpWidget(SinalAdminApp());
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Microáreas').last);
    await tester.pumpAndSettle();

    expect(find.text('Microárea 12 — Zona Rural'), findsOneWidget);
    expect(find.text('ACS: Carla Nogueira (ACS-001)'), findsOneWidget);
    expect(find.text('Microárea 03 — Vila Esperança'), findsOneWidget);
    expect(find.text('Sem ACS ativo'), findsOneWidget);

    // Somente leitura: nenhum botão de edição de vínculo nesta issue.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
}
