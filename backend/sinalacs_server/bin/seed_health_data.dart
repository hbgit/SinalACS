import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Segunda metade do seed de desenvolvimento: os campos CIFRADOS de `patients`.
///
/// `seeds/development.sql` é SQL puro, executado por `psql` fora do processo
/// Dart, e por isso não consegue chamar [HealthDataCipher] —
/// `patients.chronicConditionsEncrypted` e
/// `patients.emergencyContactEncrypted` são AES-256-GCM, não expressões que
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

/// Contato de emergência sintético por paciente (PII de terceiro — cifrado
/// pelo mesmo motivo de chronicConditions, RNF03/INV-04). Mesmos UUIDs do
/// `development.sql`: o `.sql` grava ciphertext vazio e este script completa.
const _emergencyContactByPatient = <String, String>{
  '00000000-0000-4000-8000-000000000001': 'Contato de desenvolvimento',
  '00000000-0000-4000-8000-000000000005': 'Contato de desenvolvimento',
  '00000000-0000-4000-8000-000000000006': 'Contato de desenvolvimento',
  '00000000-0000-4000-8000-000000000007': 'Contato de desenvolvimento',
  '00000000-0000-4000-8000-000000000008': 'Contato de desenvolvimento',
  '00000000-0000-4000-8000-000000000009': 'Contato de desenvolvimento',
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
    // Conjunto de pacientes tocados (não contador de linhas): dois laços
    // separados de propósito — condições crônicas e contato de emergência
    // podem evoluir independentemente no futuro.
    final atualizados = <String>{};
    for (final entry in _chronicConditionsByPatient.entries) {
      final encrypted = await cipher.encryptJson(entry.value);
      await connection.execute(
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
      atualizados.add(entry.key);
    }
    for (final entry in _emergencyContactByPatient.entries) {
      final encrypted = await cipher.encryptJson(entry.value);
      await connection.execute(
        Sql.named(
          'UPDATE "patients" '
          '   SET "emergencyContactEncrypted" = @ciphertext, '
          '       "emergencyContactKeyVersion" = @keyVersion '
          ' WHERE "id" = @id',
        ),
        parameters: {
          'ciphertext': encrypted.ciphertextBase64,
          'keyVersion': encrypted.keyVersion,
          'id': entry.key,
        },
      );
      atualizados.add(entry.key);
    }
    stdout.writeln(
      'Seed de campos cifrados de patients: ${atualizados.length} paciente(s) '
      'atualizado(s).',
    );
  } finally {
    await connection.close();
  }
}
