/// RF12 no aparelho: a PERMISSÃO de localização em runtime e o que a tela faz
/// com ela. Cenário e pré-requisitos em `scripts/qa/acs_gps_e2e.sh` (concede ou
/// revoga a permissão por `pm` antes de rodar). `--dart-define=EXPECT_PERMISSION=granted|denied_forever`.
///
/// O que isto prova: `pm grant` só funciona se o manifesto DECLARA a permissão
/// (o defeito que o `android_manifest_test.dart` guarda), e o app, com ela,
/// enxerga `whileInUse`; sem ela, a tela diz "indisponível" e não trava.
/// O que NÃO prova: a chegada de um fix de GPS. No AVD usado (Android 16, Play
/// Services) nem `adb emu geo fix`, nem provider de teste, nem
/// `forceLocationManager` entregam posição ao app; "Local alcançado" com posição
/// segue coberto por `map_flow_test.dart` e pelos widget tests (posição injetada).
///
/// Sufixo `_e2e.dart` (não `_test.dart`) de propósito: `flutter test
/// integration_test` descobre `*_test.dart` por pasta, e este arquivo só faz
/// sentido pelo script.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';

import '../test/support/fakes.dart';

const _expect = String.fromEnvironment('EXPECT_PERMISSION', defaultValue: 'granted');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a permissão de localização no aparelho ($_expect)', (tester) async {
    final alert = testAlert(alertId: 'gps-1', locationCell: testLocationCell);

    final permission = await Geolocator.checkPermission();
    if (_expect == 'granted') {
      expect(permission, anyOf(LocationPermission.whileInUse, LocationPermission.always),
          reason: 'o manifesto precisa declarar ACCESS_FINE_LOCATION para a permissão existir');
    } else {
      // Leva a permissão a negada-de-vez NA MESMA SESSÃO (o `flutter drive` desinstala o app ao
      // terminar, então o estado não sobrevive entre rodadas). Enquanto não está fixada, cada
      // `requestPermission()` abre o diálogo do sistema, que o script do emulador recusa; a
      // segunda recusa a torna permanente e o pedido passa a voltar na hora, sem diálogo.
      expect(permission, isNot(anyOf(LocationPermission.whileInUse, LocationPermission.always)));
      var resposta = await Geolocator.requestPermission();
      for (var i = 0; i < 2 && resposta != LocationPermission.deniedForever; i++) {
        resposta = await Geolocator.requestPermission();
      }
      expect(resposta, LocationPermission.deniedForever);
    }

    await tester.pumpWidget(SinalAcsApp(
      backend: FakeAcsBackend(),
      feedBuilder: (queue) {
        queue.upsert(alert); // `initialAlert` só seleciona; a tela lê a fila
        return FakeAlertFeed(queue);
      },
      initialAlert: alert,
      // `currentPosition` AUSENTE de propósito: a posição tem de vir do Geolocator.
    ));
    await tester.enterText(find.byKey(const Key('matricula_field')), '123456');
    await tester.enterText(find.byKey(const Key('senha_field')), 'qualquer');
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpFor(tester, const Duration(seconds: 3));

    await tester.tap(find.text('Mais'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Geofencing'));
    await _pumpFor(tester, const Duration(seconds: 3));

    if (_expect == 'denied_forever') {
      // Review Focus 1: permissão negada nunca trava o ACS.
      expect(find.textContaining('Localização atual indisponível'), findsOneWidget);
      expect(find.byKey(const Key('geofence_visit')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final fim = DateTime.now().add(d);
  while (DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
