import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';

import 'support/fake_rpc_server.dart';

/// Renovação silenciosa por refresh token rotativo (LGPD-RT06). Credenciais
/// sintéticas, servidor local.
void main() {
  late FakeRpcServer server;
  late MemorySessionTokenStore store;
  late MemoryDeviceIdStore devices;
  late BackendClient backend;

  BackendClient novo() => BackendClient(host: server.host, tokenStore: store, deviceIds: devices);

  setUp(() async {
    server = await FakeRpcServer.start();
    store = MemorySessionTokenStore();
    devices = MemoryDeviceIdStore();
    backend = novo();
  });

  tearDown(() async {
    backend.close();
    await server.stop();
  });

  Future<void> entrar() => backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');

  test('JWT vencido é renovado por refresh, sem reenviar senha nem código', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();

    await backend.listPatients();

    expect(server.loginCount, 1);
    expect(server.refreshCount, 1);
  });

  test('chamadas simultâneas com JWT vencido compartilham UM refresh (single-flight)', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    server.refreshDelay = const Duration(milliseconds: 200);

    await Future.wait([backend.listPatients(), backend.listPatients(), backend.listPatients()]);

    expect(server.refreshCount, 1);
  });

  test('o refresh token rotativo é regravado a cada renovação', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    expect(await store.read(), 'refresh-0');

    await backend.listPatients();

    expect(await store.read(), 'refresh-1');
    expect(server.requests.where((r) => r.method == 'refreshSession').single.args['refreshToken'], 'refresh-0');
  });

  test('recusa do refresh (SessionExpiredException) limpa o token e chama onSessionExpired', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await entrar();
    server.rejectRefresh = true;

    await expectLater(
      backend.listPatients(),
      throwsA(isA<BackendFailure>()
          .having((f) => f.isRecoverable, 'isRecoverable', isFalse)
          .having((f) => f.message, 'message',
              'Sua sessão expirou. Entre novamente com o código do autenticador.')),
    );
    expect(avisos, 1);
    expect(await store.read(), isNull);
  });

  test('falha de REDE no refresh é recuperável e NÃO apaga o token', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await entrar();
    server.failRefreshOnce = true;

    await expectLater(
      backend.listPatients(),
      throwsA(isA<BackendFailure>().having((f) => f.isRecoverable, 'isRecoverable', isTrue)),
    );
    expect(await store.read(), 'refresh-0');
    expect(avisos, 0);

    await backend.listPatients();
    expect(server.refreshCount, 2);
    expect(await store.read(), isNotNull);
  });

  test('resumeSession: sem token salvo devolve null; com token, devolve sessão', () async {
    expect(await backend.hasStoredSession, isFalse);
    expect(await backend.resumeSession(), isNull);
    expect(server.refreshCount, 0);

    await store.write('refresh-0');
    expect(await backend.hasStoredSession, isTrue);
    final session = await backend.resumeSession();

    expect(session, isNotNull);
    expect(session!.microAreaId, server.microAreaId);
    expect(backend.isAuthenticated, isTrue);
    expect(await store.read(), 'refresh-1');
  });

  test('resumeSession recusado devolve null, apaga o token e NÃO avisa a UI', () async {
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await store.write('refresh-0');
    server.rejectRefresh = true;

    expect(await backend.resumeSession(), isNull);
    expect(await store.read(), isNull);
    expect(avisos, 0);
  });

  test('logout revoga no servidor e apaga o token local, mesmo se o servidor estiver fora', () async {
    await entrar();
    await backend.logout();
    expect(server.loggedOut, ['refresh-0']);
    expect(await store.read(), isNull);
    expect(backend.session, isNull);

    await store.write('refresh-9');
    await server.stop();
    await backend.logout();
    expect(await store.read(), isNull);
    // tearDown chama stop() de novo: é idempotente.
  });

  test('a senha não é guardada: BackendClient não mantém credencial após o login', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    await backend.listPatients();
    await backend.listPatients();

    expect(server.loginCount, 1);
    final comSenha = server.requests.where((r) => r.args.containsKey('password'));
    expect(comSenha.map((r) => r.method), ['loginInstitutional']);
    expect(server.requests.where((r) => r.method == 'refreshSession').every((r) => !r.args.containsKey('password')), isTrue);
  });

  test('login sem refreshToken na resposta limpa um token antigo', () async {
    await store.write('velho');
    server.omitRefreshToken = true;
    await entrar();
    expect(await store.read(), isNull);
  });

  test('o deviceId enviado ao login e ao refresh é o mesmo e persiste entre instâncias', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    await backend.listPatients();

    final segunda = novo();
    addTearDown(segunda.close);
    expect(await segunda.resumeSession(), isNotNull);

    final ids = server.requests
        .where((r) => r.method == 'loginInstitutional' || r.method == 'refreshSession')
        .map((r) => r.args['deviceId'])
        .toSet();
    expect(ids, hasLength(1));
    expect(ids.single, isNotEmpty);
  });
}
