/// Prova, no aparelho, que o canal nativo devolve um token FCM REAL. Precisa de
/// Play Services, internet e do `google-services.json` no build. Nunca imprime o
/// token: só confere forma e tamanho.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_patient/core/push/native_push_token_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('o canal nativo devolve um token FCM real do aparelho', () async {
    final device = await const NativePushTokenSource()
        .currentDevice()
        .timeout(const Duration(seconds: 60));

    expect(device, isNotNull,
        reason: 'sem token: o lado nativo falta, ou o build não tem o google-services.json');
    expect(device!.platform, 'android');
    expect(device.token.length, greaterThan(100));
    expect(device.token.contains(':'), isTrue, reason: 'token FCM tem a forma <id>:<segredo>');
  });
}
