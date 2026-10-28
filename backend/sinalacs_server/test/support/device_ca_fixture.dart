import 'dart:io';

import 'package:sinalacs_server/src/config/device_ca_config.dart';
import 'package:test/test.dart';

/// CA de aparelhos descartável (#94) para os testes da emissão e da CRL: uma
/// CA EC P-256 em `Directory.systemTemp`, apagada por [dispose]. Roda o
/// `openssl` de verdade; sem ele no PATH o teste FALHA (o backend depende dele).
/// Nenhum conteúdo de chave é impresso.
class DeviceCaFixture {
  DeviceCaFixture._(this.dir);

  final Directory dir;

  String get caCert => '${dir.path}/ca.crt';
  String get caKey => '${dir.path}/ca.key';
  String get crlPath => '${dir.path}/crl.pem';

  DeviceCaConfig config({int certDays = 30, int crlDays = 30}) =>
      DeviceCaConfig(
        caCertPath: caCert,
        caKeyPath: caKey,
        crlPath: crlPath,
        certDays: certDays,
        crlDays: crlDays,
      );

  static Future<DeviceCaFixture> create({String cn = 'sinalacs-test-devices-ca'}) async {
    final f = DeviceCaFixture._(
      await Directory.systemTemp.createTemp('sinalacs-device-ca-fixture-'),
    );
    await f.ok([
      'req', '-x509', '-newkey', 'ec', '-pkeyopt',
      'ec_paramgen_curve:prime256v1', '-nodes', '-days', '30',
      '-keyout', 'ca.key', '-out', 'ca.crt', '-subj', '/CN=$cn',
    ]);
    return f;
  }

  Future<void> dispose() => dir.delete(recursive: true);

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

  var _n = 0;

  /// CSR novo (chave EC P-256, ou RSA 2048 com [rsa]) com `CN=[cn]`.
  Future<String> csr({required String cn, bool rsa = false}) async {
    final nome = 'csr-${_n++}';
    await ok([
      'req', '-new', '-nodes',
      '-newkey', rsa ? 'rsa:2048' : 'ec',
      if (!rsa) ...['-pkeyopt', 'ec_paramgen_curve:prime256v1'],
      '-keyout', '$nome.key', '-out', '$nome.csr', '-subj', '/CN=$cn',
    ]);
    return File('${dir.path}/$nome.csr').readAsString();
  }

  Future<String> _tmp(String conteudo) async {
    final f = File('${dir.path}/tmp-${_n++}.pem');
    await f.writeAsString(conteudo);
    return f.path;
  }

  /// `openssl x509 -text` da folha, com `CN = x` (`-nameopt oneline`).
  Future<String> x509Text(String pem) async {
    final r = await run([
      'x509', '-in', await _tmp(pem), '-noout', '-text', '-serial',
      '-nameopt', 'oneline',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return r.stdout as String;
  }

  /// `openssl verify` da folha contra esta CA, como cliente TLS.
  Future<ProcessResult> verify(String pem) async =>
      run(['verify', '-purpose', 'sslclient', '-CAfile', caCert, await _tmp(pem)]);

  /// `openssl crl -text` de um arquivo de CRL.
  Future<String> crlText(String path) async {
    final r = await run(['crl', '-in', path, '-noout', '-text']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return r.stdout as String;
  }

  /// A assinatura da CRL em [path] confere com esta CA.
  Future<bool> crlVerifies(String path) async =>
      (await run(['crl', '-in', path, '-CAfile', caCert, '-noout'])).exitCode == 0;
}
