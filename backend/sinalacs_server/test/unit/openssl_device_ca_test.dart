import 'dart:io';

import 'package:sinalacs_server/src/config/device_ca_config.dart';
import 'package:sinalacs_server/src/infrastructure/pki/openssl_device_ca.dart';
import 'package:test/test.dart';

/// CA de aparelhos (#94): o invólucro `openssl` que assina as folhas MQTT dos
/// aparelhos e gera a CRL. Os testes rodam o `openssl` de verdade contra uma CA
/// descartável em `Directory.systemTemp`, apagada no fim — nenhum conteúdo de
/// chave é impresso.
///
/// Sem o binário `openssl` no PATH os testes FALHAM com mensagem clara, em vez
/// de pular em silêncio: o backend depende dele em produção (Dockerfile).
void main() {
  const microArea = '00000000-0000-4000-8000-000000000003';
  late Directory dir;
  late String caCert;
  late String csr;
  late OpensslDeviceCa ca;

  Future<ProcessResult> run(List<String> args) async {
    try {
      return await Process.run('openssl', args, workingDirectory: dir.path);
    } on ProcessException {
      fail('binário `openssl` ausente no PATH: estes testes precisam dele.');
    }
  }

  Future<void> ok(List<String> args) async {
    final r = await run(args);
    if (r.exitCode != 0) {
      fail('openssl ${args.first} saiu com ${r.exitCode}: ${r.stderr}');
    }
  }

  Future<String> novoCsr({required String cn, String alg = 'ec'}) async {
    final nome = 'csr-${DateTime.now().microsecondsSinceEpoch}';
    await ok([
      'req', '-new', '-nodes',
      '-newkey', alg == 'ec' ? 'ec' : 'rsa:2048',
      if (alg == 'ec') ...['-pkeyopt', 'ec_paramgen_curve:prime256v1'],
      '-keyout', '$nome.key', '-out', '$nome.csr', '-subj', '/CN=$cn',
    ]);
    return File('${dir.path}/$nome.csr').readAsString();
  }

  Future<String> tmp(String nome, String conteudo) async {
    final f = File('${dir.path}/$nome');
    await f.writeAsString(conteudo);
    return f.path;
  }

  Future<String> x509Text(String pem) async {
    final p = await tmp('leaf.pem', pem);
    // `-nameopt oneline` imprime `CN = x`; o padrão do 3.5 é `CN=x`.
    final r = await run([
      'x509', '-in', p, '-noout', '-text', '-serial', '-dates',
      '-nameopt', 'oneline',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return r.stdout as String;
  }

  Future<ProcessResult> verify(String pem, String caPath) async {
    final p = await tmp('verify.pem', pem);
    return run(['verify', '-purpose', 'sslclient', '-CAfile', caPath, p]);
  }

  Future<String> crlText(String pem) async {
    final p = await tmp('crl.pem', pem);
    final r = await run(['crl', '-in', p, '-noout', '-text']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return r.stdout as String;
  }

  Future<ProcessResult> verifyCrl(String pem, String caPath) async {
    final p = await tmp('crl-verify.pem', pem);
    return run(['crl', '-in', p, '-CAfile', caPath, '-noout']);
  }

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sinalacs-device-ca-test-');
    await ok([
      'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
      '-nodes', '-days', '30', '-keyout', 'ca.key', '-out', 'ca.crt',
      '-subj', '/CN=sinalacs-test-devices-ca',
    ]);
    caCert = '${dir.path}/ca.crt';
    csr = await novoCsr(cn: microArea);
    ca = OpensslDeviceCa(DeviceCaConfig(
      caCertPath: caCert,
      caKeyPath: '${dir.path}/ca.key',
      crlPath: '${dir.path}/crl-final.pem',
      certDays: 30,
      crlDays: 30,
    ));
  });

  tearDownAll(() async {
    await dir.delete(recursive: true);
  });

  test('sign emite folha clientAuth com serial, CN, SANs e validade pedidos',
      () async {
    final pem = await ca.sign(
      csrPem: csr,
      serial: BigInt.parse('0a1b', radix: 16),
      commonName: microArea,
      sanUris: ['urn:sinalacs:device:dev-1', 'urn:sinalacs:acs:acs-1'],
      notBefore: DateTime.utc(2026, 10, 27, 11),
      notAfter: DateTime.utc(2026, 11, 26, 12),
    );
    final txt = await x509Text(pem);
    expect(txt, contains('serial=0A1B'));
    expect(txt, contains('CN = $microArea'));
    expect(txt, contains('URI:urn:sinalacs:device:dev-1'));
    expect(txt, contains('URI:urn:sinalacs:acs:acs-1'));
    expect(txt, contains('TLS Web Client Authentication'));
    expect(txt, contains('notBefore=Oct 27 11:00:00 2026 GMT'));
    expect(txt, contains('notAfter=Nov 26 12:00:00 2026 GMT'));
    expect(txt, contains('CA:FALSE'));
    expect((await verify(pem, caCert)).exitCode, 0);
  });

  test(
      'sign preserva a serial exata (128 bits com o bit alto, e hex ímpar) e '
      'o sujeito só CN= mesmo com RDN extra no CSR', () async {
    final nome = 'csr-rdn-${DateTime.now().microsecondsSinceEpoch}';
    await ok([
      'req', '-new', '-nodes', '-newkey', 'ec',
      '-pkeyopt', 'ec_paramgen_curve:prime256v1',
      '-keyout', '$nome.key', '-out', '$nome.csr',
      '-subj', '/CN=$microArea/O=Outra Org/OU=Outra',
    ]);
    final csrComRdn = await File('${dir.path}/$nome.csr').readAsString();
    for (final (serial, esperado) in [
      (
        BigInt.parse('f1e2d3c4b5a6478890a1b2c3d4e5f601', radix: 16),
        'F1E2D3C4B5A6478890A1B2C3D4E5F601',
      ),
      (BigInt.from(0xabc), '0ABC'),
    ]) {
      final pem = await ca.sign(
        csrPem: csrComRdn,
        serial: serial,
        commonName: microArea,
        sanUris: ['urn:sinalacs:device:dev-1'],
        notBefore: DateTime.utc(2026, 10, 27, 11),
        notAfter: DateTime.utc(2026, 11, 26, 12),
      );
      final p = await tmp('leaf-rdn.pem', pem);
      final r = await run([
        'x509', '-in', p, '-noout', '-subject', '-serial',
        '-nameopt', 'RFC2253',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout as String, contains('subject=CN=$microArea\n'));
      expect(r.stdout as String, contains('serial=$esperado\n'));
      expect((await verify(pem, caCert)).exitCode, 0);
    }
  });

  test('sign recusa CSR com CN diferente do pedido', () async {
    final outro = await novoCsr(cn: 'outra-microarea');
    expect(
      () => ca.sign(
        csrPem: outro,
        serial: BigInt.from(11),
        commonName: microArea,
        sanUris: ['urn:sinalacs:device:dev-2'],
        notBefore: DateTime.utc(2026, 10, 27, 11),
        notAfter: DateTime.utc(2026, 11, 26, 12),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  group('C1 (revisão final): SAN e CN não injetam configuração no OpenSSL', () {
    // O `-extfile` é configuração do OpenSSL: `${ENV::X}` e `$x` são expandidos
    // e `#` corta a linha. Provado antes da correção: o SAN
    // `urn:sinalacs:device:${ENV::JWT_SECRET}` saía na folha com o valor do
    // segredo. O binário aqui não existe: se a validação deixasse passar, a
    // chamada ao `openssl` viraria StateError, não ArgumentError.
    final semBinario = OpensslDeviceCa(
      DeviceCaConfig(
        caCertPath: '/inexistente/ca.crt',
        caKeyPath: '/inexistente/ca.key',
        crlPath: '/inexistente/crl.pem',
        certDays: 30,
        crlDays: 30,
      ),
      opensslBinary: '/inexistente/openssl',
    );

    Future<String> assinar({
      List<String> sanUris = const ['urn:sinalacs:device:dev-1'],
      String commonName = microArea,
    }) => semBinario.sign(
      csrPem: 'irrelevante',
      serial: BigInt.from(7),
      commonName: commonName,
      sanUris: sanUris,
      notBefore: DateTime.utc(2026, 10, 27, 11),
      notAfter: DateTime.utc(2026, 11, 26, 12),
    );

    for (final uri in [
      r'urn:sinalacs:device:${ENV::JWT_SECRET}',
      r'urn:sinalacs:device:$HOME',
      r'urn:sinalacs:device:{x}',
      'urn:sinalacs:device:a#comentario',
      'urn:sinalacs:device:a\nsubjectAltName=URI:urn:x',
      'urn:sinalacs:device:a\\b',
    ]) {
      test('recusa SAN com metacaractere do OpenSSL sem chamar o binário: $uri',
          () async {
        await expectLater(
          assinar(sanUris: [uri]),
          throwsA(isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('OpenSSL interpreta'),
          )),
        );
      });
    }

    for (final uri in [
      'https://exemplo/x',
      'URN:sinalacs:device:dev-1',
      'urn:sinalacs:device:a b',
      'urn:sinalacs:device:a,URI:urn:b',
      'urn:',
    ]) {
      test('recusa SAN fora de urn: com alfabeto fechado: $uri', () async {
        await expectLater(
          assinar(sanUris: [uri]),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test(r'recusa CN com ${ENV::...} sem chamar o binário', () async {
      await expectLater(
        assinar(commonName: r'${ENV::JWT_SECRET}'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a folha real nunca contém a expansão de uma variável do ambiente',
        () async {
      // Com o binário real: o SAN malicioso é recusado antes do openssl, então
      // nenhuma folha é emitida.
      await expectLater(
        ca.sign(
          csrPem: csr,
          serial: BigInt.from(8),
          commonName: microArea,
          sanUris: [r'urn:sinalacs:device:${ENV::PATH}'],
          notBefore: DateTime.utc(2026, 10, 27, 11),
          notAfter: DateTime.utc(2026, 11, 26, 12),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('inspectCsr identifica EC prime256v1 e recusa RSA', () async {
    final info = await ca.inspectCsr(csr);
    expect(info.commonName, microArea);
    expect(info.keyAlgorithm, 'id-ecPublicKey');
    expect(info.curve, 'prime256v1');

    final rsa = await ca.inspectCsr(await novoCsr(cn: microArea, alg: 'rsa'));
    expect(rsa.keyAlgorithm, 'rsaEncryption');
    expect(rsa.curve, isNull);
  });

  test('inspectCsr recusa CSR com assinatura adulterada', () async {
    // Troca o CN no DER sem reassinar: o PEM continua bem-formado, mas a
    // assinatura deixa de conferir.
    final der = await run([
      'req', '-in', await tmp('orig.csr', csr), '-outform', 'DER',
      '-out', 'orig.der',
    ]);
    expect(der.exitCode, 0);
    final bytes = await File('${dir.path}/orig.der').readAsBytes();
    final alvo = '000000000003'.codeUnits;
    var i = -1;
    for (var k = 0; k + alvo.length <= bytes.length; k++) {
      var igual = true;
      for (var j = 0; j < alvo.length; j++) {
        if (bytes[k + j] != alvo[j]) {
          igual = false;
          break;
        }
      }
      if (igual) {
        i = k;
        break;
      }
    }
    expect(i, isNonNegative);
    bytes[i + alvo.length - 1] = '4'.codeUnitAt(0);
    await File('${dir.path}/adulterado.der').writeAsBytes(bytes);
    final pem = await run([
      'req', '-in', 'adulterado.der', '-inform', 'DER', '-out', 'adulterado.csr',
    ]);
    expect(pem.exitCode, 0, reason: '${pem.stderr}');
    final adulterado =
        await File('${dir.path}/adulterado.csr').readAsString();

    expect(() => ca.inspectCsr(adulterado), throwsA(isA<FormatException>()));
    expect(() => ca.inspectCsr('não é um CSR'),
        throwsA(isA<FormatException>()));
  });

  test(
      'buildCrl lista a serial revogada, com nextUpdate em now+days e '
      'assinatura válida', () async {
    final crl = await ca.buildCrl(
      revoked: [
        RevokedEntry(
          serial: BigInt.from(10),
          revokedAt: DateTime.utc(2026, 10, 27, 10),
          notAfter: DateTime.utc(2026, 11, 26, 12),
          commonName: 'x',
        ),
      ],
      crlNumber: BigInt.from(7),
      now: DateTime.utc(2026, 10, 27, 12),
      days: 30,
    );
    final txt = await crlText(crl);
    expect(txt, contains('Serial Number: 0A'));
    expect(txt, contains('Last Update: Oct 27 12:00:00 2026 GMT'));
    expect(txt, contains('Next Update: Nov 26 12:00:00 2026 GMT'));
    expect(txt, contains('X509v3 CRL Number:'));
    expect((await verifyCrl(crl, caCert)).exitCode, 0);
  });

  test('buildCrl vazia ainda é uma CRL válida', () async {
    final crl = await ca.buildCrl(
      revoked: const [],
      crlNumber: BigInt.one,
      now: DateTime.utc(2026, 10, 27, 12),
      days: 30,
    );
    final txt = await crlText(crl);
    expect(txt, contains('No Revoked Certificates'));
    expect((await verifyCrl(crl, caCert)).exitCode, 0);
  });

  group('DeviceCaConfig.fromEnvironment', () {
    test('sem as três variáveis de caminho → null', () {
      expect(DeviceCaConfig.fromEnvironment(const {}), isNull);
    });

    test('subconjunto das três → StateError nomeando as três', () {
      expect(
        () => DeviceCaConfig.fromEnvironment(
            const {'DEVICE_CA_CERT_PATH': '/a/ca.crt'}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('DEVICE_CA_CERT_PATH'),
              contains('DEVICE_CA_KEY_PATH'), contains('DEVICE_CRL_PATH')),
        )),
      );
    });

    test('as três presentes; dias com padrão 30 e validados', () {
      final c = DeviceCaConfig.fromEnvironment(const {
        'DEVICE_CA_CERT_PATH': '/a/ca.crt',
        'DEVICE_CA_KEY_PATH': '/a/ca.key',
        'DEVICE_CRL_PATH': '/a/crl.pem',
      })!;
      expect(c.caCertPath, '/a/ca.crt');
      expect(c.caKeyPath, '/a/ca.key');
      expect(c.crlPath, '/a/crl.pem');
      expect(c.certDays, 30);
      expect(c.crlDays, 30);
      expect(
        () => DeviceCaConfig.fromEnvironment(const {
          'DEVICE_CA_CERT_PATH': '/a/ca.crt',
          'DEVICE_CA_KEY_PATH': '/a/ca.key',
          'DEVICE_CRL_PATH': '/a/crl.pem',
          'DEVICE_CERT_DAYS': 'trinta',
        }),
        throwsA(isA<StateError>()),
      );
    });
  });
}
