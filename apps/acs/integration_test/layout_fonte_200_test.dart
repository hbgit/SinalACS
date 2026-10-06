/// Layout do painel do ACS no aparelho, com a janela e a escala de fonte que o
/// SISTEMA configurou — o contrário de `test/text_scale_test.dart`, que força
/// os dois por `TestPlatformDispatcher`. Aqui a fonte é a real (Roboto), não a
/// Ahem dos testes de widget.
///
/// Hermético: usa `FakeAcsBackend` e `FakeAlertFeed`, sem backend, broker nem
/// seed. Os parâmetros vêm do emulador:
///
///   adb shell settings put system font_scale 2.0
///   adb shell wm size 320x640 && adb shell wm density 160   # 1 dp = 1 px
///   flutter test integration_test/layout_fonte_200_test.dart -d emulator-5554 \
///     --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD"
///   adb shell wm size reset && adb shell wm density reset
///   adb shell settings put system font_scale 1.0
///
/// Sem ajuste nenhum ele passa na escala 1.0 da janela padrão: é um teste de
/// fumaça de layout, não uma prova de 200% por si só (o log imprime o que foi
/// medido).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';
import '../test/support/layout_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('painel inteiro cabe na janela e na fonte do aparelho', (tester) async {
    final escala = tester.platformDispatcher.textScaleFactor;
    final tamanho = tester.view.physicalSize / tester.view.devicePixelRatio;
    // ignore: avoid_print
    print('LAYOUT-DEVICE janela=${tamanho.width.toStringAsFixed(0)}x${tamanho.height.toStringAsFixed(0)}dp escalaDeFonte=$escala');

    // Sem biometria real: no aparelho a retomada de sessão a consultaria e o login
    // ficaria esperando o sistema; o fake indisponível leva ao formulário de senha.
    await abrirPainel(tester, tamanho: tamanho, escalaDeFonte: escala, biometricGate: FakeBiometricGate(available: false));
    await percorrerPainelInteiro(tester, 'aparelho ${tamanho.width.toStringAsFixed(0)}x${tamanho.height.toStringAsFixed(0)} fonte $escala');
  });
}
