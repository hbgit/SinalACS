/// Conexão real do app do paciente com o backend Serverpod.
///
/// Ao contrário dos testes em `test/`, estes NÃO são herméticos: exigem a stack
/// local de pé (`docker compose up`, com o database-seed concluído). Ficam em
/// `integration_test/` justamente por isso — `flutter test` não os executa, e o
/// CI segue hermético.
///
///   flutter test integration_test \
///     --dart-define=SINALACS_HOST=https://10.0.2.2/
///
/// O default é 10.0.2.2, o host da máquina visto de dentro do emulador Android.
/// `./scripts/qa/e2e.sh --emulator` (o caminho da CI) usa `localhost` com
/// `adb reverse tcp:443 tcp:443` em vez disso: medido no runner da CI que
/// 10.0.2.2 não chega ao RPC (a mesma stack respondia por `localhost` rodando
/// no host segundos antes), embora 10.0.2.2 funcione normalmente num emulador
/// local comum.
///
/// O RPC é **HTTPS na 443** (RNF04/L-08) e o certificado é assinado pela CA de
/// desenvolvimento, que chega ao app como asset — é por isso que o caminho
/// pronto (`./scripts/qa/e2e.sh --emulator`) roda o `sync_dev_ca.sh` antes. Sem
/// essa CA o handshake falha, e é o que se quer: o armazenamento do sistema não
/// a conhece, e aceitar qualquer certificado anularia o requisito.
///
/// PRIVACIDADE: só os UUIDs sintéticos do seed. Nenhum dado real de paciente,
/// e o token nunca é impresso.
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

/// Bytes da CA de desenvolvimento do RPC, lidos do bundle do app.
///
/// É o MESMO trabalho que `main.dart` faz: este teste constrói o `BackendClient`
/// por conta própria, então precisa entregar a CA por conta própria também.
/// Ausente, o cliente cai no armazenamento do sistema e o handshake falha — o
/// que apareceria como "sem conexão", culpando a rede por um asset que ninguém
/// copiou.
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

  late BackendClient backend;

  setUp(() async {
    final caBytes = await _devRpcCaBytes();
    if (caBytes == null) {
      fail(
        'A CA do RPC não está no bundle (${BackendConfig.rpcCaAsset}). Rode '
        './scripts/dev/sync_dev_ca.sh com a stack de pé — sem ela o handshake '
        'falha e este teste falaria de rede em vez de falar de asset.',
      );
    }
    backend = BackendClient(trustedCaBytes: caBytes);
  });
  tearDown(() => backend.close());

  test('a stack responde à sonda de saúde', () async {
    final health = await backend.health();

    expect(health.status, 'ok');
    expect(health.dbConnected, isTrue,
        reason: 'sem banco, createRedAlert falha por chave estrangeira');
  });

  test('o login devolve uma sessão com a microárea do seed', () async {
    final session = await backend.developmentLogin(role: 'patient');

    expect(session.role, 'patient');
    // A microárea sai do payload do token; é o que define o tópico que o ACS
    // assina, então tem de casar com o seed.
    expect(session.microAreaId, seedMicroAreaId);
    expect(session.isExpired(), isFalse);
  });

  test('a triagem é classificada pelo motor do servidor', () async {
    await backend.developmentLogin(role: 'patient');

    final red = await backend.evaluateTriage(
      chestPain: true,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    final yellow = await backend.evaluateTriage(
      chestPain: false,
      difficultyBreathing: false,
      fever: true,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    final green = await backend.evaluateTriage(
      chestPain: false,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );

    expect(red, RiskLevel.red);
    expect(yellow, RiskLevel.yellow);
    expect(green, RiskLevel.green);
  });

  test('a mesma resposta produz sempre o mesmo risco', () async {
    await backend.developmentLogin(role: 'patient');

    // Determinismo é invariante (INV-02): a classificação não pode variar entre
    // chamadas idênticas.
    final results = <RiskLevel>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      results.add(await backend.evaluateTriage(
        chestPain: false,
        difficultyBreathing: true,
        fever: true,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      ));
    }

    expect(results, everyElement(RiskLevel.red));
  });

  test('o alerta vermelho é criado e o reenvio não duplica', () async {
    await backend.developmentLogin(role: 'patient');
    final key = newIdempotencyKey();
    final hash = locationHashFrom(-23.55052, -46.633308);

    final first = await backend.createRedAlert(idempotencyKey: key, locationHash: hash);
    final retry = await backend.createRedAlert(idempotencyKey: key, locationHash: hash);

    expect(first.alertId, isNotEmpty);
    expect(first.status, AlertStatus.pending);
    // Retry da MESMA tentativa: um segundo alerta aqui seria um chamado
    // duplicado na fila do ACS.
    expect(retry.alertId, first.alertId);
  });

  test('a chave de idempotência reusada com outra localização é recusada', () async {
    await backend.developmentLogin(role: 'patient');
    final key = newIdempotencyKey();

    await backend.createRedAlert(
      idempotencyKey: key,
      locationHash: locationHashFrom(-23.55052, -46.633308),
    );

    expect(
      () => backend.createRedAlert(
        idempotencyKey: key,
        locationHash: locationHashFrom(-22.90685, -43.17290),
      ),
      throwsA(isA<BackendFailure>()),
    );
  });

  test('o hash de localização não revela a coordenada', () async {
    // LGPD: o que trafega é o hash; a coordenada não pode ser legível nele.
    final hash = locationHashFrom(-23.55052, -46.633308);

    expect(hash, hasLength(12));
    expect(hash, isNot(contains('23.55')));
    expect(hash, isNot(contains('46.63')));
  });
}
