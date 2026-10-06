import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';

/// Terceira metade do seed de desenvolvimento: a credencial institucional.
///
/// `seeds/development.sql` roda por `psql`, FORA do processo Dart, e por isso
/// não consegue derivar Argon2id — mesmo motivo de `bin/seed_health_data.dart`.
/// Colar um hash literal no `.sql` seria a alternativa, e foi rejeitada pelo
/// mesmo raciocínio: a lógica de KDF passaria a existir em dois lugares e
/// quebraria em silêncio a cada troca de parâmetro.
///
/// A senha vem de `DEV_ACS_PASSWORD`, gerada por máquina em
/// `scripts/dev/bootstrap_env.sh`. **Nunca** um literal versionado: uma senha
/// de desenvolvimento fixa no git é uma credencial pública.
Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final appEnv = env['APP_ENV'] ?? 'development';
  if (appEnv != 'development') {
    stderr.writeln(
      'Recusando rodar: este script cria uma credencial de DESENVOLVIMENTO e '
      'APP_ENV=$appEnv. Ele nunca deve tocar um banco que não seja local.',
    );
    exit(2);
  }

  final password = env['DEV_ACS_PASSWORD'];
  if (password == null || password.isEmpty) {
    stderr.writeln(
      'DEV_ACS_PASSWORD não definida. Rode ./scripts/dev/bootstrap_env.sh para '
      'gerá-la no .env.',
    );
    exit(2);
  }

  final adminPassword = env['DEV_ADMIN_PASSWORD'];
  if (adminPassword == null || adminPassword.isEmpty) {
    stderr.writeln(
      'DEV_ADMIN_PASSWORD não definida. Acrescente-a ao .env (por exemplo '
      '`echo "DEV_ADMIN_PASSWORD=\$(openssl rand -hex 32)" >> .env`) ou rode '
      './scripts/dev/bootstrap_env.sh numa máquina nova.',
    );
    exit(2);
  }

  // UUID do ACS semeado. `development.sql` cria a linha de `users` e a de `acs`
  // com ESTE mesmo UUID fixo, e é a de `acs` que carrega
  // `enrollmentId = 'ACS-001'` — o ACS do dev-login. `user_credentials.userId`
  // tem FK para `users`, então um UUID que não exista ali falha alto em vez de
  // gravar uma credencial órfã que ninguém consegue usar.
  const acsId = '00000000-0000-4000-8000-000000000002';
  // UUID do admin do backoffice (`users` role admin + `staff_accounts`
  // ADM-001, criados por `development.sql`). Mesma FK: id inexistente falha alto.
  const adminId = '00000000-0000-4000-8000-000000000090';
  const hasher = Argon2PasswordHasher();
  final digest = await hasher.derive(password);
  final adminDigest = await hasher.derive(adminPassword);

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
    Future<void> grava(String userId, PasswordDigest d) => connection.execute(
      Sql.named(
        'INSERT INTO "user_credentials" '
        '  ("userId", "passwordHash", "passwordSalt", "memoryKb", '
        '   "iterations", "parallelism", "failedAttempts", "createdAt", "updatedAt") '
        'VALUES (@userId, @hash, @salt, @memoryKb, @iterations, @parallelism, 0, NOW(), NOW()) '
        'ON CONFLICT ("userId") DO UPDATE SET '
        '  "passwordHash" = @hash, "passwordSalt" = @salt, '
        '  "memoryKb" = @memoryKb, "iterations" = @iterations, '
        '  "parallelism" = @parallelism, "failedAttempts" = 0, '
        '  "lockedUntil" = NULL, "updatedAt" = NOW()',
      ),
      parameters: {
        'userId': userId,
        'hash': d.hashBase64,
        'salt': d.saltBase64,
        'memoryKb': d.memoryKb,
        'iterations': d.iterations,
        'parallelism': d.parallelism,
      },
    );

    await grava(acsId, digest);
    stdout.writeln(
      'Credencial de desenvolvimento do ACS ${acsId.substring(0, 8)}… gravada.',
    );
    await grava(adminId, adminDigest);
    stdout.writeln(
      'Credencial de desenvolvimento do admin ${adminId.substring(0, 8)}… '
      'gravada.',
    );
  } finally {
    await connection.close();
  }
}
