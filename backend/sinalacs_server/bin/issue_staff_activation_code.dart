import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:sinalacs_server/src/ops/staff_activation_issuer.dart';

/// Emite o código de ativação de uso único da MFA de uma conta de staff (#48).
///
///   `dart run bin/issue_staff_activation_code.dart MATRICULA --issued-by QUEM [--ttl-hours 24]`
///
/// Ferramenta de OPERAÇÃO: roda com acesso ao banco (as mesmas variáveis
/// `SERVERPOD_DATABASE_*` do servidor) e entrega o código fora de banda a quem
/// vai ativar a conta. O código aparece UMA vez, na saída; o banco guarda só o
/// hash. A emissão fica em `staff_accounts.activationCodeIssuedBy/At`.
///
/// Saída 2: argumento ausente, matrícula inexistente ou conta inativa (sem
/// distinguir os dois últimos, e sem imprimir código nenhum).
Future<void> main(List<String> args) async {
  String? matricula;
  String? issuedBy;
  var ttlHours = StaffActivationCode.defaultValidity.inHours;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--issued-by':
        issuedBy = i + 1 < args.length ? args[++i] : null;
      case '--ttl-hours':
        ttlHours = int.tryParse(i + 1 < args.length ? args[++i] : '') ?? 0;
      default:
        matricula ??= args[i];
    }
  }
  if (matricula == null || issuedBy == null || issuedBy.trim().isEmpty || ttlHours <= 0) {
    stderr.writeln('uso: dart run bin/issue_staff_activation_code.dart <matricula> --issued-by <quem> [--ttl-hours 24]');
    exit(2);
  }

  final env = Platform.environment;
  final conexao = await pg.Connection.open(
    pg.Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: env['SERVERPOD_DATABASE_NAME'] ?? 'sinalacs_db',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'sinalacs_user',
      password: env['SERVERPOD_DATABASE_PASSWORD'],
    ),
    settings: pg.ConnectionSettings(
      sslMode: env['SERVERPOD_DATABASE_REQUIRE_SSL'] == 'true' ? pg.SslMode.require : pg.SslMode.disable,
    ),
  );
  try {
    final r = await issueStaffActivationCode(
      conexao,
      matricula: matricula,
      issuedBy: issuedBy,
      validity: Duration(hours: ttlHours),
    );
    if (r.status != IssueStatus.issued) {
      stderr.writeln('Matrícula inexistente ou conta inativa. Nenhum código foi emitido.');
      exit(2);
    }
    stdout.writeln('Código de ativação (mostrado uma única vez): ${r.code}');
    stdout.writeln('Vale até ${r.expiresAt!.toIso8601String()} e só pode ser usado uma vez.');
  } finally {
    await conexao.close();
  }
}
