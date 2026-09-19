import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Login institucional contra Postgres real: prova o JOIN
/// `acs.enrollmentId → acs.id → users.microAreaId → user_credentials` que o
/// teste unitário (com store falso) não alcança.
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';
const _matricula = 'ACS-001';
const _senha = 'senha-sintetica-de-teste';

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
      // bloqueio JÁ VENCIDO abaixo do limite. É a linha que o contrato do
      // store cobre (`registerFailedAttempt` grava o que recebe, inclusive
      // rebaixando o contador) e que o serviço não produz sozinho — só um
      // seed ou uma escrita manual como esta chegam nela.
      await AlertRuntimeHarness.store(session).registerFailedAttempt(
            _acsId,
            failedAttempts: 4,
            lockedUntil: DateTime.now().toUtc().subtract(
                  const Duration(minutes: 1),
                ),
          );

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
      final credential = await UserCredential.db.findFirstRow(
        session,
        where: (table) => table.userId.equals(UuidValue.fromString(_acsId)),
      );
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
  });
}
