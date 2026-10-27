import 'dart:io';

import 'package:sinalacs_server/src/config/api_tls_config.dart';
import 'package:sinalacs_server/src/runtime/mtls_api_server.dart';
import 'package:test/test.dart';

/// mTLS do apiServer (RNF04, issue #90): o listener da 8080 EXIGE certificado
/// de cliente assinado pela CA do RPC, recusado no handshake.
///
/// Medido de verdade: um listener ligado por `bindRequiringClientCertificate`
/// e o `curl` do host sondando com e sem certificado. As sondas negativas
/// afirmam a AUSÊNCIA de resposta HTTP (`HTTP 000`, sem `"status"`), nunca o
/// código de saída do curl (35 ou 56, conforme o OpenSSL) nem o texto do
/// `openssl s_client` — que no TLS 1.3 imprime `CONNECTION ESTABLISHED` mesmo
/// quando o servidor recusa o certificado em seguida (medido na PoC da #90).
void main() {
  late Directory dir;
  late String caPath, cliCrt, cliKey, foraCrt, foraKey;
  late ApiTlsConfig config;
  late HttpServer server;

  Future<void> openssl(List<String> args) async {
    final r = await Process.run('openssl', args, workingDirectory: dir.path);
    if (r.exitCode != 0) {
      throw StateError('openssl ${args.first} falhou: ${r.stderr}');
    }
  }

  Future<void> folha(String nome, String ca, String eku, {String? san}) async {
    await openssl(['req', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', '$nome.key', '-out', '$nome.csr', '-subj', '/CN=$nome']);
    File('${dir.path}/$nome.ext').writeAsStringSync(
      'extendedKeyUsage=$eku\n${san == null ? '' : 'subjectAltName=$san\n'}',
    );
    await openssl(['x509', '-req', '-days', '2', '-in', '$nome.csr',
      '-CA', '$ca.crt', '-CAkey', '$ca.key', '-CAcreateserial',
      '-extfile', '$nome.ext', '-out', '$nome.crt']);
  }

  /// `curl` contra `server`, com os argumentos extras; devolve stdout+stderr e
  /// o código de saída. `-w` acrescenta a linha `HTTP <código>` ao fim.
  Future<(int, String)> curl(List<String> extra, {int? port}) async {
    final r = await Process.run('curl', [
      '-sS', '--max-time', '5', '--tlsv1.3', '--cacert', caPath,
      '-X', 'POST', '-H', 'Content-Type: application/json', '-d', '{}',
      '-w', '\nHTTP %{http_code}', ...extra,
      'https://localhost:${port ?? server.port}/health/check',
    ]);
    return (r.exitCode, '${r.stdout}${r.stderr}');
  }

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('mtls_api_server_test');
    await openssl(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
      '-keyout', 'ca.key', '-out', 'ca.crt', '-subj', '/CN=ca-de-teste']);
    await folha('localhost', 'ca', 'serverAuth', san: 'DNS:localhost,IP:127.0.0.1');
    await folha('traefik-de-teste', 'ca', 'clientAuth');
    await openssl(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
      '-keyout', 'fora.key', '-out', 'fora.crt', '-subj', '/CN=ca-de-fora']);
    // Mesmo CN que o cliente legítimo, de propósito: a recusa tem de vir da
    // cadeia, não do nome.
    await openssl(['req', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', 'fora-cli.key', '-out', 'fora-cli.csr', '-subj', '/CN=traefik-de-teste']);
    await openssl(['x509', '-req', '-days', '2', '-in', 'fora-cli.csr',
      '-CA', 'fora.crt', '-CAkey', 'fora.key', '-CAcreateserial',
      '-extfile', 'traefik-de-teste.ext', '-out', 'fora-cli.crt']);
    caPath = '${dir.path}/ca.crt';
    cliCrt = '${dir.path}/traefik-de-teste.crt';
    cliKey = '${dir.path}/traefik-de-teste.key';
    foraCrt = '${dir.path}/fora-cli.crt';
    foraKey = '${dir.path}/fora-cli.key';
    config = ApiTlsConfig(
      certificatePath: '${dir.path}/localhost.crt',
      keyPath: '${dir.path}/localhost.key',
      clientCaPath: caPath,
    );
    server = await bindRequiringClientCertificate(
      InternetAddress.loopbackIPv4, 0, config.toSecurityContext(),
    );
    server.listen((req) => req.response
      ..statusCode = 200
      ..write('{"status":"ok"}')
      ..close());
  });

  tearDownAll(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  group('bindRequiringClientCertificate', () {
    test('certificado assinado pela CA: 200 e corpo (controle positivo)', () async {
      final (rc, out) = await curl(['--cert', cliCrt, '--key', cliKey]);
      expect(rc, 0, reason: out);
      expect(out, allOf(contains('"status"'), contains('HTTP 200')));
    });

    test('sem certificado de cliente: nenhuma resposta HTTP', () async {
      final (rc, out) = await curl([]);
      expect(rc, isNot(0));
      expect(out, isNot(contains('"status"')));
      expect(out, contains('HTTP 000'));
    });

    test('certificado de outra CA (mesmo CN): nenhuma resposta HTTP', () async {
      final (rc, out) = await curl(['--cert', foraCrt, '--key', foraKey]);
      expect(rc, isNot(0));
      expect(out, isNot(contains('"status"')));
      expect(out, contains('HTTP 000'));
    });

    test('TLS 1.2 com certificado válido continua recusado', () async {
      final (rc, out) = await curl(
        ['--tlsv1.2', '--tls-max', '1.2', '--cert', cliCrt, '--key', cliKey],
      );
      expect(rc, isNot(0));
      expect(out, isNot(contains('"status"')));
    });
  });

  group('SecureServerSocketAsServerSocket', () {
    test('rajada de handshakes falhos não derruba o listener (DoS)', () async {
      final log = <String>[];
      final socket = await bindRequiringClientCertificateSocket(
        InternetAddress.loopbackIPv4, 0, config.toSecurityContext(),
        log: log.add,
      );
      final proprio = HttpServer.listenOn(socket);
      addTearDown(() => proprio.close(force: true));
      proprio.listen((req) => req.response
        ..write('{"status":"ok"}')
        ..close());

      for (var i = 0; i < 20; i++) {
        await curl([], port: proprio.port);
        await curl(['--cert', foraCrt, '--key', foraKey], port: proprio.port);
      }
      // Conexão TCP que manda lixo e fecha no meio do handshake.
      final s = await Socket.connect(InternetAddress.loopbackIPv4, proprio.port);
      s.add([0x16, 0x03, 0x01, 0x00, 0x05, 0x6c, 0x69, 0x78, 0x6f]);
      await s.flush();
      await s.close();

      final (rc, out) = await curl(
        ['--cert', cliCrt, '--key', cliKey], port: proprio.port,
      );
      expect(rc, 0, reason: out);
      expect(out, allOf(contains('"status"'), contains('HTTP 200')));
      expect(socket.handshakesRecusados, greaterThanOrEqualTo(40));
      expect(log, isNotEmpty);
      // VAZ-01: só o tipo do erro, nada do peer.
      expect(log, everyElement(isNot(contains('127.0.0.1'))));
      expect(log, everyElement(contains('handshake recusado')));
    });

    test('address, port e close delegam ao socket seguro', () async {
      final socket = await bindRequiringClientCertificateSocket(
        InternetAddress.loopbackIPv4, 0, config.toSecurityContext(),
      );
      expect(socket.address, InternetAddress.loopbackIPv4);
      expect(socket.port, greaterThan(0));
      await socket.close();
      // A porta ficou livre: um bind novo na mesma porta tem de funcionar.
      final outro = await ServerSocket.bind(InternetAddress.loopbackIPv4, socket.port);
      await outro.close();
    });
  });

  group('mtlsApiServerAdapter', () {
    test('sem SecurityContext falha fechado', () {
      expect(
        () => mtlsApiServerAdapter(InternetAddress.loopbackIPv4, 0, null),
        throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('SecurityContext'),
        )),
      );
    });

    test('devolve um Adapter na porta ligada, que exige o certificado', () async {
      final adapter = await mtlsApiServerAdapter(
        InternetAddress.loopbackIPv4, 0, config.toSecurityContext(),
      );
      addTearDown(() => adapter.close(force: true));
      expect(adapter.port, greaterThan(0));
      final (rc, out) = await curl([], port: adapter.port);
      expect(rc, isNot(0));
      expect(out, isNot(contains('"status"')));
    });
  });
}
