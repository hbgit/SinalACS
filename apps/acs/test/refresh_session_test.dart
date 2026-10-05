import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/secure_session_token_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fake_rpc_server.dart';
import 'support/gated_session_token_store.dart';

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

  test('a segunda renovação envia o filho rotacionado, não o token do login', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    await backend.listPatients();
    await backend.listPatients();
    expect(server.refreshTokensSeen, ['refresh-0', 'refresh-1']);
  });

  test('login com deviceId em branco não recebe refreshToken (como o backend real)', () async {
    final r = await HttpClientProbe.login(server, deviceId: '  ');
    expect(r.containsKey('refreshToken'), isFalse);
  });

  group('falhas do armazenamento seguro', () {
    test('login: falha ao gravar vira BackendFailure, não PlatformException', () async {
      final b = BackendClient(host: server.host, tokenStore: ThrowingStore(failWrite: true), deviceIds: devices);
      addTearDown(b.close);
      await expectLater(b.login(matricula: 'ACS-001', senha: 'x'), throwsA(isA<BackendFailure>()));
    });

    test('renovação: falha ao gravar o filho => sessão perdida, avisa a UI, não é "sem conexão"', () async {
      server.tokenLifetime = const Duration(minutes: -1);
      final inner = ThrowingStore();
      final b = BackendClient(host: server.host, tokenStore: inner, deviceIds: devices);
      addTearDown(b.close);
      var avisos = 0;
      b.onSessionExpired = () => avisos++;
      await b.login(matricula: 'ACS-001', senha: 'x');
      inner.failWrite = true;
      await expectLater(
        b.listPatients(),
        throwsA(isA<BackendFailure>()
            .having((f) => f.isRecoverable, 'isRecoverable', isFalse)
            .having((f) => f.message, 'message', contains('guardar a sessão'))),
      );
      expect(avisos, 1);
      expect(b.session, isNull);
    });

    test('renovação: falha ao ler o deviceId não vira "Sem conexão"', () async {
      server.tokenLifetime = const Duration(minutes: -1);
      final b = BackendClient(host: server.host, tokenStore: store, deviceIds: ThrowingDevices());
      addTearDown(b.close);
      await store.write('refresh-0');
      await expectLater(
        b.listPatients(),
        throwsA(isA<BackendFailure>().having((f) => f.message, 'message', isNot(contains('Sem conexão')))),
      );
    });

    test('resumeSession com leitura falhando devolve null', () async {
      final b = BackendClient(host: server.host, tokenStore: ThrowingStore(failRead: true), deviceIds: devices);
      addTearDown(b.close);
      expect(await b.resumeSession(), isNull);
      expect(await b.hasStoredSession, isFalse);
    });

    test('logout com clear falhando lança BackendFailure, mas sessão em memória cai', () async {
      final b = BackendClient(host: server.host, tokenStore: ThrowingStore(failClear: true), deviceIds: devices);
      addTearDown(b.close);
      await b.login(matricula: 'ACS-001', senha: 'x');
      await expectLater(b.logout(), throwsA(isA<BackendFailure>()));
      expect(b.session, isNull);
    });
  });

  test('logout com renovação em voo: nada é regravado nem ressuscitado', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await entrar();
    server.refreshDelay = const Duration(milliseconds: 200);

    final renovacao = backend.listPatients().then<Object?>((_) => null, onError: (Object e) => e);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await backend.logout();
    await renovacao;

    expect(await store.read(), isNull);
    expect(backend.session, isNull);
    expect(avisos, 0, reason: 'renovação obsoleta não manda a UI para o login');
  });

  test('renovação em voo + login de OUTRO usuário: vale o login, não a renovação (INV-01)', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await entrar(); // ACS A, refresh-0
    server.refreshDelay = const Duration(milliseconds: 200);

    final renovacao = backend.listPatients().then<Object?>((_) => null, onError: (Object e) => e);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    server
      ..userId = '00000000-0000-4000-8000-0000000000bb'
      ..tokenLifetime = const Duration(minutes: 15);
    final sessaoB = await backend.login(matricula: 'ACS-002', senha: 'senha-sintetica-b');
    final tokenB = server.loginTokens.last;
    expect(tokenB, isNot('refresh-0'), reason: 'o login de B emite um token próprio');
    expect(await store.read(), tokenB);
    final resultado = await renovacao;

    expect(resultado, isA<BackendFailure>(), reason: 'a renovação obsoleta não entrega sessão a ninguém');
    expect(identical(backend.session, sessaoB), isTrue, reason: 'o painel de B segue com o JWT de B');
    expect(await store.read(), tokenB, reason: 'o filho da renovação de A não sobrescreve o token de B');
    expect(avisos, 0);
  });

  test('renovação iniciada durante a chamada de logout não regrava o token', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    var avisos = 0;
    backend.onSessionExpired = () => avisos++;
    await entrar();
    server
      ..logoutDelay = const Duration(milliseconds: 100)
      ..refreshDelay = const Duration(milliseconds: 300);

    final saida = backend.logout();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final renovacao = backend.listPatients().then<Object?>((_) => null, onError: (Object e) => e);
    await saida;
    await renovacao;

    expect(await store.read(), isNull);
    expect(backend.session, isNull);
    expect(avisos, 0);
  });

  test('refresh token novo vazio é tratado como ausente (e o JWT ilegível ainda persiste o filho)', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    server.emptyRefreshToken = true;
    await expectLater(backend.listPatients(), throwsA(isA<BackendFailure>()));
    expect(await store.read(), 'refresh-0', reason: 'vazio não sobrescreve');
  });

  test('JWT ilegível não perde o filho rotacionado', () async {
    server.tokenLifetime = const Duration(minutes: -1);
    await entrar();
    server.garbageAccessToken = true;
    await expectLater(backend.listPatients(), throwsA(isA<BackendFailure>()));
    expect(await store.read(), 'refresh-1');
  });

  group('corrida do login (janela da gravação)', () {
    /// Espera, em tempo real, até [condicao] valer: a requisição passa por um
    /// socket de verdade, então `pumpEventQueue` sozinho não basta.
    Future<void> esperarAte(bool Function() condicao, {String? motivo}) async {
      final limite = DateTime.now().add(const Duration(seconds: 5));
      while (!condicao()) {
        if (DateTime.now().isAfter(limite)) fail(motivo ?? 'condição não chegou a valer');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('renovação iniciada com o login parado na gravação ESPERA e usa o token NOVO', () async {
      final gated = GatedSessionTokenStore();
      final b = BackendClient(host: server.host, tokenStore: gated, deviceIds: MemoryDeviceIdStore('aparelho-1'));
      addTearDown(b.close);
      await b.login(matricula: 'ACS-A', senha: 'senha-sintetica'); // token do login #0, gravado
      server.tokenLifetime = const Duration(minutes: 15);

      gated.writeGate = Completer<void>();
      final login = b.login(matricula: 'ACS-B', senha: 'senha-sintetica'); // para na escrita
      await esperarAte(() => gated.writes == 2, motivo: 'o login B não chegou à escrita');
      await pumpEventQueue();
      expect(gated.writes, 2, reason: 'o login B chegou à escrita e está parado nela');

      final renovacao = b.renewSession(); // começa DENTRO da janela
      await pumpEventQueue();
      // Tempo real para uma requisição indevida chegar ao servidor.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.refreshTokensSeen, isEmpty, reason: 'a renovação não pode ler o token antes de o login confirmar');

      gated.writeGate!.complete();
      await login;
      await renovacao;

      // Leu o token do login de B, não o de A:
      expect(server.refreshTokensSeen, [server.loginTokens.last]);
      expect(await gated.read(), isNot(server.loginTokens.first));
      expect(b.session!.userId, isNotNull);
    });

    test('renovação que começou ANTES do login e termina DEPOIS da gravação continua obsoleta', () async {
      final gated = GatedSessionTokenStore();
      final b = BackendClient(host: server.host, tokenStore: gated, deviceIds: MemoryDeviceIdStore('aparelho-1'));
      addTearDown(b.close);
      server.tokenLifetime = const Duration(minutes: -1);
      var avisos = 0;
      b.onSessionExpired = () => avisos++;
      await b.login(matricula: 'ACS-A', senha: 'senha-sintetica');
      server.refreshDelay = const Duration(milliseconds: 300);

      final renovacao = b.listPatients().then<Object?>((_) => null, onError: (Object e) => e);
      await esperarAte(() => server.refreshCount == 1, motivo: 'a renovação de A não saiu');
      server
        ..userId = '00000000-0000-4000-8000-0000000000bb'
        ..tokenLifetime = const Duration(minutes: 15);
      final sessaoB = await b.login(matricula: 'ACS-B', senha: 'senha-sintetica-b');
      final resultado = await renovacao;

      expect(resultado, isA<BackendFailure>().having((f) => f.isRecoverable, 'isRecoverable', isTrue));
      expect(identical(b.session, sessaoB), isTrue, reason: 'a sessão é a de B');
      expect(await gated.read(), server.loginTokens.last, reason: 'o token é o do login de B');
      expect(server.refreshTokensSeen, [server.loginTokens.first]);
      expect(avisos, 0);
    });

    test('sync de A com JWT vencido e login de B confirmando no meio: o lote de A NÃO sai com o token de B',
        () async {
      const acsB = '00000000-0000-4000-8000-0000000000bb';
      final gated = GatedSessionTokenStore();
      final b = BackendClient(host: server.host, tokenStore: gated, deviceIds: MemoryDeviceIdStore('aparelho-1'));
      addTearDown(b.close);
      server.tokenLifetime = const Duration(minutes: -1);
      final sessaoA = await b.login(matricula: 'ACS-A', senha: 'senha-sintetica'); // JWT de A já vencido
      server
        ..userId = acsB
        ..tokenLifetime = const Duration(minutes: 15);

      // Login de B parado na gravação: a sessão exposta ainda é a de A.
      gated.writeGate = Completer<void>();
      final login = b.login(matricula: 'ACS-B', senha: 'senha-sintetica-b');
      await esperarAte(() => gated.writes == 2, motivo: 'o login B não chegou à escrita');
      expect(b.session!.userId, sessaoA.userId);

      // A fila de A sincroniza: a guarda síncrona passa (sessão de A), a
      // renovação espera a seção do login de B e leria o token DE B.
      final fila = OfflineVisitQueue(
        synchronizer: BackendVisitSynchronizer(backend: b, ownerId: sessaoA.userId),
      );
      await fila.add(OfflineVisitRecord(
        localId: 'local-a1',
        patientId: '00000000-0000-4000-8000-0000000000a1',
        risk: 'red',
        status: 'PENDENTE',
      ));
      final envio = fila.sync();
      await pumpEventQueue();

      gated.writeGate!.complete();
      await login;
      final resultado = await envio;

      expect(b.session!.userId, acsB);
      expect(resultado.kind, SyncOutcomeKind.error);
      expect(fila.pendingCount, 1, reason: 'o lote de A continua pendente');
      expect(server.requests.where((r) => r.method == 'sync'), isEmpty,
          reason: 'nenhum visits.sync saiu com o token de B');
    });

    test('logout: renovação iniciada durante a rede do logout não ressuscita a sessão', () async {
      final gated = GatedSessionTokenStore();
      final b = BackendClient(host: server.host, tokenStore: gated, deviceIds: MemoryDeviceIdStore('aparelho-1'));
      addTearDown(b.close);
      server.tokenLifetime = const Duration(minutes: -1);
      var avisos = 0;
      b.onSessionExpired = () => avisos++;
      await b.login(matricula: 'ACS-A', senha: 'senha-sintetica');
      server
        ..logoutDelay = const Duration(milliseconds: 150)
        ..refreshDelay = const Duration(milliseconds: 300);

      final saida = b.logout();
      await esperarAte(() => server.loggedOut.isNotEmpty, motivo: 'o logout não chegou ao servidor');
      final renovacao = b.listPatients().then<Object?>((_) => null, onError: (Object e) => e);
      await saida;
      final resultado = await renovacao;

      expect(resultado, isA<BackendFailure>());
      expect(await gated.read(), isNull);
      expect(b.session, isNull);
      expect(avisos, 0);
    });
  });

  test('SecureStorageDeviceIdStore: chamadas concorrentes na 1ª vez devolvem o mesmo id', () async {
    final storage = SlowStorage();
    final ids = SecureStorageDeviceIdStore(storage: storage);
    final r = await Future.wait([ids.readOrCreate(), ids.readOrCreate(), ids.readOrCreate()]);
    expect(r.toSet(), hasLength(1));
    expect(storage.writes, 1);
  });
}

class HttpClientProbe {
  static Future<Map<String, dynamic>> login(FakeRpcServer s, {required String deviceId}) async {
    final c = HttpClient();
    try {
      final req = await c.postUrl(Uri.parse('${s.host}auth'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'method': 'loginInstitutional', 'matricula': 'a', 'password': 'b', 'deviceId': deviceId}));
      final res = await req.close();
      return jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
    } finally {
      c.close(force: true);
    }
  }
}

class ThrowingStore implements SessionTokenStore {
  ThrowingStore({this.failRead = false, this.failWrite = false, this.failClear = false});
  bool failRead, failWrite, failClear;
  String? _t;
  @override
  Future<String?> read() async => failRead ? throw PlatformException(code: 'x') : _t;
  @override
  Future<void> write(String token) async => failWrite ? throw PlatformException(code: 'x') : _t = token;
  @override
  Future<void> clear() async => failClear ? throw PlatformException(code: 'x') : _t = null;
  @override
  Future<bool> contains() async => await read() != null;
  @override
  Future<SessionUnlock> unlock({required String reason}) async => SessionUnlock.notRequired;
}

class ThrowingDevices implements DeviceIdStore {
  @override
  Future<String> readOrCreate() async => throw PlatformException(code: 'x');
}

class SlowStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};
  int writes = 0;
  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return data[key];
  }

  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    writes++;
    data[key] = value!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
