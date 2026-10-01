import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/emergency_dialer.dart';

import 'support/fakes.dart';

class _FakeDialer implements EmergencyDialer {
  _FakeDialer({this.opens = true, this.throws = false});

  final bool opens;
  final bool throws;
  final dialed = <String>[];

  @override
  Future<bool> dial(String number) async {
    dialed.add(number);
    if (throws) throw StateError('sem discador');
    return opens;
  }
}

class _GatedDialer implements EmergencyDialer {
  _GatedDialer(this._gate, this.dialed);

  final Completer<bool> _gate;
  final List<String> dialed;

  @override
  Future<bool> dial(String number) {
    dialed.add(number);
    return _gate.future;
  }
}

Future<void> _pump(WidgetTester tester, _FakeDialer dialer) => tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscalationScreen(alert: testAlert(alertId: 'a1'), dialer: dialer),
      ),
    ));

void main() {
  testWidgets('o botão do SAMU abre o discador com 192', (tester) async {
    final dialer = _FakeDialer();
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(dialer.dialed, ['192']);
    expect(find.text('Discagem não está integrada neste protótipo.'), findsNothing);
  });

  testWidgets('sem discador, mostra o número em texto em vez de falhar em silêncio', (tester) async {
    final dialer = _FakeDialer(opens: false);
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(find.textContaining('Ligue manualmente para 192'), findsOneWidget);
  });

  testWidgets('um erro do discador cai no mesmo aviso, sem derrubar a tela', (tester) async {
    final dialer = _FakeDialer(throws: true);
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ligue manualmente para 192'), findsOneWidget);
  });

  testWidgets('toque duplo não abre dois discadores', (tester) async {
    // O discador real leva tempo; o segundo toque chega com o primeiro em voo.
    final aberto = Completer<bool>();
    final dialed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscalationScreen(
          alert: testAlert(alertId: 'a1'),
          dialer: _GatedDialer(aberto, dialed),
        ),
      ),
    ));

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();
    await tester.tap(find.text('Ligar para o SAMU (192)'), warnIfMissed: false);
    await tester.pump();
    aberto.complete(true);
    await tester.pump();

    expect(dialed, ['192']);
  });

  testWidgets('o botão da UBS continua sendo o aviso honesto (sem contato cadastrado)', (tester) async {
    await _pump(tester, _FakeDialer());

    await tester.tap(find.text('Encaminhar para UBS Central'));
    await tester.pump();

    expect(find.text('Encaminhamento será integrado à UBS.'), findsOneWidget);
  });
}
