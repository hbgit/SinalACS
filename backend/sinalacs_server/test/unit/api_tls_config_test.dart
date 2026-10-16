import 'dart:io';

import 'package:sinalacs_server/src/config/api_tls_config.dart';
import 'package:test/test.dart';

/// TLS 1.3 do apiServer (RNF04, issue #78): o trecho Traefik → backend.
///
/// As regras de leitura das variáveis são testadas pelo mapa; a versão mínima
/// é medida de verdade — um `HttpServer.bindSecure` com o contexto produzido e
/// o `openssl s_client` do host negociando 1.3 e 1.2 contra ele. Só a primeira
/// parte provaria que o código lê `API_TLS_*`, não que o 1.2 é recusado.
void main() {
  group('ApiTlsConfig.fromMap', () {
    test('sem as duas variáveis devolve null (HTTP, caminho do Render)', () {
      expect(ApiTlsConfig.fromMap({}), isNull);
    });

    test('string vazia ou só de espaços conta como ausente', () {
      expect(
        ApiTlsConfig.fromMap({'API_TLS_CERT_PATH': '', 'API_TLS_KEY_PATH': '  '}),
        isNull,
      );
    });

    test('só o certificado é erro de boot que nomeia as duas', () {
      expect(
        () => ApiTlsConfig.fromMap({'API_TLS_CERT_PATH': '/x.crt'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('API_TLS_CERT_PATH'), contains('API_TLS_KEY_PATH')),
          ),
        ),
      );
    });

    test('só a chave também é erro de boot', () {
      expect(
        () => ApiTlsConfig.fromMap({'API_TLS_KEY_PATH': '/x.key'}),
        throwsStateError,
      );
    });

    test('as duas juntas produzem os caminhos', () {
      final config = ApiTlsConfig.fromMap({
        'API_TLS_CERT_PATH': '/a.crt',
        'API_TLS_KEY_PATH': '/a.key',
      })!;
      expect(config.certificatePath, '/a.crt');
      expect(config.keyPath, '/a.key');
    });
  });

  group('ApiTlsConfig.toSecurityContext', () {
    late Directory dir;
    late String caPath;
    late ApiTlsConfig config;

    Future<void> openssl(List<String> args) async {
      final r = await Process.run('openssl', args, workingDirectory: dir.path);
      if (r.exitCode != 0) {
        throw StateError('openssl ${args.first} falhou: ${r.stderr}');
      }
    }

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('api_tls_config_test');
      await openssl(['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-days', '2', '-keyout', 'ca.key', '-out', 'ca.crt',
        '-subj', '/CN=ca-de-teste']);
      await openssl(['req', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', 'leaf.key', '-out', 'leaf.csr', '-subj', '/CN=localhost']);
      File('${dir.path}/leaf.ext').writeAsStringSync(
        'extendedKeyUsage=serverAuth\n'
        'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
      );
      await openssl(['x509', '-req', '-days', '2', '-in', 'leaf.csr',
        '-CA', 'ca.crt', '-CAkey', 'ca.key', '-CAcreateserial',
        '-extfile', 'leaf.ext', '-out', 'leaf.crt']);
      caPath = '${dir.path}/ca.crt';
      config = ApiTlsConfig(
        certificatePath: '${dir.path}/leaf.crt',
        keyPath: '${dir.path}/leaf.key',
      );
    });

    tearDownAll(() => dir.deleteSync(recursive: true));

    test('arquivo inexistente falha no boot, não cai para HTTP', () {
      expect(
        () => const ApiTlsConfig(
          certificatePath: '/nao/existe.crt',
          keyPath: '/nao/existe.key',
        ).toSecurityContext(),
        throwsA(anything),
      );
    });

    test('servidor com o contexto aceita TLS 1.3 e recusa TLS 1.2', () async {
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        config.toSecurityContext(),
      );
      server.listen((req) => req.response
        ..statusCode = 200
        ..close());
      addTearDown(() => server.close(force: true));

      Future<(int, String)> handshake(String version) async {
        final p = await Process.start('openssl', [
          's_client', '-brief', '-connect', '127.0.0.1:${server.port}',
          version, '-CAfile', caPath,
        ]);
        await p.stdin.close();
        final out = await p.stdout.transform(systemEncoding.decoder).join();
        final err = await p.stderr.transform(systemEncoding.decoder).join();
        return (await p.exitCode, '$out$err');
      }

      final (_, t13) = await handshake('-tls1_3');
      expect(t13, contains('Protocol version: TLSv1.3'));
      expect(t13, isNot(contains('verify error')));

      final (rc12, t12) = await handshake('-tls1_2');
      expect(t12, isNot(contains('CONNECTION ESTABLISHED')));
      expect(rc12, isNot(0));
    });
  });
}
