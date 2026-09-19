import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Login institucional contra Postgres real: prova o JOIN
/// `acs.enrollmentId → acs.id → users.microAreaId → user_credentials` que o
/// teste unitário (com store falso) não alcança — e prova, relendo a linha,
/// que a contagem de tentativas do achado F6 realmente **chega ao banco**.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _matricula = 'ACS-001';
const _senha = 'senha-sintetica-de-teste';

/// Identificadores do grupo da rajada, distintos dos fixos acima e dos das
/// outras suítes: esse grupo **commita** (roda sem rollback), então nada dele
/// pode colidir com o que outro arquivo cria.
const _raceAcsId = '00000000-0000-4000-8000-000000000071';
const _raceMicroAreaId = '00000000-0000-4000-8000-000000000072';
const _raceUbsId = '00000000-0000-4000-8000-000000000073';
const _raceMatricula = 'ACS-RAJADA-001';

/// As linhas que o login atravessa, semeadas pelo teste.
///
/// O harness do `withServerpod` aplica as MIGRAÇÕES, mas não o seed de
/// desenvolvimento (`seeds/development.sql` é aplicado pelo compose, via
/// `psql`, e não pelo processo de teste) — sem estas linhas a matrícula
/// `ACS-001` não existiria e o primeiro teste falharia por ausência de dado,
/// não por defeito do login. Mesma forma de `onboarding_endpoint_test.dart`.
Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );

  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs',
      name: 'ACS de desenvolvimento',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: _matricula,
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
}

/// A linha de `user_credentials` como ela está no banco, agora.
///
/// Toda asserção deste arquivo sobre o bloqueio passa por aqui: é o que
/// transforma "o serviço chamou o store" em "a escrita chegou ao Postgres".
/// Sem a releitura, um `registerFailedAttempt` que virasse no-op — ou que
/// perdesse a atualização sob concorrência — deixaria a suíte inteira verde,
/// porque nenhuma outra asserção olha para o contador.
Future<UserCredential?> _credential(Session session) => _credentialDe(_acsId, session);

Future<UserCredential?> _credentialDe(String acsId, Session session) =>
    UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(UuidValue.fromString(acsId)),
    );

/// Escreve um estado de partida arbitrário direto no ORM.
///
/// Depois deste fix a interface do store só sabe **contar** (somar 1 sobre a
/// linha, ou recomeçar em 1 quando o bloqueio venceu) — de propósito, porque é
/// isso que impede a atualização perdida. Um contador arbitrário, como as 4
/// tentativas semeadas aqui, é coisa que só um seed ou uma escrita manual
/// produzem; a fixture usa o ORM justamente por não existir mais operação de
/// produção que grave um valor absoluto.
Future<void> _seedFailedAttempts(
  Session session, {
  required int failedAttempts,
  DateTime? lockedUntil,
}) async {
  final row = await _credential(session);
  if (row == null) {
    throw StateError('a credencial do ACS precisa estar semeada antes');
  }
  row
    ..failedAttempts = failedAttempts
    ..lockedUntil = lockedUntil;
  await UserCredential.db.updateRow(session, row);
}

/// Semeia o território, o usuário, o ACS e a credencial do grupo da rajada.
///
/// Idempotente de propósito: se uma execução anterior morreu antes da limpeza
/// do `finally`, as linhas ainda estão lá e o `insertRow` falharia por chave
/// duplicada — a limpeza vem primeiro justamente para o teste ser repetível.
Future<void> _seedRace(Session session) async {
  await _cleanupRace(session);

  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_raceUbsId),
      name: 'UBS Rajada',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_raceMicroAreaId),
      name: 'Microárea Rajada',
      ubsId: UuidValue.fromString(_raceUbsId),
      geoJsonBoundary: '{}',
    ),
  );

  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_raceAcsId),
      cpfHash: 'development-acs-rajada',
      name: 'ACS de desenvolvimento (rajada)',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_raceMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_raceAcsId),
      enrollmentId: _raceMatricula,
      ubsId: UuidValue.fromString(_raceUbsId),
      active: true,
    ),
  );

  await AlertRuntimeHarness.store(session).saveCredential(
        _raceAcsId,
        await AlertRuntimeHarness.hasher.derive(_senha),
        now,
      );
}

/// Desfaz o que [_seedRace] e a rajada gravam. Ordem inversa às FKs: filhos
/// antes dos pais. Não toca em `audit_logs` porque este grupo não audita nada
/// (ver `_RecordingAudit`).
Future<void> _cleanupRace(Session session) async {
  await UserCredential.db.deleteWhere(
    session,
    where: (t) => t.userId.equals(UuidValue.fromString(_raceAcsId)),
  );
  await Acs.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceAcsId)),
  );
  await User.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceAcsId)),
  );
  await MicroArea.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceMicroAreaId)),
  );
  await Ubs.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_raceUbsId)),
  );
}

