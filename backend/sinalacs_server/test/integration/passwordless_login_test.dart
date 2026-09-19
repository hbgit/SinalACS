import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/passwordless_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/sms_gateway.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_otp_challenge_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Login passwordless contra Postgres real: prova o JOIN por `cpfHash` e a
/// passagem por `otp_challenges` que o teste unitário (store falso) não alcança.
///
/// O grupo "Store ORM" prende, direto no banco, cinco semânticas que a
/// interface `OtpChallengeStore` **não declara** e que o fake de
/// `passwordless_auth_service_test.dart` não consegue alcançar — um fake
/// concorda com quem o escreveu. Sem estas asserções, o defeito passa com a
/// suíte inteira verde. As quatro primeiras são as do bloco "CASO 1" do brief:
///
/// 1. `save` ignora o `id` recebido e o banco atribui o seu (o serviço manda
///    `id: ''`). No ORM isso falha ALTO (`''` não é uuid), mas o modo de falha
///    silencioso de um store que honrasse o id recebido só é observável aqui.
/// 2. `latestOpen` filtra `consumedAt IS NULL AND expiresAt > at`, do mais
///    recente: sem o primeiro filtro o código já usado volta a valer, sem o
///    segundo um desafio vencido volta a valer, e sem a ordenação o desafio
///    errado é o que casa com o código digitado.
/// 3. `registerAttempt` grava a contagem **absoluta** — o serviço manda
///    `attempts + 1` já calculado; um `UPDATE attempts = attempts + 1` no store
///    faria o teto de tentativas disparar na metade do caminho.
/// 4. `consume` não desfaz nem re-datou o consumo: o desafio continua morto.
///
/// O quinto caso (isolação por usuário) não vem da tabela do brief: o filtro
/// por `userId` é o que impede o desafio de um paciente responder pelo login de
/// outro, e sem asserção ele some sem deixar rastro nenhum na suíte.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _ubsId = '00000000-0000-4000-9000-000000000001';
const _microAreaId = '00000000-0000-4000-9000-000000000002';

/// CPF sintético e válido (dígitos verificadores corretos), usado só aqui.
/// Nunca um CPF real — regra do repositório (LGPD).
const _cpfSintetico = '12345678909';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      // Hex de 64 caracteres: HealthDataCipher decodifica byte a byte para
      // montar a chave AES-256 (ver AppConfig).
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

