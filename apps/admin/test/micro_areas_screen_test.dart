import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

void main() {
  testWidgets('deve listar microáreas com o ACS vinculado e a gestão das contas de ACS', (tester) async {
    await tester.pumpWidget(SinalAdminApp(auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);

    await tester.tap(find.text('Microáreas').last);
    await tester.pumpAndSettle();

    expect(find.text('Microárea 12 — Zona Rural'), findsOneWidget);
    expect(find.text('ACS: Carla Nogueira (ACS-001)'), findsOneWidget);
    expect(find.text('Microárea 03 — Vila Esperança'), findsOneWidget);
    expect(find.text('Sem ACS ativo'), findsOneWidget);

    // A tela deixou de ser somente leitura (#43): cadastro e vínculo de ACS
    // vivem aqui agora. O que continua fora dela é a classificação de risco —
    // a triagem é determinística e não se altera por tela nenhuma (PRD §2.4).
    expect(find.byKey(const Key('novo_acs')), findsOneWidget);
    expect(find.byKey(const Key('vincular_acs_acs-1')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<RiskLevel>), findsNothing);
  });
}
