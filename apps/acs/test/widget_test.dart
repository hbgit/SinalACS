import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('deve abrir a tela de login do ACS', (tester) async {
    await tester.pumpWidget(const SinalAcsApp());

    expect(find.text('SinalACS'), findsOneWidget);
    expect(find.byKey(const Key('matricula_field')), findsOneWidget);
    expect(find.byKey(const Key('senha_field')), findsOneWidget);
  });
}
