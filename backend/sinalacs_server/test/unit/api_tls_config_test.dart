import 'dart:io';

import 'package:sinalacs_server/src/config/api_tls_config.dart';
import 'package:test/test.dart';

/// TLS 1.3 mútuo do apiServer (RNF04, issues #78 e #90): o trecho Traefik →
/// backend.
///
/// As regras de leitura das variáveis são testadas pelo mapa; a versão mínima
/// é medida de verdade — um `HttpServer.bindSecure` com o contexto produzido e
/// o `openssl s_client` do host negociando 1.3 e 1.2 contra ele. Só a primeira
/// parte provaria que o código lê `API_TLS_*`, não que o 1.2 é recusado. A
/// exigência do certificado de cliente é medida em `mtls_api_server_test.dart`.
///
/// Desde a #90 são TRÊS variáveis, juntas ou nenhuma: duas delas presentes é o
/// caso que mais importa recusar, porque é o que um `.env` anterior à #90 tem.
/// Sem a recusa, o servidor subiria em TLS de mão única — exatamente o estado
/// que a issue existe para fechar — sem ninguém notar.
const _asTres = ['API_TLS_CERT_PATH', 'API_TLS_KEY_PATH', 'API_TLS_CLIENT_CA_PATH'];

Matcher _erroQueNomeiaAsTres() => throwsA(
  isA<StateError>().having(
    (e) => e.message,
    'message',
    allOf(
      contains('API_TLS_CERT_PATH'),
      contains('API_TLS_KEY_PATH'),
      contains('API_TLS_CLIENT_CA_PATH'),
      contains('devem vir juntas'),
      contains('#90'),
    ),
  ),
);

void main() {
  group('ApiTlsConfig.fromMap', () {
    test('sem as três variáveis devolve null (HTTP, caminho do Render)', () {
      expect(ApiTlsConfig.fromMap({}), isNull);
    });

    test('string vazia ou só de espaços conta como ausente', () {
      expect(
        ApiTlsConfig.fromMap({
          'API_TLS_CERT_PATH': '',
          'API_TLS_KEY_PATH': '  ',
          'API_TLS_CLIENT_CA_PATH': '',
        }),
        isNull,
      );
    });

    test('só o certificado é erro de boot que nomeia as três', () {
      expect(
        () => ApiTlsConfig.fromMap({'API_TLS_CERT_PATH': '/x.crt'}),
        _erroQueNomeiaAsTres(),
      );
    });

    test('só duas das três é erro de boot que nomeia as três (fail-fast, #90)', () {
      for (final ausente in _asTres) {
        final mapa = {for (final v in _asTres) if (v != ausente) v: '/x'};
        expect(
          () => ApiTlsConfig.fromMap(mapa),
          _erroQueNomeiaAsTres(),
          reason: 'sem $ausente o boot tem de falhar, não cair em mão única',
        );
      }
    });

    test('só a chave também é erro de boot', () {
      expect(
        () => ApiTlsConfig.fromMap({'API_TLS_KEY_PATH': '/x.key'}),
        throwsStateError,
      );
    });

    test('as três juntas produzem os caminhos', () {
      final config = ApiTlsConfig.fromMap({
        'API_TLS_CERT_PATH': '/a.crt',
        'API_TLS_KEY_PATH': '/a.key',
        'API_TLS_CLIENT_CA_PATH': '/ca.crt',
      })!;
      expect(config.certificatePath, '/a.crt');
      expect(config.keyPath, '/a.key');
      expect(config.clientCaPath, '/ca.crt');
    });
  });

  group('ApiTlsConfig.carregar (boot)', () {
    Never sair(int codigo) => throw _Saiu(codigo);

    test('sem variável nenhuma: HTTP, sem log, sem sair', () {
      final log = <String>[];
      final boot = ApiTlsConfig.carregar({}, log: log.add, exitFn: sair);
      expect(boot.config, isNull);
      expect(boot.context, isNull);
      expect(log, isEmpty);
    });

    test('só duas das três: escreve a mensagem com as três variáveis e sai 78', () {
      final log = <String>[];
      expect(
        () => ApiTlsConfig.carregar(
          {'API_TLS_CERT_PATH': '/x.crt', 'API_TLS_KEY_PATH': '/x.key'},
          log: log.add, exitFn: sair,
        ),
        throwsA(isA<_Saiu>().having((e) => e.codigo, 'codigo', 78)),
      );
      expect(log.join('\n'), allOf(
        contains('API_TLS_CERT_PATH'), contains('API_TLS_KEY_PATH'),
        contains('API_TLS_CLIENT_CA_PATH'), contains('devem vir juntas'),
      ));
    });

    test('arquivo inexistente: nomeia a variável e sai 78 (não cai em HTTP)', () {
      final log = <String>[];
      expect(
        () => ApiTlsConfig.carregar(
          {
            'API_TLS_CERT_PATH': '/nao/existe.crt',
            'API_TLS_KEY_PATH': '/nao/existe.key',
            'API_TLS_CLIENT_CA_PATH': '/nao/existe-ca.crt',
          },
          log: log.add, exitFn: sair,
        ),
        throwsA(isA<_Saiu>().having((e) => e.codigo, 'codigo', 78)),
      );
      expect(log.join('\n'), contains('API_TLS_CERT_PATH'));
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
        clientCaPath: caPath,
      );
    });

    tearDownAll(() => dir.deleteSync(recursive: true));

    test('arquivo inexistente falha no boot, não cai para HTTP', () {
      expect(
        () => const ApiTlsConfig(
          certificatePath: '/nao/existe.crt',
          keyPath: '/nao/existe.key',
          clientCaPath: '/nao/existe-ca.crt',
        ).toSecurityContext(),
        throwsA(anything),
      );
    });

    test('arquivo ilegível nomeia a variável e não vaza o conteúdo', () {
      // Uma chave privada no lugar da CA: o SDK lança TlsException, que o
      // runZonedGuarded da #56 classificaria como transitório e deixaria o
      // processo sair com código 0 (revisão do checkpoint, achado 2).
      expect(
        () => ApiTlsConfig(
          certificatePath: '${dir.path}/leaf.crt',
          keyPath: '${dir.path}/leaf.key',
          clientCaPath: '${dir.path}/leaf.key',
        ).toSecurityContext(),
        throwsA(isA<StateError>().having(
          (e) => e.message, 'message',
          allOf(contains('API_TLS_CLIENT_CA_PATH'), contains('TlsException'),
              isNot(contains('PRIVATE KEY'))),
        )),
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

class _Saiu implements Exception {
  _Saiu(this.codigo);
  final int codigo;
}
