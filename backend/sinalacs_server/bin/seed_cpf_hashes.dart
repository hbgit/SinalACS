import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';

/// Quarta metade do seed de desenvolvimento: os hashes de CPF do RF01.
///
/// `seeds/development.sql` gravava literais (`'development-patient'`) porque
/// nenhum código calculava CPF. Agora que o login procura por
/// `users.cpfHash = HMAC(cpf)`, um literal nunca casa — e o paciente de
/// desenvolvimento não conseguiria entrar.
///
/// CPFs SINTÉTICOS, os exemplos da documentação do algoritmo de dígito
/// verificador. **Nunca** um CPF real (regra do repositório: nada de dado real
/// em seed, teste ou log).
const _cpfByUser = <String, String>{
  '00000000-0000-4000-8000-000000000001': '12345678909',
  '00000000-0000-4000-8000-000000000005': '98765432100',
  '00000000-0000-4000-8000-000000000006': '11144477735',
  '00000000-0000-4000-8000-000000000007': '52998224725',
  '00000000-0000-4000-8000-000000000008': '16899535009',
};

/// Datas de nascimento correspondentes (as mesmas do `development.sql`).
const _birthDateByUser = <String, String>{
  '00000000-0000-4000-8000-000000000001': '1990-01-01',
  '00000000-0000-4000-8000-000000000005': '1975-03-10',
  '00000000-0000-4000-8000-000000000006': '1988-07-22',
  '00000000-0000-4000-8000-000000000007': '1962-11-30',
  '00000000-0000-4000-8000-000000000008': '1999-05-14',
};

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final config = AppConfig.fromEnvironment();

  if (config.appEnv != 'development') {
    stderr.writeln(
      'Recusando rodar: este script grava CPFs SINTÉTICOS de desenvolvimento e '
      'APP_ENV=${config.appEnv}.',
    );
    exit(2);
  }

  // A MESMA instância que o servidor usa, pelo mesmo pepper: se divergirem,
  // nenhum CPF do seed é encontrado no login.
  final hasher = HmacCpfHasher(pepper: config.cpfHashPepper);

  final connection = await Connection.open(
    Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: env['SERVERPOD_DATABASE_NAME'] ?? 'sinalacs_db',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'sinalacs_user',
      password: env['SERVERPOD_DATABASE_PASSWORD'],
    ),
    settings: ConnectionSettings(
      sslMode: env['SERVERPOD_DATABASE_REQUIRE_SSL'] == 'true'
          ? SslMode.require
          : SslMode.disable,
    ),
  );

  try {
    var atualizados = 0;
    for (final entry in _cpfByUser.entries) {
      final cpf = Cpf.tryParse(entry.value);
      if (cpf == null) {
        // Falha alto em vez de gravar um hash de CPF inválido: um DV errado no
        // mapa acima produziria um paciente que existe e não consegue entrar.
        throw StateError('CPF sintético inválido para ${entry.key}');
      }
      final result = await connection.execute(
        Sql.named(
          'UPDATE "users" '
          '   SET "cpfHash" = @cpfHash, "birthDate" = @birthDate::date, '
          '       "updatedAt" = NOW() '
          ' WHERE "id" = @id',
        ),
        parameters: {
          'cpfHash': hasher.hash(cpf),
          'birthDate': _birthDateByUser[entry.key],
          'id': entry.key,
        },
      );
      atualizados += result.affectedRows;
    }
    stdout.writeln(
      'Seed de CPF (RF01): $atualizados linha(s) de users atualizada(s).',
    );
  } finally {
    await connection.close();
  }
}
