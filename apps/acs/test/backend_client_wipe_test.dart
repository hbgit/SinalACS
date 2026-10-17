import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';

import 'support/fake_rpc_server.dart';

/// Limpeza remota do aparelho (#81) vista pelo `BackendClient`: o servidor
/// recusa login, renovação e envio diferido com `DeviceWipeRequiredException`,
/// e o cliente avisa por `onDeviceWipeRequired` — nunca por
/// `onSessionExpired`. Servidor local e credenciais sintéticas.
void main() {
  late FakeRpcServer server;
  late MemorySessionTokenStore store;
  late BackendClient backend;
  late List<String> pedidos;
  late int expiradas;

  const orderId = '00000000-0000-4000-8000-0000000000aa';
  const mensagem = 'Este aparelho precisa ser limpo a pedido da coordenação.';

  setUp(() async {
    server = await FakeRpcServer.start();
    store = MemorySessionTokenStore();
    backend = BackendClient(host: server.host, tokenStore: store, deviceIds: MemoryDeviceIdStore('aparelho-antigo'));
    pedidos = <String>[];
    expiradas = 0;
    backend.onDeviceWipeRequired = pedidos.add;
    backend.onSessionExpired = () => expiradas++;
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  Matcher falhaDeLimpeza() => throwsA(isA<BackendFailure>()
      .having((f) => f.message, 'message', mensagem)
      .having((f) => f.isRecoverable, 'isRecoverable', isFalse));

  test('renewSession com DeviceWipeRequiredException chama onDeviceWipeRequired e não onSessionExpired', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    server.wipeOrderId = orderId;

    await expectLater(backend.renewSession(), falhaDeLimpeza());

    expect(pedidos, [orderId]);
    expect(expiradas, 0);
  });

  test('login com DeviceWipeRequiredException chama onDeviceWipeRequired e lança BackendFailure não recuperável', () async {
    server.wipeOrderId = orderId;

    await expectLater(backend.login(matricula: 'ACS-001', senha: 'senha-sintetica'), falhaDeLimpeza());

    expect(pedidos, [orderId]);
    expect(expiradas, 0);
    expect(backend.session, isNull);
    expect(await store.read(), isNull);
  });

  test('syncDeferred com DeviceWipeRequiredException chama onDeviceWipeRequired', () async {
    server.wipeOrderId = orderId;

    await expectLater(
      backend.syncDeferredVisits(uploadToken: 'upload-0', deviceId: 'aparelho-antigo', visits: const []),
      falhaDeLimpeza(),
    );

    expect(pedidos, [orderId]);
    expect(expiradas, 0);
  });

  test('forgetLocalSession apaga o token e a sessão sem rede', () async {
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    expect(await store.read(), isNotNull);
    final antes = server.requests.length;

    await backend.forgetLocalSession();

    expect(backend.session, isNull);
    expect(backend.isAuthenticated, isFalse);
    expect(await store.read(), isNull);
    expect(server.requests.length, antes, reason: 'nenhuma chamada de rede');
    expect(expiradas, 0);
  });

  test('forgetLocalSession torna obsoleta a renovação em voo', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    server.refreshDelay = const Duration(milliseconds: 200);

    final voo = backend.renewSession();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await backend.forgetLocalSession();

    await expectLater(voo, throwsA(isA<BackendFailure>()));
    expect(backend.session, isNull);
    expect(await store.read(), isNull, reason: 'o filho da renovação obsoleta não é gravado');
  });

  test('pendingDeviceWipe e confirmDeviceWipe falam com devices.*', () async {
    expect(await backend.pendingDeviceWipe('aparelho-antigo'), isNull);
    await backend.confirmDeviceWipe('aparelho-antigo', orderId);

    final chamadas = server.requests.where((r) => r.endpoint == 'devices').toList();
    expect(chamadas.map((r) => r.method), ['pendingWipe', 'confirmWipe']);
    expect(chamadas.first.args['deviceId'], 'aparelho-antigo');
    expect(chamadas.last.args['orderId'], orderId);
  });

  test('pendingDeviceWipe devolve o orderId do servidor', () async {
    server.pendingWipeOrderId = orderId;
    expect(await backend.pendingDeviceWipe('aparelho-antigo'), orderId);
  });

  test('pendingDeviceWipe sem rede vira BackendFailure recuperável', () async {
    await server.stop();
    await expectLater(
      backend.pendingDeviceWipe('aparelho-antigo'),
      throwsA(isA<BackendFailure>().having((f) => f.isRecoverable, 'isRecoverable', isTrue)),
    );
  });
}
