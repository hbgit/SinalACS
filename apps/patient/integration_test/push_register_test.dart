/// Registra no backend REAL o token FCM REAL do aparelho, com consentimento (RF14).
/// Pré-requisitos: a stack de pé com `ENABLE_DEV_LOGIN=true`, Play Services, o
/// `google-services.json` no build e `adb reverse tcp:8443 tcp:443` (ver
/// `scripts/qa/push_e2e.sh`). Nunca imprime o token.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show ConsentPurpose;
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';
import 'package:sinalacs_patient/core/push/native_push_token_source.dart';

Future<List<int>?> _devRpcCaBytes() async {
  try {
    final data = await rootBundle.load(BackendConfig.rpcCaAsset);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('registra no backend o token FCM real do aparelho, com consentimento', () async {
    final caBytes = await _devRpcCaBytes();
    if (caBytes == null) {
      fail('A CA do RPC não está no bundle (${BackendConfig.rpcCaAsset}). '
          'Rode ./scripts/dev/sync_dev_ca.sh com a stack de pé.');
    }
    final backend = BackendClient(trustedCaBytes: caBytes);
    addTearDown(backend.close);
    await backend.developmentLogin(role: 'patient');

    final device = await const NativePushTokenSource()
        .currentDevice()
        .timeout(const Duration(seconds: 60));
    expect(device, isNotNull, reason: 'sem token FCM real: rode a Task 2 antes');

    // Desfaz qualquer consentimento de uma rodada anterior: o teste parte de "sem".
    await backend.updateConsent(purpose: ConsentPurpose.segmentedPush, granted: false);

    // Sem consentimento, o servidor recusa e nada é gravado.
    await expectLater(
      backend.registerPushToken(token: device!.token, platform: device.platform),
      throwsA(isA<BackendFailure>()),
    );

    await backend.updateConsent(purpose: ConsentPurpose.segmentedPush, granted: true);
    await backend.registerPushToken(token: device.token, platform: device.platform); // não lança
  });
}
