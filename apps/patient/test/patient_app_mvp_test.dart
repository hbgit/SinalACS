import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';

void main() {
  testWidgets('deve abrir a triagem do paciente e classificar risco', (tester) async {
    await tester.pumpWidget(const SinalAcsApp());

    expect(find.text('SinalACS'), findsOneWidget);
    expect(find.text('Acesso do paciente'), findsOneWidget);

    await tester.tap(find.byKey(const Key('enter_button')));
    await tester.pumpAndSettle();

    expect(find.text('Triagem rápida'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chest_pain')));
    await tester.tap(find.byKey(const Key('difficulty_breathing')));
    await tester.scrollUntilVisible(find.byKey(const Key('submit_triage')), 50);
    await tester.tap(find.byKey(const Key('submit_triage')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Risco'), findsWidgets);
  });

  testWidgets('deve expor rótulo semântico e alvo de toque acessível no fluxo do paciente', (tester) async {
    await tester.pumpWidget(const SinalAcsApp());

    final enterButton = tester.widget<FilledButton>(find.byKey(const Key('enter_button')));
    final minimumSize = enterButton.style?.minimumSize?.resolve({}) ?? const Size(0, 0);

    expect(find.bySemanticsLabel('Entrar na triagem do paciente'), findsOneWidget);
    expect(minimumSize.height, greaterThanOrEqualTo(48));
    expect(minimumSize.width, greaterThanOrEqualTo(48));
  });
}
