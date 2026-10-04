import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/secure_upload_token_store.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fake_rpc_server.dart';

/// Token de envio diferido (D7): um por dono no Keystore, gravado pelo login
/// na mesma seção crítica do refresh token, e que SOBREVIVE ao "Sair".
/// Credenciais e ids sintéticos.
void main() {
  group('MemoryUploadTokenStore', () {
    test('repairIndex é inofensivo (o índice é o próprio mapa)', () async {
      final store = MemoryUploadTokenStore({'acs-a': 'upload-a'});
      await store.repairIndex('acs-a');
      await store.repairIndex('acs-x');
      expect(await store.owners(), ['acs-a']);
    });

    test('um token por dono; owners lista só quem tem token', () async {
      final store = MemoryUploadTokenStore();
      await store.write('acs-a', 'upload-a');
      await store.write('acs-b', 'upload-b');
      await store.write('acs-a', 'upload-a2');

      expect(await store.read('acs-a'), 'upload-a2');
      expect(await store.owners(), unorderedEquals(['acs-a', 'acs-b']));

      await store.clear('acs-a');
      expect(await store.read('acs-a'), isNull);
      expect(await store.owners(), ['acs-b']);
    });
  });

  group('SecureStorageUploadTokenStore', () {
    test("chave 'acs_upload_token|<userId>', índice de donos e nunca readAll", () async {
      final keystore = _KeystoreFalso({
        'acs_refresh_token': 'refresh-sintetico',
        'acs_device_id': 'aparelho-sintetico',
      });
      final store = SecureStorageUploadTokenStore(storage: keystore);

      await store.write('acs-a', 'upload-a');
      await store.write('acs-b', 'upload-b');
      await store.write('acs-a', 'upload-a2');

      expect(keystore.data['acs_upload_token|acs-a'], 'upload-a2');
      expect(await store.read('acs-b'), 'upload-b');
      expect(await store.owners(), ['acs-a', 'acs-b']);

      await store.clear('acs-a');
      expect(await store.read('acs-a'), isNull);
      expect(await store.owners(), ['acs-b']);
      expect(keystore.data['acs_refresh_token'], 'refresh-sintetico');
      expect(keystore.readAllCalls, 0, reason: 'listar donos não carrega os outros segredos do Keystore');
      expect(keystore.keysRead.where((k) => !k.startsWith('acs_upload_token')), isEmpty);
    });

    test('write(A) e clear(B) concorrentes não perdem atualização do índice', () async {
      for (var rodada = 0; rodada < 5; rodada++) {
        final keystore = _KeystoreFalso()..latencia = const Duration(milliseconds: 5);
        final store = SecureStorageUploadTokenStore(storage: keystore);
        await store.write('acs-b', 'upload-b');

        await Future.wait([store.write('acs-a', 'upload-a'), store.clear('acs-b')]);

        expect(await store.owners(), ['acs-a'], reason: 'rodada $rodada');
        expect(await store.read('acs-b'), isNull);
      }
    });

    test('repairIndex recoloca no índice um dono cujo token existe; sem token, nada', () async {
      final keystore = _KeystoreFalso({'acs_upload_token|acs-a': 'upload-a'});
      final store = SecureStorageUploadTokenStore(storage: keystore);
      expect(await store.owners(), isEmpty);

      await store.repairIndex('acs-a');
      await store.repairIndex('acs-sem-token');

      expect(await store.owners(), ['acs-a']);
      expect(await store.read('acs-a'), 'upload-a', reason: 'o reparo nunca regrava o token');
    });

    test('índice ausente ou corrompido vale como vazio, e a próxima gravação o refaz', () async {
      for (final corrompido in [null, '', 'não é json', '{"a":1}', '[1, null]']) {
        final keystore = _KeystoreFalso({if (corrompido != null) 'acs_upload_token_owners': corrompido});
        final store = SecureStorageUploadTokenStore(storage: keystore);

        expect(await store.owners(), isEmpty, reason: '$corrompido');
        await store.write('acs-a', 'upload-a');
        expect(await store.owners(), ['acs-a'], reason: '$corrompido');
      }
    });
  });

  group('BackendClient', () {
    late FakeRpcServer server;
    late MemorySessionTokenStore refresh;
    late MemoryUploadTokenStore uploads;
    late BackendClient backend;

    setUp(() async {
      server = await FakeRpcServer.start();
      refresh = MemorySessionTokenStore();
      uploads = MemoryUploadTokenStore();
      backend = BackendClient(
        host: server.host,
        tokenStore: refresh,
        deviceIds: MemoryDeviceIdStore('aparelho-sintetico'),
        uploadTokens: uploads,
      );
    });

    tearDown(() async {
      backend.close();
      await server.stop();
    });

    Future<void> entrarComo(String userId) {
      server.userId = userId;
      return backend.login(matricula: 'ACS-001', senha: 'senha-sintetica');
    }

    test('login grava o uploadToken sob o userId do dono; o de outro dono fica', () async {
      await entrarComo('acs-a');
      await entrarComo('acs-b');

      expect(await uploads.read('acs-a'), server.uploadTokensIssued[0]);
      expect(await uploads.read('acs-b'), server.uploadTokensIssued[1]);
      expect(server.uploadTokensIssued[0], isNot(server.uploadTokensIssued[1]));
    });

    test('logout NÃO apaga o token de envio (D7: sobrevive ao Sair)', () async {
      await entrarComo('acs-a');
      await backend.logout();

      expect(await refresh.read(), isNull);
      expect(await uploads.read('acs-a'), server.uploadTokensIssued.single);
    });

    test('sem deviceId (ou com o sentinela) o servidor não emite: nada gravado', () async {
      for (final semAparelho in ['', 'nao-aplicavel-login-institucional']) {
        final cliente = BackendClient(
          host: server.host,
          deviceIds: MemoryDeviceIdStore(semAparelho),
          uploadTokens: uploads,
        );
        server.userId = 'acs-a';
        await cliente.login(matricula: 'ACS-001', senha: 'senha-sintetica');
        cliente.close();
      }

      expect(server.uploadTokensIssued, isEmpty);
      expect(await uploads.owners(), isEmpty);
    });

    test('login sem uploadToken na resposta não apaga o token já guardado do mesmo dono', () async {
      await entrarComo('acs-a');
      final antigo = await uploads.read('acs-a');
      server.omitUploadToken = true;
      await entrarComo('acs-a');

      expect(await uploads.read('acs-a'), antigo);
    });

    VisitSyncEntry entrada(String localId) => VisitSyncEntry(
          localId: localId,
          patientId: '00000000-0000-4000-8000-000000000001',
          scheduledAt: DateTime.utc(2026, 10, 3),
          completedAt: DateTime.utc(2026, 10, 3),
          status: 'PENDENTE',
          riskLevelBefore: RiskLevel.green,
          notes: const <String, String>{},
          version: 1,
          arrivalMethod: ArrivalMethod.manual,
        );

    test('syncDeferredVisits vai com o token de envio, sem accessToken', () async {
      final results = await backend.syncDeferredVisits(
        uploadToken: 'upload-sintetico',
        deviceId: 'aparelho-sintetico',
        visits: [entrada('a-1')],
      );

      expect(results.single.syncStatus, SyncStatus.synced);
      final pedido = server.requests.singleWhere((r) => r.method == 'syncDeferred');
      expect(pedido.endpoint, 'visits');
      expect(pedido.args['uploadToken'], 'upload-sintetico');
      expect(pedido.args['deviceId'], 'aparelho-sintetico');
      expect(pedido.args.containsKey('accessToken'), isFalse);
    });

    test('token de envio recusado vira UploadTokenRefused (não "sem conexão")', () async {
      server.refusedUploadTokens.add('upload-morto');

      await expectLater(
        backend.syncDeferredVisits(uploadToken: 'upload-morto', deviceId: 'aparelho-sintetico', visits: [entrada('a-1')]),
        throwsA(isA<UploadTokenRefused>().having((f) => f.isRecoverable, 'isRecoverable', isFalse)),
      );
    });

    test('syncLegacyVisits usa a sessão atual como transporte', () async {
      await entrarComo('acs-b');

      final results = await backend.syncLegacyVisits([entrada('leg-1')], deviceId: 'aparelho-sintetico');

      expect(results.single.localId, 'leg-1');
      final pedido = server.requests.singleWhere((r) => r.method == 'syncLegacy');
      expect(pedido.args['accessToken'], isNotNull);
      expect(pedido.args['deviceId'], 'aparelho-sintetico');
    });

    test('revokeUploadToken envia o token ao servidor', () async {
      await backend.revokeUploadToken('upload-sintetico');

      expect(server.revokedUploadTokens, ['upload-sintetico']);
    });
  });

  test('o caminho importado pelo backend_client não puxa o Flutter (token de envio)', () {
    final imports =
        File('lib/core/security/upload_token_store.dart').readAsLinesSync().where((l) => l.startsWith('import ')).join('\n');
    expect(imports, isNot(contains('package:flutter')));
    final client = File('lib/core/network/backend_client.dart').readAsStringSync();
    expect(client, isNot(contains('secure_upload_token_store.dart')));
  });
}

/// Keystore em memória que registra o que foi lido e RECUSA `readAll`.
class _KeystoreFalso implements FlutterSecureStorage {
  _KeystoreFalso([Map<String, String>? inicial]) : data = {...?inicial};

  final Map<String, String> data;
  final List<String> keysRead = <String>[];
  int readAllCalls = 0;

  /// Atraso de cada operação (provoca intercalação entre chamadas).
  Duration latencia = Duration.zero;

  Future<void> _espera() => latencia > Duration.zero ? Future<void>.delayed(latencia) : Future<void>.value();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    keysRead.add(key);
    await _espera();
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _espera();
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _espera();
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCalls++;
    return Map.of(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