void main() {
  withServerpod('Dado o login passwordless do paciente (RF01)', (
    sessionBuilder,
    endpoints,
  ) {
    final cpf = Cpf.tryParse(_cpfSintetico)!;
    final nascimento = DateTime.utc(1990, 1, 1);

    // Antes de qualquer uso do `AlertRuntime`: sem a config de teste,
    // `AppConfig.fromEnvironment()` é lido do ambiente do processo.
    setUp(() => AlertRuntime.instance.overrideConfig(_config()));

    tearDown(() {
      // O gateway de teste não pode vazar para o próximo caso (o mesmo cuidado
      // do `overrideConfig`).
      AlertRuntime.instance.overrideSmsGateway(null);
      AlertRuntime.instance.overrideConfig(null);
    });

    setUp(() async {
      final session = sessionBuilder.build();

      // O harness `withServerpod` aplica as MIGRAÇÕES, nunca o
      // `development.sql`: o paciente do seed NÃO existe no banco de teste, e
      // um `findById` seguido de `user!` estoura null-check antes de qualquer
      // asserção. (Foi o defeito que quem executou a Task 4 do RF07 encontrou no
      // teste irmão de lá.) Insere o mínimo que o caminho exige — UBS, microárea
      // e o usuário paciente — com UUIDs sintéticos próprios para não colidir
      // com os de outros arquivos de integração que rodam sob o mesmo banco.
      await _seedPatient(session);

      final user = (await User.db.findById(
        session,
        UuidValue.fromString(_patientId),
      ))!;
      // O hash de CPF é o índice de busca do login e depende do pepper da
      // config, então só pode ser calculado aqui — depois do `overrideConfig`.
      user
        ..cpfHash = AlertRuntime.instance.cpfHasherForTests.hash(cpf)
        ..birthDate = nascimento;
      await User.db.updateRow(session, user);
    });

    test('o código pedido permite entrar e devolver token de paciente', () async {
      final session = sessionBuilder.build();
      final gateway = RecordingSmsGateway();
      AlertRuntime.instance.overrideSmsGateway(gateway);

      // Endpoint recebe o próprio `sessionBuilder`; `sessionBuilder.build()` é
      // para acesso direto ao banco (ver `onboarding_endpoint_test.dart`).
      await endpoints.auth.requestOtp(
        sessionBuilder,
        cpf: cpf.digits,
        birthDate: nascimento,
      );

      // O gateway de teste guarda o código que "enviaria" — é o único lugar
      // onde o código em claro existe, por desenho.
      expect(gateway.sent, hasLength(1));

      final result = await endpoints.auth.verifyOtp(
        sessionBuilder,
        cpf: cpf.digits,
        code: gateway.sent.single.code,
      );

      expect(result.accessToken, isNotEmpty);
      final sessao = AlertRuntime.instance.auth.verifyToken(result.accessToken);
      expect(sessao?.role, UserRole.patient);
      // A microárea do token é a do PACIENTE, lida do banco pelo store: é ela
      // que restringe o acesso ao território (INV-01). Um store que devolvesse
      // a microárea errada — ou nula — torna este login inútil ou o território
      // errado, e o papel sozinho não denuncia nenhum dos dois.
      expect(sessao?.microAreaId, _microAreaId);

      // Prova que o código em claro NÃO está no banco.
      final challenge = await OtpChallenge.db.findFirstRow(
        session,
        where: (table) => table.userId.equals(UuidValue.fromString(_patientId)),
        orderBy: (table) => table.createdAt,
        orderDescending: true,
      );
      expect(challenge!.codeHash.length, 64);
      expect(challenge.codeHash.contains(gateway.sent.single.code), isFalse);
      expect(challenge.consumedAt, isNotNull);
    });

    test('CPF não cadastrado não grava desafio', () async {
      final session = sessionBuilder.build();
      final outro = Cpf.tryParse('98765432100')!;

      await endpoints.auth.requestOtp(
        sessionBuilder,
        cpf: outro.digits,
        birthDate: nascimento,
      );

      final challenges = await OtpChallenge.db.find(session);
      expect(challenges, isEmpty);
    });

    test('código inválido é recusado pelo endpoint com a exceção tipada', () async {
      await expectLater(
        endpoints.auth.verifyOtp(
          sessionBuilder,
          cpf: cpf.digits,
          code: '000000',
        ),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('verifyOtp com CPF impossível é recusado com a exceção tipada', () async {
      // Mesmo CPF sintético com o dígito final trocado: a validação do
      // endpoint recusa antes de qualquer consulta, e a recusa sai tipada —
      // não como o erro cru de uma conversão que só falharia depois.
      await expectLater(
        endpoints.auth.verifyOtp(
          sessionBuilder,
          cpf: '12345678900',
          code: '000000',
        ),
        throwsA(isA<OtpRequestException>()),
      );
    });

    test('data de nascimento errada não gera desafio', () async {
      final session = sessionBuilder.build();

      await endpoints.auth.requestOtp(
        sessionBuilder,
        cpf: cpf.digits,
        birthDate: DateTime.utc(1991, 2, 2),
      );

      expect(await OtpChallenge.db.find(session), isEmpty);
    });

    test('CPF com dígito verificador errado é recusado antes de virar hash', () async {
      final session = sessionBuilder.build();

      // Mesmo CPF sintético com o último dígito trocado: 11 dígitos, DV
      // inválido. O endpoint recusa na porta, sem consultar o banco — não é
      // "CPF não encontrado", é "número impossível".
      await expectLater(
        endpoints.auth.requestOtp(
          sessionBuilder,
          cpf: '12345678900',
          birthDate: nascimento,
        ),
        throwsA(isA<OtpRequestException>()),
      );

      expect(await OtpChallenge.db.find(session), isEmpty);
    });

    // As semânticas não declaradas da interface, medidas contra o Postgres e
    // **direto no store** — pelo endpoint elas ficam escondidas atrás dos
    // filtros que o próprio serviço repete.
    group('Store ORM', () {
      test('save ignora o id recebido e o banco atribui um id próprio', () async {
        final session = sessionBuilder.build();
        final store = OrmOtpChallengeStore(session: () => session);

        // `createdAt` distintos de propósito: `latestOpen` ordena por
        // `createdAt` e um empate deixaria a ordem a cargo do Postgres.
        final t1 = DateTime.utc(2026, 1, 1, 12, 0, 0);
        final t2 = t1.add(const Duration(seconds: 30));

        await store.save(_desafio(codeHash: 'hash-a', createdAt: t1));
        final primeiro = await store.latestOpen(
          _patientId,
          t1.add(const Duration(minutes: 1)),
        );

        expect(
          primeiro,
          isNotNull,
          reason: 'o desafio gravado tem de voltar pelo latestOpen',
        );
        expect(
          primeiro!.id,
          isNotEmpty,
          reason: 'o id do desafio é atribuído pelo banco: o serviço manda '
              '`id: ""` e um store que honrasse esse valor não teria id nenhum '
              'para devolver',
        );

        await store.save(_desafio(codeHash: 'hash-b', createdAt: t2));
        final segundo = await store.latestOpen(
          _patientId,
          t2.add(const Duration(minutes: 1)),
        );

        expect(segundo, isNotNull);
        expect(segundo!.id, isNotEmpty);
        expect(
          segundo.id,
          isNot(primeiro.id),
          reason: 'cada desafio tem o seu id: dois desafios do mesmo usuário '
              'não podem colidir, senão registerAttempt e consume escrevem na '
              'linha errada',
        );
        expect(
          segundo.codeHash,
          'hash-b',
          reason: 'latestOpen devolve o MAIS RECENTE (createdAt desc)',
        );
      });

      test('latestOpen recusa desafio expirado e desafio já consumido', () async {
        final session = sessionBuilder.build();
        final store = OrmOtpChallengeStore(session: () => session);

        final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
        final validade = t0.add(const Duration(minutes: 5));
        await store.save(_desafio(createdAt: t0, expiresAt: validade));

        // Controle: dentro da validade o desafio aparece. Sem ele, os `null`
        // abaixo passariam também por "não gravou nada" — que é o motivo
        // errado, e é o que deixaria um store quebrado invisível.
        final dentro = await store.latestOpen(
          _patientId,
          t0.add(const Duration(minutes: 1)),
        );
        expect(dentro, isNotNull);

        final depois = await store.latestOpen(
          _patientId,
          t0.add(const Duration(minutes: 6)),
        );
        expect(
          depois,
          isNull,
          reason: 'desafio expirado (expiresAt <= at) não pode mais ser '
              'devolvido: aceitá-lo é conceder login com um código que já '
              'deveria ter morrido (TTL)',
        );

        final naBorda = await store.latestOpen(_patientId, validade);
        expect(
          naBorda,
          isNull,
          reason: 'a borda `expiresAt == at` já está fora: a validade é '
              '`expiresAt > at`, a mesma comparação que o serviço repete',
        );

        // Uso único: consumido, o mesmo desafio não volta — e aqui ele ainda
        // está dentro da validade, então o `null` só pode vir do `consumedAt`.
        await store.consume(dentro!.id, t0.add(const Duration(minutes: 1)));
        final consumido = await store.latestOpen(
          _patientId,
          t0.add(const Duration(minutes: 2)),
        );
        expect(
          consumido,
          isNull,
          reason: 'código de uso único: consumido não pode ser devolvido de '
              'novo enquanto não expirar',
        );
      });

      test('registerAttempt grava a contagem absoluta, não incrementa', () async {
        final session = sessionBuilder.build();
        final store = OrmOtpChallengeStore(session: () => session);

        final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
        await store.save(_desafio(createdAt: t0));
        final desafio = await store.latestOpen(
          _patientId,
          t0.add(const Duration(minutes: 1)),
        );

        await store.registerAttempt(desafio!.id, 3);
        expect(
          await _attempts(session, desafio.id),
          3,
          reason: 'o serviço manda o número já calculado (attempts + 1); gravar '
              '`attempts + 1` no SQL daria 1 aqui',
        );

        await store.registerAttempt(desafio.id, 3);
        expect(
          await _attempts(session, desafio.id),
          3,
          reason: 'gravar 3 de novo tem de continuar 3 — um incremento no '
              'store faria o teto de tentativas disparar antes do tempo',
        );
      });

      test('latestOpen não devolve desafio de OUTRO usuário', () async {
        final session = sessionBuilder.build();
        final store = OrmOtpChallengeStore(session: () => session);

        final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
        final outroId = '00000000-0000-4000-9000-000000000003';
        final agora = DateTime.now().toUtc();
        await User.db.insertRow(
          session,
          User(
            id: UuidValue.fromString(outroId),
            // Hash sintético: este usuário existe só para ter um desafio
            // aberto e é POR ele que a consulta errada responderia.
            cpfHash: 'hash-sintetico-do-outro-usuario',
            name: 'Outro Paciente Sintético RF01',
            birthDate: DateTime.utc(1985, 5, 5),
            role: UserRole.patient,
            microAreaId: UuidValue.fromString(_microAreaId),
            createdAt: agora,
            updatedAt: agora,
          ),
        );

        await store.save(_desafio(codeHash: 'hash-do-paciente', createdAt: t0));
        await store.save(
          _desafio(
            userId: outroId,
            codeHash: 'hash-do-outro',
            createdAt: t0.add(const Duration(seconds: 30)),
          ),
        );

        // O desafio do outro usuário é o MAIS RECENTE: sem o filtro por
        // `userId` é ele que a consulta devolve, e o serviço compararia o
        // código digitado com o hash de outro paciente.
        final aberto = await store.latestOpen(
          _patientId,
          t0.add(const Duration(minutes: 1)),
        );

        expect(aberto, isNotNull);
        expect(aberto!.userId, _patientId);
        expect(aberto.codeHash, 'hash-do-paciente');
      });

      test('consume não desfaz nem re-datou o consumo', () async {
        final session = sessionBuilder.build();
        final store = OrmOtpChallengeStore(session: () => session);

        final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
        final t1 = t0.add(const Duration(minutes: 1));
        final t2 = t0.add(const Duration(minutes: 2));
        await store.save(_desafio(createdAt: t0));
        final desafio = await store.latestOpen(_patientId, t1);

        await store.consume(desafio!.id, t1);
        expect(await _consumedAt(session, desafio.id), t1);

        await store.consume(desafio.id, t2);
        expect(
          await _consumedAt(session, desafio.id),
          t1,
          reason: 'o segundo consume não pode re-datar o primeiro: o instante '
              'gravado é o do consumo real, não o da última chamada',
        );
        expect(
          await store.latestOpen(_patientId, t2),
          isNull,
          reason: 'consumo não se desfaz: o desafio continua morto',
        );
      });
    });
  });
}

/// Um `OtpChallengeRecord` como o SERVIÇO o monta: `id: ''` (o id é do banco) e
/// `expiresAt` no TTL padrão quando o caso não precisa de outra validade.
OtpChallengeRecord _desafio({
  required DateTime createdAt,
  DateTime? expiresAt,
  String codeHash = 'hash-sintetico',
  int attempts = 0,
  String userId = _patientId,
}) =>
    OtpChallengeRecord(
      id: '',
      userId: userId,
      codeHash: codeHash,
      attempts: attempts,
      createdAt: createdAt,
      expiresAt: expiresAt ??
          createdAt.add(PasswordlessAuthService.codeTtl),
    );

/// Lê a linha direto do ORM: as asserções do "CASO 1" são sobre o que está
/// GRAVADO, não sobre o que o store devolve.
Future<int> _attempts(Session session, String challengeId) async =>
    (await OtpChallenge.db.findById(
      session,
      UuidValue.fromString(challengeId),
    ))!
        .attempts;

Future<DateTime?> _consumedAt(Session session, String challengeId) async =>
    (await OtpChallenge.db.findById(
      session,
      UuidValue.fromString(challengeId),
    ))!
        .consumedAt;

/// Semeia o mínimo que o login passwordless exige: UBS, microárea e o usuário
/// paciente (o `users` é quem carrega `cpfHash`/`birthDate`/`microAreaId`).
///
/// UUIDs sintéticos e **próprios deste arquivo**: vários testes de integração
/// rodam sob o mesmo banco e reusam `…0002`/`…0003`/`…0004`, o que funciona
/// porque o harness reverte cada caso (`rollbackDatabase` = `afterEach`), mas
/// usar um espaço próprio evita depender disso.
Future<void> _seedPatient(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Teste RF01',
      address: 'Endereço sintético',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea Teste RF01',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_patientId),
      // Placeholder: o `setUp` sobrescreve com o HMAC real do CPF sintético.
      cpfHash: 'a-definir-no-setup',
      name: 'Paciente Sintético RF01',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );
  await Patient.db.insertRow(
    session,
    Patient(
      id: UuidValue.fromString(_patientId),
      emergencyContact: 'Contato sintético',
      isChronic: false,
      chronicConditionsEncrypted: '',
      chronicConditionsKeyVersion: 1,
    ),
  );
}
