import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('deve abrir a tela de login do ACS', (tester) async {
    // O backend é injetado para manter o teste hermético: sem duplo, o app
    // construiria o cliente real e tentaria falar com a rede.
    await tester.pumpWidget(SinalAcsApp(
      backend: FakeAcsBackend(),
      feedBuilder: (queue) => FakeAlertFeed(queue),
    ));

    expect(find.text('SinalACS'), findsOneWidget);
    expect(find.byKey(const Key('matricula_field')), findsOneWidget);
    expect(find.byKey(const Key('senha_field')), findsOneWidget);
  });
}
