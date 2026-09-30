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

/// Quanto segurar o app instalado depois do registro (`--dart-define=PUSH_HOLD_SECONDS=N`).
///
/// O `flutter test integration_test` DESINSTALA o app ao terminar, e o token FCM
/// morre junto (o FCM passa a responder `NotRegistered`). Para provar a ENTREGA o
/// app precisa continuar instalado enquanto `tool/send_notice.dart` envia, então
/// `scripts/qa/push_e2e.sh` usa este intervalo. O padrão, 0, não espera nada.
const _holdSeconds = int.fromEnvironment('PUSH_HOLD_SECONDS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('registra no backend o token FCM real do aparelho, com consentimento', timeout: const Timeout(Duration(minutes: 6)), () async {
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

    if (_holdSeconds > 0) {
      // Sinal para o script: o registro terminou e o app fica instalado daqui em diante.
      // ignore: avoid_print
      print('PUSH_E2E_REGISTERED');
      await Future<void>.delayed(const Duration(seconds: _holdSeconds));
    }
  });
}
