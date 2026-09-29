import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Segunda metade do seed de desenvolvimento: os campos clínicos CIFRADOS.
///
/// `seeds/development.sql` é SQL puro, executado por `psql` fora do processo
/// Dart, e por isso não consegue chamar [HealthDataCipher] —
/// `patients.chronicConditionsEncrypted` é AES-256-GCM, não uma expressão que
/// o Postgres saiba montar. As duas alternativas eram colar um ciphertext
/// literal no `.sql` (que quebra silenciosamente a cada mudança de algoritmo
/// ou de chave) ou mover só esses campos para um passo Dart pós-boot. Este
/// arquivo é a segunda: a lógica de cifragem continua existindo em UM único
/// lugar.
///
/// O `.sql` insere as linhas com ciphertext vazio; este script as completa.
/// Roda depois do `database-seed` no `docker-compose.yml`.
///
/// Dados sintéticos apenas — nunca condição real de paciente (LGPD).
const _chronicConditionsByPatient = <String, List<String>>{
  '00000000-0000-4000-8000-000000000001': [],
  '00000000-0000-4000-8000-000000000005': ['hipertensão'],
  '00000000-0000-4000-8000-000000000006': [],
  '00000000-0000-4000-8000-000000000007': ['diabetes', 'hipertensão'],
  '00000000-0000-4000-8000-000000000008': [],
  '00000000-0000-4000-8000-000000000009': [],
};

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final config = AppConfig.fromEnvironment();

  // A MESMA chave que o servidor usa: se as duas divergirem, o diretório de
  // pacientes falha ao decifrar o que este script gravou. Por isso ambos leem
  // `HEALTH_DATA_ENCRYPTION_KEY` do mesmo `.env`, via `AppConfig`.
  final cipher = HealthDataCipher(
    keyHex: config.healthDataEncryptionKey,
    keyVersion: 1,
  );

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
    for (final entry in _chronicConditionsByPatient.entries) {
      final encrypted = await cipher.encryptJson(entry.value);
      final result = await connection.execute(
        Sql.named(
          'UPDATE "patients" '
          '   SET "chronicConditionsEncrypted" = @ciphertext, '
          '       "chronicConditionsKeyVersion" = @keyVersion '
          ' WHERE "id" = @id',
        ),
        parameters: {
          'ciphertext': encrypted.ciphertextBase64,
          'keyVersion': encrypted.keyVersion,
          'id': entry.key,
        },
      );
      atualizados += result.affectedRows;
    }
    stdout.writeln(
      'Seed de dados clínicos cifrados: $atualizados linha(s) de patients '
      'atualizada(s).',
    );
  } finally {
    await connection.close();
  }
}
