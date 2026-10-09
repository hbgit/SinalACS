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
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';

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
  final staffDigest = await const Argon2PasswordHasher().derive(fixtures.staff.password);
  final coordinatorDigest = await const Argon2PasswordHasher().derive(fixtures.coordinator.password);
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
      // Administrador do backoffice (RF07 para o staff): `users` com papel `admin`,
      // `staff_accounts` e credencial Argon2id, SEM TOTP (a MFA é ativada pela
      // tela do app admin). Fora de qualquer microárea.
      final staff = fixtures.staff;
      await tx.execute(
        Sql.named('INSERT INTO "users" ("id","cpfHash","name","birthDate","role","microAreaId","createdAt","updatedAt") '
            "VALUES (@id,@hash,'Admin E2E','1985-01-01','admin',NULL,NOW(),NOW())"),
        parameters: {'id': staff.id, 'hash': 'e2e-staff-${staff.id}'},
      );
      await tx.execute(
        Sql.named('INSERT INTO "staff_accounts" ("id","enrollmentId","active") VALUES (@id,@matricula,true)'),
        parameters: {'id': staff.id, 'matricula': staff.matricula},
      );
      // Painel do admin (#40): 3 alertas determinísticos na microárea das fixtures,
      // para o e2e provar contagens e TMRAV reais. O reconhecimento vem 60 s depois
      // do disparo, então o TMRAV esperado é exatamente 60 s.
      //
      // OPT-IN (`E2E_SEED_ADMIN_ALERTS=1`, ligado só por `admin_login_e2e.sh`): o
      // seed é compartilhado e estes alertas são do paciente `main`, então semeá-los
      // sempre alteraria o histórico que as jornadas do paciente e do ACS conferem.
      if (env['E2E_SEED_ADMIN_ALERTS'] == '1') {
      final paciente = fixtures.byRole('main');
      Future<void> alerta(String id, String risco, String status, {int? reconhecidoEmSegundos}) => tx.execute(
            Sql.named('INSERT INTO "alerts" ("id","patientId","acsId","microAreaId","triggeredAt","acknowledgedAt",'
                '"riskLevel","locationHash","status","mqttTopic","deviceId","retryCount","version") '
                "VALUES (@id,@patient,@acs,@ma,NOW() - interval '1 hour',"
                "CASE WHEN @ack::int IS NULL THEN NULL ELSE NOW() - interval '1 hour' + (@ack::int * interval '1 second') END,"
                "@risco,'hash-e2e',@status,@topic,'device-e2e',0,0)"),
            parameters: {
              'id': id,
              'patient': paciente.id,
              'acs': fixtures.acs.id,
              'ma': fixtures.microAreaId,
              'ack': reconhecidoEmSegundos,
              'risco': risco,
              'status': status,
              'topic': 'sinalacs/v1/microareas/${fixtures.microAreaId}/alerts',
            },
          );
      await alerta(fixtures.adminAlertIds[0], 'red', 'pending');
      await alerta(fixtures.adminAlertIds[1], 'red', 'acknowledged', reconhecidoEmSegundos: 60);
      await alerta(fixtures.adminAlertIds[2], 'green', 'pending');
      }
      // Pedidos do titular (#42), OPT-IN (`E2E_SEED_DATA_REQUESTS=1`, só por
      // `admin_titular_e2e.sh`): uma correção JÁ VENCIDA (paciente `main`) e uma
      // exclusão no prazo (paciente `chronic`, com um token de push para provar a
      // limpeza). Os textos são sintéticos e o e2e procura por eles no log.
      if (env['E2E_SEED_DATA_REQUESTS'] == '1') {
        Future<void> pedido(String userId, String tipo, String texto, {required int criadoHaDias, required int prazoEmDias}) async {
          final cifrado = await cipher.encryptJson(texto);
          await tx.execute(
            Sql.named('INSERT INTO "data_subject_requests" ("userId","requestType","detailsEncrypted","detailsKeyVersion",'
                '"status","createdAt","dueAt") VALUES (@u,@t,@c,@v,\'open\','
                "NOW() - (@criado::int * interval '1 day'), NOW() + (@prazo::int * interval '1 day'))"),
            parameters: {'u': userId, 't': tipo, 'c': cifrado.ciphertextBase64, 'v': cifrado.keyVersion, 'criado': criadoHaDias, 'prazo': prazoEmDias},
          );
        }
        await pedido(fixtures.byRole('main').id, 'correction', 'E2E-CORRECAO telefone de contato desatualizado',
            criadoHaDias: 20, prazoEmDias: -5);
        await pedido(fixtures.byRole('chronic').id, 'deletion', 'E2E-EXCLUSAO pedido do titular',
            criadoHaDias: 1, prazoEmDias: 14);
        await tx.execute(
          Sql.named('INSERT INTO "push_tokens" ("userId","token","platform","createdAt","updatedAt") '
              "VALUES (@u,@tok,'android',NOW(),NOW())"),
          parameters: {'u': fixtures.byRole('chronic').id, 'tok': 'e2e-push-${fixtures.byRole('chronic').id}'},
        );
      }
      // Código de ativação (#48): só o hash vai ao banco; o claro segue no manifesto.
      await tx.execute(
        Sql.named('UPDATE "staff_accounts" SET "activationCodeHash"=@h, "activationCodeExpiresAt"=@e, '
            '"activationCodeIssuedBy"=\'e2e\', "activationCodeIssuedAt"=NOW() WHERE "id"=@id'),
        parameters: {
          'id': staff.id,
          'h': StaffActivationCode.hash(staff.activationCode),
          'e': DateTime.now().toUtc().add(StaffActivationCode.defaultValidity),
        },
      );
      await tx.execute(
        Sql.named('INSERT INTO "user_credentials" ("userId","passwordHash","passwordSalt","memoryKb","iterations","parallelism","failedAttempts","createdAt","updatedAt") '
            'VALUES (@userId,@hash,@salt,@memoryKb,@iterations,@parallelism,0,NOW(),NOW())'),
        parameters: {
          'userId': staff.id,
          'hash': staffDigest.hashBase64,
          'salt': staffDigest.saltBase64,
          'memoryKb': staffDigest.memoryKb,
          'iterations': staffDigest.iterations,
          'parallelism': staffDigest.parallelism,
        },
      );
      // Coordenador do backoffice (issue #43): o MESMO arranjo do administrador
      // — `users` + `staff_accounts` + código de ativação + credencial Argon2id,
      // sem TOTP —, com duas diferenças: o papel é `coordinator` e o
      // `staff_accounts."ubsId"` está preenchido com a UBS destas fixtures. É o
      // que dá escopo ao papel no e2e: o coordenador vê os ACS da UBS (as duas
      // microáreas são dela) e não vê a equipe do backoffice.
      final coordinator = fixtures.coordinator;
      await tx.execute(
        Sql.named('INSERT INTO "users" ("id","cpfHash","name","birthDate","role","microAreaId","createdAt","updatedAt") '
            "VALUES (@id,@hash,'Coordenador E2E','1985-01-01','coordinator',NULL,NOW(),NOW())"),
        parameters: {'id': coordinator.id, 'hash': 'e2e-coordinator-${coordinator.id}'},
      );
      await tx.execute(
        Sql.named('INSERT INTO "staff_accounts" ("id","enrollmentId","active","ubsId") VALUES (@id,@matricula,true,@ubs)'),
        parameters: {'id': coordinator.id, 'matricula': coordinator.matricula, 'ubs': fixtures.ubsId},
      );
      await tx.execute(
        Sql.named('UPDATE "staff_accounts" SET "activationCodeHash"=@h, "activationCodeExpiresAt"=@e, '
            '"activationCodeIssuedBy"=\'e2e\', "activationCodeIssuedAt"=NOW() WHERE "id"=@id'),
        parameters: {
          'id': coordinator.id,
          'h': StaffActivationCode.hash(coordinator.activationCode),
          'e': DateTime.now().toUtc().add(StaffActivationCode.defaultValidity),
        },
      );
      await tx.execute(
        Sql.named('INSERT INTO "user_credentials" ("userId","passwordHash","passwordSalt","memoryKb","iterations","parallelism","failedAttempts","createdAt","updatedAt") '
            'VALUES (@userId,@hash,@salt,@memoryKb,@iterations,@parallelism,0,NOW(),NOW())'),
        parameters: {
          'userId': coordinator.id,
          'hash': coordinatorDigest.hashBase64,
          'salt': coordinatorDigest.saltBase64,
          'memoryKb': coordinatorDigest.memoryKb,
          'iterations': coordinatorDigest.iterations,
          'parallelism': coordinatorDigest.parallelism,
        },
      );
    });
  } finally {
    await connection.close();
  }

  final out = File(args.isNotEmpty ? args.first : '.e2e/fixtures.json');
  writeManifestPrivately(out, jsonEncode(fixtures.toJson()));
  stdout.writeln('Fixtures de e2e gravadas (${fixtures.patients.length} pacientes, 2 ACS, 1 admin, 1 coordenador) '
      'em ${out.path}.');
}
