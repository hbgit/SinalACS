import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/infrastructure/testing/e2e_fixtures.dart';

/// Insere UM aviso agendado (#46) já na fila do `NoticeDispatchLoop`, para o
/// `push_e2e.sh` provar o disparo real pelo laço do servidor (reserva, envio
/// por Gorush/FCM e auditoria). O login de staff exige TOTP e não é scriptável
/// ali, então o agendamento entra direto no banco; o endpoint HTTP e as
/// negações por papel são cobertos pelos testes de integração do backend.
///
/// Mesma guarda do `seed_e2e_fixtures.dart`: só escreve no `sinalacs_e2e`.
/// Lê o manifesto e NUNCA imprime segredo, CPF, token nem o texto do aviso;
/// imprime só o id do aviso.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final refusal = e2eSeedRefusal(env);
  if (refusal != null) {
    stderr.writeln('Recusando rodar: $refusal');
    exit(2);
  }
  final manifest = File(args.isNotEmpty ? args.first : '.e2e/fixtures.json');
  if (!manifest.existsSync()) {
    stderr.writeln('Manifesto ${manifest.path} não encontrado: rode o seed antes.');
    exit(2);
  }
  final json = jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
  final adminId = ((json['staff']! as Map)['id']) as String;
  final microAreaId = json['microAreaId']! as String;

  final connection = await Connection.open(
    Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '9090'),
      database: 'sinalacs_e2e',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'postgres',
      password: env['SERVERPOD_DATABASE_PASSWORD']!,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  try {
    final now = DateTime.now().toUtc();
    final result = await connection.execute(
      Sql.named('INSERT INTO "scheduled_notices" ("createdBy","microAreaId","audience","title","message",'
          '"scheduledFor","status","createdAt") '
          "VALUES (@by,@area,'everyone','SinalACS agendado e2e','Aviso agendado do Gorush',"
          "@quando::timestamp,'pending',@agora::timestamp) RETURNING \"id\""),
      parameters: {
        'by': adminId,
        'area': microAreaId,
        // Sem o `Z`: a coluna não tem fuso e guarda o instante UTC.
        'quando': now.add(const Duration(seconds: 20)).toIso8601String().replaceFirst('Z', ''),
        'agora': now.toIso8601String().replaceFirst('Z', ''),
      },
    );
    stdout.writeln('Aviso agendado de e2e criado (id=${result.first.first}).');
  } finally {
    await connection.close();
  }
}
