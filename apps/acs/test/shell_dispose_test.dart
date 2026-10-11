import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';

import 'support/fakes.dart';

/// Feed que avisa a desconexão ao parar, como o `MqttAlertFeed` real faz:
/// `stop()` → `MqttClient.disconnect` → `onConnectionChanged(false)`.
class _FeedQueAvisaAoParar extends FakeAlertFeed {
  _FeedQueAvisaAoParar(super.queue);

  @override
  void stop() {
    super.stop();
    onConnectionChanged?.call(false);
  }
}

void main() {
  testWidgets('desmontar o painel não chama setState nele mesmo ao parar o feed', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakeAcsBackend(),
      feedBuilder: (queue) => _FeedQueAvisaAoParar(queue),
    ));
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('ACS •'), findsOneWidget, reason: 'o painel precisa estar aberto');

    await tester.pumpWidget(const SizedBox.shrink());

    expect(tester.takeException(), isNull);
  });
}
