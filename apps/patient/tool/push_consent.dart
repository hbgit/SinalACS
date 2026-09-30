/// Concede ou revoga `segmentedPush` como o paciente de desenvolvimento, pelo RPC real.
///
///   dart run tool/push_consent.dart --grant | --revoke [--host https://localhost/]
///
/// Serve ao `scripts/qa/push_e2e.sh` (caso "revogar zera os destinatários"). Precisa
/// da stack de pé com `ENABLE_DEV_LOGIN=true`. Saída: `consent=granted|revoked`; uma
/// falha imprime a mensagem e sai com 2.
library;

import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart' show ConsentPurpose;
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/host_login.dart';

Future<void> main(List<String> args) async {
  final grant = args.contains('--grant');
  if (grant == args.contains('--revoke')) {
    stderr.writeln('uso: dart run tool/push_consent.dart --grant | --revoke [--host https://localhost/]');
    exitCode = 2;
    return;
  }
  final index = args.indexOf('--host');
  final String host;
  try {
    host = requireSecureHost(index >= 0 && index + 1 < args.length ? args[index + 1] : 'https://localhost/');
  } on BackendFailure catch (failure) {
    stderr.writeln('erro: ${failure.message}');
    exitCode = 2;
    return;
  }
  // apps/patient/tool/push_consent.dart → raiz do repositório.
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  final caFile = File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt');
  if (!await caFile.exists()) {
    stderr.writeln('erro: a CA do RPC não existe em ${caFile.path}. Suba a stack.');
    exitCode = 2;
    return;
  }
  final backend = BackendClient(host: host, trustedCaBytes: await caFile.readAsBytes());
  try {
    await loginPatientOnHost(backend, role: 'push');
    await backend.updateConsent(purpose: ConsentPurpose.segmentedPush, granted: grant);
    stdout.writeln('consent=${grant ? 'granted' : 'revoked'}');
  } on BackendFailure catch (failure) {
    stderr.writeln('falhou: ${failure.message}');
    exitCode = 2;
  } finally {
    backend.close();
  }
}