/// Auditoria de mentira, usada só pelo teste de concorrência (grupo sem
/// rollback).
///
/// A trilha real (`OrmAuditTrail`) gravaria linhas em `audit_logs` que, neste
/// grupo, ficam **permanentes** — e a cadeia de hash é global: as suítes que
/// rodam em paralelo pesquisam `audit_logs` sem filtro e conferem a cadeia
/// inteira (`patient_directory_and_territory_test.dart:219`,
/// `triage_session_persistence_test.dart:162`), então auditoria commitada aqui
/// quebraria asserção de outro arquivo. A propriedade sob teste é a contagem de
/// tentativas, não a auditoria: esta tem os próprios testes, e o caminho do
/// endpoint com a trilha de verdade é exercitado pelos casos do grupo
/// principal, uma requisição por vez.
class _RecordingAudit extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

void main() {
  withServerpod('Dado o login institucional do ACS (RF07)', (
    sessionBuilder,
    endpoints,
  ) {
    setUp(() async {
      final session = sessionBuilder.build();
      await _seed(session);
      // Mesma KDF de produção, com custo reduzido: o que se prova é o
      // caminho, não o custo.
      final digest = await AlertRuntimeHarness.hasher.derive(_senha);
      await AlertRuntimeHarness.store(session).saveCredential(
            _acsId,
            digest,
            DateTime.now().toUtc(),
          );
    });

    test('matrícula e senha corretas devolvem token de ACS', () async {
      final session = sessionBuilder.build();

      // Estado de partida sujo de propósito: contador acima de zero e um
      // bloqueio JÁ VENCIDO abaixo do limite. É a linha que o serviço não
      // produz sozinho — só um seed ou uma escrita manual como esta chegam
      // nela.
      final vencido = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await _seedFailedAttempts(session, failedAttempts: 4, lockedUntil: vencido);

      // A fixture só serve de prova se estiver MESMO no banco: sem esta
      // releitura, uma escrita que virasse no-op deixaria a asserção abaixo
      // ("limpou o estado sujo") passando por vacuidade — 0 e `null` já era o
      // estado de uma linha recém-criada.
      final semeada = await _credential(session);
      expect(semeada?.failedAttempts, 4);
      expect(semeada?.lockedUntil, isNotNull);

      // Endpoint recebe o próprio `sessionBuilder`; `sessionBuilder.build()` é
      // para acesso direto ao banco (ver `onboarding_endpoint_test.dart:236`).
      final result = await endpoints.auth.loginInstitutional(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
      );

      expect(result.accessToken, isNotEmpty);
      expect(result.tokenType, 'Bearer');

      final user = AlertRuntimeHarness.verify(result.accessToken);
      expect(user?.id, _acsId);
      expect(user?.role, UserRole.acs);
      // A microárea viaja do `users` semeado até o token: é esta igualdade que
      // prova a perna territorial do JOIN, e não só a existência da linha.
      expect(user?.microAreaId, _microAreaId);

      // E o login válido limpou o estado sujo: os DOIS campos, contador e
      // bloqueio. Só o store ORM e um Postgres de verdade provam esta
      // gravação — o fake do teste unitário não tem linha para reler.
      final credential = await _credential(session);
      expect(credential?.failedAttempts, 0);
      expect(credential?.lockedUntil, isNull);
    });

    test('senha errada é recusada pelo endpoint com a exceção tipada', () async {
      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('grava uma linha real em audit_logs', () async {
      final session = sessionBuilder.build();

      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );

      final rows = await AuditLog.db.find(
        session,
        where: (table) =>
            table.resourceType.equals('session') &
            table.result.equals('denied_credentials'),
      );
      expect(rows, isNotEmpty);
    });

    test('senha errada grava a tentativa na linha da credencial', () async {
      final session = sessionBuilder.build();

      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // O outro lado do teste anterior: `audit_logs` prova que o desfecho foi
      // auditado, não que a tentativa foi CONTADA. Se `registerFailedAttempt`
      // virasse no-op, a auditoria continuaria escrevendo e todo o resto da
      // suíte continuaria verde — este é o único ponto que mede a contagem.
      final credential = await _credential(session);
      expect(credential?.failedAttempts, 1);
      expect(credential?.lockedUntil, isNull);
    });

    test('a quinta falha bloqueia a conta por quinze minutos', () async {
      final session = sessionBuilder.build();
      await _seedFailedAttempts(session, failedAttempts: 4);
      final antes = DateTime.now().toUtc();

      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );

      final credential = await _credential(session);
      expect(credential?.failedAttempts, 5);
      expect(credential?.lockedUntil, isNotNull);
      // O vencimento é o do serviço (`lockDuration`), gravado pelo store: a
      // janela é medida contra o relógio real, com folga para o tempo do
      // Argon2id entre a leitura de `antes` e a UPDATE.
      final vencimento = credential!.lockedUntil!;
      expect(
        vencimento.isAfter(antes.add(const Duration(minutes: 14, seconds: 30))),
        isTrue,
        reason: 'bloqueio cedo demais: $vencimento contra $antes',
      );
      expect(
        vencimento.isBefore(antes.add(const Duration(minutes: 15, seconds: 30))),
        isTrue,
        reason: 'bloqueio tarde demais: $vencimento contra $antes',
      );
    });

    test('a falha depois do bloqueio vencido recomeça a contagem', () async {
      final session = sessionBuilder.build();
      // Bloqueio JÁ VENCIDO com o contador no limite: a linha em que o serviço
      // decide reiniciar em 1 em vez de somar. Quem APLICA a decisão é o SQL
      // (`CASE WHEN @restart THEN 1` e `lockedUntil = NULL` no reinício), então
      // só um Postgres de verdade prende a regra — o fake do teste unitário
      // espelha a mesma regra e, por construção, não acusa erro nenhum nela.
      await _seedFailedAttempts(
        session,
        failedAttempts: 5,
        lockedUntil: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );

      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );

      final credential = await _credential(session);
      // 1, e não 6: sem o reinício, `6 >= 5` trancaria a conta de novo a cada
      // tentativa e uma tentativa por janela bastaria para manter um ACS fora
      // para sempre.
      expect(credential?.failedAttempts, 1);
      // E o bloqueio vencido sai da linha: manter `lockedUntil` no passado
      // deixaria a leitura seguinte ambígua.
      expect(credential?.lockedUntil, isNull);
    });

    test('a contagem recusa a escrita enquanto o bloqueio está ativo', () async {
      final session = sessionBuilder.build();
      final ativo = DateTime.now().toUtc().add(const Duration(minutes: 5));
      await _seedFailedAttempts(session, failedAttempts: 5, lockedUntil: ativo);

      // Chamada direta ao store, com o serviço fora do caminho: com bloqueio
      // ativo o serviço recusa ANTES de contar (e é isso que o teste
      // `bloqueio ativo não conta tentativa nem com a senha errada` prende), mas
      // o serviço não é o único caminho até a `UPDATE` — duas requisições
      // concorrentes podem chegar aqui com a linha já trancada por outra. É o
      // `WHERE` da instrução que garante "não conta nem estende" nesse caso.
      await AlertRuntimeHarness.store(session).registerFailedAttempt(
        _acsId,
        restartCounter: false,
        maxFailedAttempts: InstitutionalAuthService.maxFailedAttempts,
        lockUntil: ativo.add(const Duration(minutes: 15)),
        at: DateTime.now().toUtc(),
      );

      final credential = await _credential(session);
      expect(credential?.failedAttempts, 5);
      expect(credential?.lockedUntil, ativo);
    });

    test('o bloqueio só é revelado a quem acertou a senha', () async {
      final session = sessionBuilder.build();
      final agora = DateTime.now().toUtc();
      await _seedFailedAttempts(
        session,
        failedAttempts: 5,
        lockedUntil: agora.add(const Duration(minutes: 5)),
      );

      // A mensagem genérica é MEDIDA na própria implementação, com uma
      // matrícula que não existe, e não escrita como literal: o que este teste
      // mede é a indistinguibilidade, não a redação da frase.
      Future<Object?> tentar({
        required String matricula,
        required String password,
      }) =>
          endpoints.auth
              .loginInstitutional(
                sessionBuilder,
                matricula: matricula,
                password: password,
              )
              .then<Object?>((_) => null, onError: (Object error) => error);

      final inexistente = await tentar(matricula: 'ACS-999', password: _senha);
      final bloqueadaComSenhaErrada =
          await tentar(matricula: _matricula, password: 'outra');

      // Com a senha errada, a conta bloqueada responde IGUAL a uma matrícula
      // inexistente: é o que impede cinco chutes anônimos por candidata de
      // enumerarem quem existe.
      expect(inexistente, isA<AuthenticationFailedException>());
      expect(bloqueadaComSenhaErrada, isA<AuthenticationFailedException>());
      expect(
        (bloqueadaComSenhaErrada as AuthenticationFailedException).message,
        (inexistente as AuthenticationFailedException).message,
      );

      // Com a senha certa, o bloqueio é dito — e a tentativa recusada por
      // bloqueio não move o contador.
      final bloqueadaComSenhaCerta =
          await tentar(matricula: _matricula, password: _senha);
      expect(
        bloqueadaComSenhaCerta,
        isA<AuthenticationFailedException>().having(
          (error) => error.message,
          'message',
          contains('bloqueado'),
        ),
      );

      final credential = await _credential(session);
      expect(credential?.failedAttempts, 5);
    });
  });

  // Grupo separado, com rollback desligado, só para a corrida. Mesmo motivo
  // (e mesmo formato) do grupo de corrida de `onboarding_endpoint_test.dart`:
  // com o rollback ligado, cada `Session` do harness tem o seu próprio
  // `TestDatabaseProxy`, mas TODAS compartilham o mesmo `TransactionManager` —
  // duas operações de banco concorrentes colidem no savepoint compartilhado e o
  // harness recusa com `InvalidConfigurationException` ("Concurrent database
  // calls outside an already active transaction are not supported..."). Só com
  // o rollback desligado cada tentativa abre a sua conexão de verdade, que é a
  // condição em que o controle do achado F6 precisa valer.
  //
  // O caminho exercitado é o do SERVIÇO com o store ORM real, contra Postgres
  // real — e não o endpoint — por causa da auditoria: `loginInstitutional`
  // audita todo desfecho, e `OrmAuditTrail.record` grava linhas de `audit_logs`
  // que, sem rollback, ficariam permanentes. As suítes que rodam em paralelo
  // fazem `AuditLog.db.find(session)` sem filtro e conferem a cadeia
  // (`patient_directory_and_territory_test.dart:219`,
  // `triage_session_persistence_test.dart:162`), então commitar auditoria aqui
  // as quebraria. Com uma trilha de mentira nada é auditado e o que sobra no
  // banco são as quatro linhas deste grupo — que a limpeza do `finally`
  // remove, e que o seed idempotente recria se uma execução anterior morrer no
  // meio.
  withServerpod(
    'Dado o login institucional do ACS (RF07), sem rollback automático (rajada)',
    (sessionBuilder, endpoints) {
      test('rajada de tentativas erradas conta cada uma e tranca a conta',
          () async {
        final session = sessionBuilder.build();
        await _seedRace(session);

        try {
          // Exatamente tantas tentativas quantas o limite exige, todas
          // disparadas juntas. Com a contagem feita em Dart a partir de um
          // valor lido antes, todas leem 0 e todas gravam 1: o contador fecha
          // em 1, o bloqueio nunca aparece e o controle do achado F6 não
          // existe sob rajada. Com a soma dentro da UPDATE, cada tentativa
          // enxerga o resultado da anterior.
          final concorrentes = InstitutionalAuthService.maxFailedAttempts;
          final resultados = await Future.wait([
            for (var i = 0; i < concorrentes; i++)
              _tentativaErrada(sessionBuilder),
          ]);

          expect(
            resultados,
            everyElement(isA<AuthenticationFailedException>()),
            reason: 'nenhuma tentativa com senha errada pode passar',
          );

          final credential = await _credentialDe(_raceAcsId, session);
          expect(
            credential?.failedAttempts,
            concorrentes,
            reason: 'cada tentativa concorrente precisa contar',
          );
          expect(
            credential?.lockedUntil,
            isNotNull,
            reason: 'a rajada que cruza o limite precisa trancar a conta',
          );

          // E o bloqueio vale de verdade: a partir daqui nem a senha certa
          // entra, e a mensagem é a que só é dita a quem acertou a senha.
          final bloqueado = await _tentativa(
            sessionBuilder,
            matricula: _raceMatricula,
            password: _senha,
          );
          expect(
            bloqueado,
            isA<AuthenticationFailedException>().having(
              (error) => error.message,
              'message',
              contains('bloqueado'),
            ),
          );
        } finally {
          // Sem rollback automático neste grupo: a limpeza é manual e roda
          // mesmo se uma asserção falhar, para o teste ficar repetível.
          await _cleanupRace(sessionBuilder.build());
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}

/// Uma tentativa de login pelo serviço, com o store ORM real, devolvendo o erro
/// em vez de lançar — as chamadas concorrentes precisam chegar todas ao fim.
Future<Object?> _tentativaErrada(TestSessionBuilder sessionBuilder) =>
    _tentativa(sessionBuilder, matricula: _raceMatricula, password: 'outra');

Future<Object?> _tentativa(
  TestSessionBuilder sessionBuilder, {
  required String matricula,
  required String password,
}) {
  // Uma `Session` por tentativa, como no servidor de verdade: cada requisição
  // monta a sua, e é isso que dá conexões independentes ao `Future.wait`.
  final service = InstitutionalAuthService(
    store: AlertRuntimeHarness.store(sessionBuilder.build()),
    hasher: AlertRuntimeHarness.hasher,
    audit: _RecordingAudit(),
  );

  return service
      .login(matricula: matricula, password: password)
      .then<Object?>((_) => null, onError: (Object error) => error);
}
