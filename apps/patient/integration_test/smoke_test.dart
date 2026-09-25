/// Smoke do app do paciente no dispositivo — o único arquivo que a CI roda.
///
/// Um teste só, de propósito: cada arquivo de `integration_test/` custa um
/// build e um `adb install` do APK no emulador da CI, e é isso que domina o
/// tempo do job `android-e2e`, não o teste em si. Aqui fica apenas o que só o
/// aparelho prova — o RPC por HTTPS saindo do app, com a CA de desenvolvimento
/// vinda do asset — encadeado no caminho que importa: saúde → login → triagem
/// vermelha → alerta criado e reenvio idempotente.
///
/// O resto da bateria continua em `backend_connection_test.dart`, rodado por
/// `./scripts/qa/e2e.sh --emulator --full`; determinismo e idempotência também
/// são cobertos pelo `dart test` do backend, e o hash de localização por
/// `test/location_hash_test.dart`.
///
/// Mesmos pré-requisitos e `--dart-define` de `backend_connection_test.dart`.
///
/// PRIVACIDADE: só os UUIDs sintéticos do seed; o token nunca é impresso.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_client/sinalacs_client.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';
import 'package:sinalacs_patient/core/network/idempotency.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';

const seedMicroAreaId = '00000000-0000-4000-8000-000000000003';

/// Mesma leitura de `backend_connection_test.dart`: sem a CA no bundle o
/// handshake falha, e o sintoma culparia a rede.
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

  test('smoke: do app ao alerta vermelho, por HTTPS com a CA do asset', () async {
    final caBytes = await _devRpcCaBytes();
    if (caBytes == null) {
      fail(
        'A CA do RPC não está no bundle (${BackendConfig.rpcCaAsset}). Rode '
        './scripts/dev/sync_dev_ca.sh com a stack de pé.',
      );
    }
    final backend = BackendClient(trustedCaBytes: caBytes);
    addTearDown(backend.close);

    final health = await backend.health();
    expect(health.status, 'ok');
    expect(health.dbConnected, isTrue,
        reason: 'sem banco, createRedAlert falha por chave estrangeira');

    final session = await backend.developmentLogin(role: 'patient');
    expect(session.role, 'patient');
    expect(session.microAreaId, seedMicroAreaId);

    final risk = await backend.evaluateTriage(
      chestPain: true,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    expect(risk, RiskLevel.red);

    final key = newIdempotencyKey();
    final hash = locationHashFrom(-23.55052, -46.633308);
    final first = await backend.createRedAlert(idempotencyKey: key, locationHash: hash);
    final retry = await backend.createRedAlert(idempotencyKey: key, locationHash: hash);

    expect(first.alertId, isNotEmpty);
    expect(first.status, AlertStatus.pending);
    // Retry da MESMA tentativa: um segundo alerta seria um chamado duplicado.
    expect(retry.alertId, first.alertId);
  });
}
