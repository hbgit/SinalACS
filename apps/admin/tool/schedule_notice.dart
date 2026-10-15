/// Agenda UM aviso comunitário pelo endpoint REAL `admin.scheduleNotice` (#46),
/// para o `push_e2e.sh` provar agendamento → laço do servidor → Gorush/FCM.
///
///   dart run tool/schedule_notice.dart <manifesto.json> [--host https://localhost/]
///
/// Entra como o staff (admin) das fixtures de e2e: ativa a MFA com o código de
/// ativação do manifesto, espera o passo TOTP seguinte (o servidor recusa o
/// mesmo código duas vezes) e entra com TOTP. Só serve à stack de e2e: as
/// fixtures são novas a cada execução. Nunca imprime senha, código, token nem o
/// texto do aviso; imprime só o id. Recusa ou falha: mensagem e código 2.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

import '../integration_test/support/totp.dart';

class StaffDoManifesto {
  const StaffDoManifesto({
    required this.matricula,
    required this.senha,
    required this.codigoAtivacao,
    required this.microAreaId,
  });

  final String matricula;
  final String senha;
  final String codigoAtivacao;
  final String microAreaId;
}

/// Lê o manifesto de `seed_e2e_fixtures.dart`. O erro cita só o campo ausente.
StaffDoManifesto lerManifesto(String json) {
  final m = jsonDecode(json) as Map<String, Object?>;
  final staff = m['staff'];
  final area = m['microAreaId'];
  if (staff is! Map || area is! String) {
    throw const FormatException('manifesto sem "staff" ou "microAreaId"');
  }
  String campo(String nome) {
    final v = staff[nome];
    if (v is! String) throw FormatException('manifesto sem "staff.$nome"');
    return v;
  }

  return StaffDoManifesto(
    matricula: campo('matricula'),
    senha: campo('password'),
    codigoAtivacao: campo('activationCode'),
    microAreaId: area,
  );
}

/// Passo TOTP (RFC 6238, 30 s) do instante.
int passoTotp(DateTime instante) => instante.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;

String _arg(List<String> args, String name, String fallback) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
}

/// A CA que assina o certificado do Traefik (a mesma do `tool/send_notice.dart` do ACS).
File _devRpcCaFile() {
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  return File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('uso: dart run tool/schedule_notice.dart <manifesto.json> [--host https://localhost/]');
    exitCode = 2;
    return;
  }
  final host = _arg(args, 'host', 'https://localhost/');
  if (!host.startsWith('https://')) {
    stderr.writeln('erro: o RPC é HTTPS (RNF04); recusando $host');
    exitCode = 2;
    return;
  }
  final StaffDoManifesto staff;
  try {
    staff = lerManifesto(await File(args.first).readAsString());
  } on Object catch (e) {
    stderr.writeln('erro: manifesto ilegível (${e is FormatException ? e.message : e.runtimeType})');
    exitCode = 2;
    return;
  }
  final ca = _devRpcCaFile();
  if (!await ca.exists()) {
    stderr.writeln('erro: a CA do RPC não existe em ${ca.path}. Suba a stack.');
    exitCode = 2;
    return;
  }

  final client = Client(
    host,
    securityContext: SecurityContext()..setTrustedCertificatesBytes(await ca.readAsBytes()),
  )..connectivityMonitor = null;
  try {
    final inscricao = await client.auth.beginStaffTotpEnrollment(
      matricula: staff.matricula,
      password: staff.senha,
      activationCode: staff.codigoAtivacao,
    );
    final segredo = base32Decode(inscricao.secretBase32);
    final ativacao = DateTime.now();
    await client.auth.confirmStaffTotpEnrollment(
      matricula: staff.matricula,
      password: staff.senha,
      activationCode: staff.codigoAtivacao,
      code: totpCode(segredo, ativacao),
    );
    // Anti-replay: o código do login precisa ser de um passo POSTERIOR ao da ativação.
    while (passoTotp(DateTime.now()) <= passoTotp(ativacao)) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final sessao = await client.auth.loginStaff(
      matricula: staff.matricula,
      password: staff.senha,
      totpCode: totpCode(segredo, DateTime.now()),
    );
    final id = await client.admin.scheduleNotice(
      accessToken: sessao.accessToken,
      microAreaId: staff.microAreaId,
      audience: 'everyone',
      title: 'SinalACS agendado e2e',
      message: 'Aviso agendado do Gorush',
      // O servidor exige ao menos 1 min (`noticeMinimumLeadTime`).
      scheduledFor: DateTime.now().toUtc().add(const Duration(seconds: 70)),
    );
    stdout.writeln('Aviso agendado de e2e criado (id=$id).');
  } on AdminInvalidRequestException catch (e) {
    stderr.writeln('recusado: ${e.message}');
    exitCode = 2;
  } on AlertPermissionException {
    stderr.writeln('recusado: sem permissão para agendar');
    exitCode = 2;
  } on Object catch (e) {
    // Só o tipo: a mensagem de uma exceção de auth pode ecoar a entrada.
    stderr.writeln('falhou: ${e.runtimeType}');
    exitCode = 2;
  } finally {
    client.close();
  }
}
