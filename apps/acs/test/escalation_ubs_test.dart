import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_scope.dart';
import 'package:sinalacs_acs/core/services/emergency_dialer.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show UbsContact;

import 'support/fakes.dart';

class _Dialer implements EmergencyDialer {
  _Dialer({this.abre = true});
  final bool abre;
  final discados = <String>[];

  @override
  Future<bool> dial(String number) async {
    discados.add(number);
    return abre;
  }
}

Future<void> _abrir(WidgetTester tester, FakeAcsBackend backend, _Dialer dialer) =>
    tester.pumpWidget(MaterialApp(
      home: BackendScope(
        backend: backend,
        child: Scaffold(
          body: EscalationScreen(alert: testAlert(alertId: 'a1'), dialer: dialer),
        ),
      ),
    ));

void main() {
  testWidgets('o botão da UBS abre o discador com o telefone cadastrado, só dígitos e +', (tester) async {
    final backend = FakeAcsBackend();
    final dialer = _Dialer();
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(dialer.discados, ['+551155500100']);
    expect(backend.ubsContactCount, 1);
  });

  testWidgets('UBS sem telefone: avisa e não liga', (tester) async {
    final backend = FakeAcsBackend()..ubsContactResult = UbsContact(name: 'UBS Sem Fone');
    final dialer = _Dialer();
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(dialer.discados, isEmpty);
    expect(find.textContaining('UBS Sem Fone ainda não cadastrou um telefone'), findsOneWidget);
  });

  testWidgets('sem discador, mostra o telefone em texto', (tester) async {
    final backend = FakeAcsBackend();
    final dialer = _Dialer(abre: false);
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ligue manualmente para +55 11 5550-0100'), findsOneWidget);
  });

  testWidgets('falha ao obter o contato mostra a mensagem do backend e não liga', (tester) async {
    final backend = FakeAcsBackend()..ubsContactFailure = const BackendFailure('Sem conexão.');
    final dialer = _Dialer();
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(dialer.discados, isEmpty);
    expect(find.text('Sem conexão.'), findsOneWidget);
  });
}
