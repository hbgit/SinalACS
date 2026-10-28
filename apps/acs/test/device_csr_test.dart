import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/device_csr.dart';

const _microArea = '00000000-0000-4000-8000-000000000003';

void main() {
  test(
    'CSR gerado em Dart é verificado pelo openssl e leva CN = microárea',
    () async {
      final par = generateDeviceKeyPair();
      final csr = buildDeviceCsrPem(keyPair: par, microAreaId: _microArea);
      final dir = await Directory.systemTemp.createTemp('csr');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/d.csr')..writeAsStringSync(csr);
      ProcessResult r;
      try {
        r = await Process.run('openssl', [
          'req', '-in', f.path, '-noout', '-verify', '-subject',
          '-nameopt', 'RFC2253', '-pubkey', //
        ]);
      } on ProcessException catch (e) {
        fail('openssl ausente do PATH; o teste precisa dele: $e');
      }
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains('subject=CN=$_microArea'));
      expect('${r.stdout}', contains('BEGIN PUBLIC KEY'));
      expect(par.privateKeyPem, contains('BEGIN EC PRIVATE KEY'));
      expect(csr, isNot(contains('PRIVATE')));
    },
  );

  test('dois pares gerados são diferentes', () {
    expect(
      generateDeviceKeyPair().privateKeyPem,
      isNot(generateDeviceKeyPair().privateKeyPem),
    );
  });
}
