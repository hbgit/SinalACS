/// Prova de território com o banco de e2e: o ACS da microárea lista os pacientes
/// dela (`main`, `chronic`) e NÃO o da outra (`outsider`).
///
///   E2E_FIXTURES_FILE=.e2e/fixtures.json ACS_MATRICULA=… ACS_PASSWORD=… \
///     dart run tool/territory_check.dart [--host https://localhost/]
///
/// Roda no host, e não dentro do aparelho, para que a senha do ACS chegue por
/// ambiente e nunca por `--dart-define` (que iria para o argv do `flutter test` e
/// seria compilado no APK). Saída: `territorio=ok` e código 0; qualquer
/// divergência imprime o que faltou (nomes sintéticos, nunca CPF) e sai com 2.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

import '../test/support/e2e_config.dart';

Future<void> main(List<String> args) async {
  final path = Platform.environment['E2E_FIXTURES_FILE'];
  final matricula = Platform.environment['ACS_MATRICULA'];
  final password = Platform.environment['ACS_PASSWORD'];
  if (path == null || matricula == null || password == null) {
    stderr.writeln('erro: defina E2E_FIXTURES_FILE, ACS_MATRICULA e ACS_PASSWORD.');
    exitCode = 2;
    return;
  }
  final config = E2eConfig.fromMap((jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>())!;
  final index = args.indexOf('--host');
  final host = index >= 0 && index + 1 < args.length ? args[index + 1] : 'https://localhost/';
  // apps/patient/tool/territory_check.dart → raiz do repositório.
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  final ca = File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt').readAsBytesSync();

  final client = Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
    ..connectivityMonitor = null;
  try {
    final session = await client.auth.loginInstitutional(matricula: matricula, password: password);
    final names = (await client.patients.listMicroArea(accessToken: session.accessToken)).map((p) => p.name).toSet();
    final falhas = <String>[
      for (final role in ['main', 'chronic'])
        if (!names.contains(config.patient(role).name)) 'faltou na lista: ${config.patient(role).name}',
      if (names.contains(config.patient('outsider').name)) 'vazou de outra microárea: ${config.patient('outsider').name}',
    ];
    if (falhas.isNotEmpty) {
      stderr.writeln(falhas.join('\n'));
      exitCode = 2;
      return;
    }
    stdout.writeln('territorio=ok');
  } finally {
    client.close();
  }
}
