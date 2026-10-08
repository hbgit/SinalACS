import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/hmac_cpf_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/testing/e2e_fixtures.dart';

/// Seed da stack de e2e (`docker-compose.e2e.yml`): UBS, microáreas, dois ACS com
/// credencial e pacientes SINTÉTICOS com UUIDs e CPFs novos a cada execução.
/// Escreve o manifesto (`.e2e/fixtures.json`, modo 600) que os testes leem —
/// nenhum identificador é fixo no código.
///
/// Só escreve no banco `sinalacs_e2e`: nem o de desenvolvimento nem o
/// `sinalacs_test` do `dart test`. CPF, senha e token nunca vão para a saída.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final refusal = e2eSeedRefusal(env);
  if (refusal != null) {
    stderr.writeln('Recusando rodar: $refusal');
    exit(2);
  }
  final password = env['SERVERPOD_DATABASE_PASSWORD']!;

  final config = AppConfig.fromEnvironment();
  // A MESMA chave e o MESMO pepper que o servidor usa (vêm do mesmo .env).
  final cipher = HealthDataCipher(keyHex: config.healthDataEncryptionKey, keyVersion: 1);
  final hasher = HmacCpfHasher(pepper: config.cpfHashPepper);

  final fixtures = generateE2eFixtures(Random.secure());
  final acsDigest = await const Argon2PasswordHasher().derive(fixtures.acs.password);
  final secondAcsDigest = await const Argon2PasswordHasher().derive(fixtures.secondAcs.password);

  final connection = await Connection.open(
    Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: 'sinalacs_e2e',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'postgres',
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    await connection.runTx((tx) async {
      await tx.execute(
        Sql.named('INSERT INTO "ubs" ("id","name","address","city","state","contactPhone") '
            "VALUES (@id, 'UBS E2E', 'Endereço de teste', 'São Paulo', 'SP', '+55 11 5550-0199')"),
        parameters: {'id': fixtures.ubsId},
      );
      for (final entry in {fixtures.microAreaId: 'Microárea E2E', fixtures.otherMicroAreaId: 'Outra Microárea E2E'}.entries) {
        await tx.execute(
          Sql.named('INSERT INTO "micro_areas" ("id","name","ubsId","geoJsonBoundary") VALUES (@id,@name,@ubs,\'{}\')'),
          parameters: {'id': entry.key, 'name': entry.value, 'ubs': fixtures.ubsId},
        );
      }
      for (final p in fixtures.patients) {
        final cpf = Cpf.tryParse(p.cpf)!;
        await tx.execute(
          Sql.named('INSERT INTO "users" ("id","cpfHash","name","birthDate","role","microAreaId","createdAt","updatedAt") '
              "VALUES (@id,@hash,@name,@birth::date,'patient',@area,NOW(),NOW())"),
          parameters: {'id': p.id, 'hash': hasher.hash(cpf), 'name': p.name, 'birth': p.birthDate, 'area': p.microAreaId},
        );
        final conditions = p.chronic ? ['hipertensão'] : <String>[];
        final encrypted = await cipher.encryptJson(conditions);
        final encryptedContact = await cipher.encryptJson('Contato E2E');
        await tx.execute(
          Sql.named('INSERT INTO "patients" ("id","emergencyContactEncrypted","emergencyContactKeyVersion","isChronic","chronicConditionsEncrypted","chronicConditionsKeyVersion") '
              'VALUES (@id,@contactCipher,@contactVer,@chronic,@cipher,@ver)'),
          parameters: {
            'id': p.id,
            'contactCipher': encryptedContact.ciphertextBase64,
            'contactVer': encryptedContact.keyVersion,
            'chronic': p.chronic,
            'cipher': encrypted.ciphertextBase64,
            'ver': encrypted.keyVersion,
          },
        );
      }
      // Os ACS entram por matrícula e senha (RF07), nunca por CPF: o cpfHash é
      // só um valor único para satisfazer o NOT NULL, e não é um CPF. Os dois
      // ficam na MESMA microárea (fila por dono, envio diferido).
      for (final (acs, digest, name) in [
        (fixtures.acs, acsDigest, 'ACS E2E'),
        (fixtures.secondAcs, secondAcsDigest, 'ACS E2E B'),
      ]) {
        await tx.execute(
          Sql.named('INSERT INTO "users" ("id","cpfHash","name","birthDate","role","microAreaId","createdAt","updatedAt") '
              "VALUES (@id,@hash,@name,'1985-01-01','acs',@area,NOW(),NOW())"),
          parameters: {'id': acs.id, 'hash': 'e2e-acs-${acs.id}', 'name': name, 'area': fixtures.microAreaId},
        );
        await tx.execute(
          Sql.named('INSERT INTO "acs" ("id","enrollmentId","ubsId","active") VALUES (@id,@matricula,@ubs,true)'),
          parameters: {'id': acs.id, 'matricula': acs.matricula, 'ubs': fixtures.ubsId},
        );
        await tx.execute(
          Sql.named('INSERT INTO "user_credentials" ("userId","passwordHash","passwordSalt","memoryKb","iterations","parallelism","failedAttempts","createdAt","updatedAt") '
              'VALUES (@userId,@hash,@salt,@memoryKb,@iterations,@parallelism,0,NOW(),NOW())'),
          parameters: {
            'userId': acs.id,
            'hash': digest.hashBase64,
            'salt': digest.saltBase64,
            'memoryKb': digest.memoryKb,
            'iterations': digest.iterations,
            'parallelism': digest.parallelism,
          },
        );
      }
    });
  } finally {
    await connection.close();
  }

  final out = File(args.isNotEmpty ? args.first : '.e2e/fixtures.json');
  writeManifestPrivately(out, jsonEncode(fixtures.toJson()));
  stdout.writeln('Fixtures de e2e gravadas (${fixtures.patients.length} pacientes, 2 ACS) em ${out.path}.');
}
