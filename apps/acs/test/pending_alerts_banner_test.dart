import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/pending_alerts_banner.dart';

void main() {
  Widget host(ValueNotifier<int> n) => MaterialApp(
        theme: buildAcsDarkTheme(),
        home: Scaffold(
          body: PendingAlertsBanner(listenable: n, count: () => n.value),
        ),
      );

  testWidgets('sem alerta pendente não mostra nada', (t) async {
    await t.pumpWidget(host(ValueNotifier(0)));
    expect(find.byKey(const Key('reauth_pending_alerts')), findsNothing);
  });

  testWidgets('mostra a contagem e acompanha as mudanças', (t) async {
    final n = ValueNotifier(1);
    await t.pumpWidget(host(n));
    expect(find.text('1 alerta vermelho aguardando. Entre para ver.'), findsOneWidget);

    n.value = 3;
    await t.pump();
    expect(find.text('3 alertas vermelhos aguardando. Entre para ver.'), findsOneWidget);

    n.value = 0;
    await t.pump();
    expect(find.byKey(const Key('reauth_pending_alerts')), findsNothing);
  });

  testWidgets('é região viva (SC 4.1.3)', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host(ValueNotifier(2)));
    // O nó de semântica é o do `Semantics` interno, não o do `Material` com a chave.
    expect(
      t.getSemantics(find.bySemanticsLabel('2 alertas vermelhos aguardando. Entre para ver.')),
      matchesSemantics(isLiveRegion: true, label: '2 alertas vermelhos aguardando. Entre para ver.'),
    );
    h.dispose();
  });
}
