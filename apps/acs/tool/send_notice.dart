/// Envia UM aviso comunitário como ACS de desenvolvimento e imprime só as contagens.
///
///   dart run tool/send_notice.dart --title "SinalACS e2e" --message "Teste do Gorush" \
///       [--chronic] [--host https://localhost/]
///
/// Entra com `ACS_MATRICULA` e `ACS_PASSWORD` (login institucional, RF07) quando
/// definidas; sem elas, precisa da stack de pé com `ENABLE_DEV_LOGIN=true`. Nunca imprime token nem
/// destinatários. Saída: `recipients=<n> accepted=<m>` e código 0; uma recusa ou
/// falha de envio imprime a MENSAGEM e sai com 2 (para um script distinguir "falhou"
/// de "0 destinatários", que sai com 0).
library;

import 'dart:io';

import 'package:sinalacs_acs/core/network/backend_client.dart';

import 'send_notice_login.dart';

String _arg(List<String> args, String name, String fallback) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

/// Mesma CA que `tool/live_check.dart` usa: a que assina o certificado do Traefik.
File _devRpcCaFile() {
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  return File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('uso: dart run tool/send_notice.dart --title <t> --message <m> '
        '[--chronic] [--host https://localhost/]');
    return;
  }
  final title = _arg(args, 'title', '');
  final message = _arg(args, 'message', '');
  if (title.isEmpty || message.isEmpty) {
    stderr.writeln('erro: informe --title e --message.');
    exitCode = 2;
    return;
  }
  final String host;
  try {
    host = requireSecureHost(_arg(args, 'host', 'https://localhost/'));
  } on BackendFailure catch (failure) {
    stderr.writeln('erro: ${failure.message}');
    exitCode = 2;
    return;
  }
  final AcsCredentials? credentials;
  try {
    credentials = acsCredentialsFromEnv(Platform.environment);
  } on ArgumentError catch (error) {
    stderr.writeln('erro: ${error.message}');
    exitCode = 2;
    return;
  }
  final caFile = _devRpcCaFile();
  if (!await caFile.exists()) {
    stderr.writeln('erro: a CA do RPC não existe em ${caFile.path}. Suba a stack.');
    exitCode = 2;
    return;
  }

  final backend = BackendClient(host: host, trustedCaBytes: await caFile.readAsBytes());
  try {
    if (credentials == null) {
      await backend.developmentLogin(role: 'acs');
    } else {
      await backend.login(matricula: credentials.matricula, senha: credentials.password);
    }
    final result = await backend.sendNotice(
      title: title,
      message: message,
      chronicOnly: args.contains('--chronic'),
    );
    stdout.writeln('recipients=${result.recipients} accepted=${result.accepted}');
  } on BackendFailure catch (failure) {
    stderr.writeln('falhou: ${failure.message}');
    exitCode = 2;
  } finally {
    backend.close();
  }
}
