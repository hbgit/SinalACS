import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `admin.acs`, `admin.staff`, `admin.createAcs` e `admin.setAcsMicroArea`
/// (#43) pelo endpoint, com tokens reais e Postgres real: papel, escopo por
/// UBS, auditoria de cada leitura e minimização de PII. Dados sintéticos; ids
/// próprios.
const _ubsA = '00000000-0000-4000-8000-0000000000b1';
const _ubsB = '00000000-0000-4000-8000-0000000000b2';
const _maA = '00000000-0000-4000-8000-0000000000b3';
const _maB = '00000000-0000-4000-8000-0000000000b4';
const _acsA = '00000000-0000-4000-8000-0000000000b5';
const _acsB = '00000000-0000-4000-8000-0000000000b6';
const _admin = '00000000-0000-4000-8000-0000000000b7';
const _coordA = '00000000-0000-4000-8000-0000000000b8';
const _coordSemUbs = '00000000-0000-4000-8000-0000000000b9';
const _paciente = '00000000-0000-4000-8000-0000000000ba';

/// Segunda microárea da UBS A: sem ela não há para onde mover um ACS sem
/// trocá-lo de UBS.
const _maA2 = '00000000-0000-4000-8000-0000000000bb';

final _t = DateTime.utc(2026, 10, 8, 12);

Future<void> _usuario(
  Session s,
  String id,
  String nome,
  UserRole role, {
  String? ma,
}) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'admin-ep-acc-$id',
        name: nome,
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

/// Credencial de login; só a do ACS da UBS A tem MFA ativa.
Future<void> _credencial(Session s, String userId, {bool mfaAtiva = false}) =>
    UserCredential.db
        .insertRow(
          s,
          UserCredential(
            userId: UuidValue.fromString(userId),
            passwordHash: 'hash-sintetico',
            passwordSalt: 'salt-sintetico',
            memoryKb: 65536,
            iterations: 3,
            parallelism: 1,
            failedAttempts: 0,
            createdAt: _t,
            updatedAt: _t,
            totpSecretEncrypted: mfaAtiva ? 'segredo-sintetico' : null,
            totpKeyVersion: mfaAtiva ? 1 : null,
            totpEnabledAt: mfaAtiva ? _t : null,
          ),
        )
        .then((_) {});

Future<void> _seed(Session s) async {
  for (final (id, nome) in [(_ubsA, 'UBS A'), (_ubsB, 'UBS B')]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(id),
        name: nome,
        address: 'Endereço sintético',
        city: 'São Paulo',
        state: 'SP',
      ),
    );
  }
  for (final (id, nome, ubs) in [
    (_maA, 'Microárea A', _ubsA),
    (_maA2, 'Microárea A2', _ubsA),
    (_maB, 'Microárea B', _ubsB),
  ]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: nome,
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }

  await _usuario(s, _acsA, 'Ana ACS Sintética', UserRole.acs, ma: _maA);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acsA),
      enrollmentId: 'ACS-EP-ACC-1',
      ubsId: UuidValue.fromString(_ubsA),
      active: true,
    ),
  );
  await _credencial(s, _acsA, mfaAtiva: true);

  await _usuario(s, _acsB, 'Bruno ACS Sintético', UserRole.acs, ma: _maB);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acsB),
      enrollmentId: 'ACS-EP-ACC-2',
      ubsId: UuidValue.fromString(_ubsB),
      active: true,
    ),
  );

  await _usuario(s, _admin, 'Admin Sintético', UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_admin),
      enrollmentId: 'ADM-EP-ACC-1',
      active: true,
    ),
  );

  await _usuario(s, _coordA, 'Coord A Sintético', UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordA),
      enrollmentId: 'COO-EP-ACC-1',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );

  await _usuario(s, _coordSemUbs, 'Coord Sem UBS', UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordSemUbs),
      enrollmentId: 'COO-EP-ACC-2',
      active: true,
    ),
  );

  await _usuario(s, _paciente, 'Paciente Sintético', UserRole.patient, ma: _maA);
}

String _token(String id, UserRole role, {String? ma, DateTime? now}) =>
    AlertRuntime.instance.auth.issueToken(
      AuthenticatedUser(
        id: id,
        role: role,
        microAreaId: ma,
        deviceId: 'sem-aparelho',
      ),
      now: now,
    );

/// Auditoria de mentira para o login de conferência: o que se prova é que a
/// senha devolvida uma vez abre o RF07, não a trilha do login (que tem os
/// próprios testes).
class _Audit extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

Future<int> _auditorias(Session s, String recurso, String resultado) async {
  final linhas = await s.db.unsafeQuery(
    'SELECT count(*) FROM audit_logs WHERE "resourceType" = @t AND result = @r',
    parameters: QueryParameters.named({'t': recurso, 'r': resultado}),
  );
  return linhas.single[0] as int;
}

void main() {
  withServerpod('Dado o endpoint de contas do backoffice (#43)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
    });

    test(
      'admin lê as duas listagens e cada leitura vira read/success em audit_logs',
      () async {
        final t = _token(_admin, UserRole.admin);
        final acs = await endpoints.admin.acs(sessionBuilder, accessToken: t);
        expect(acs.map((a) => a.name), [
          'Ana ACS Sintética',
          'Bruno ACS Sintético',
        ]);
        expect(acs.first.mfaActive, isTrue);
        expect(acs.first.ubsName, 'UBS A');
        expect(acs.first.microAreaName, 'Microárea A');
        expect(acs.last.mfaActive, isFalse);

        final equipe = await endpoints.admin.staff(
          sessionBuilder,
          accessToken: t,
        );
        expect(equipe.map((s) => s.enrollmentId), [
          'ADM-EP-ACC-1',
          'COO-EP-ACC-1',
          'COO-EP-ACC-2',
        ]);
        expect(await _auditorias(session, 'admin_acs', 'success'), 1);
        expect(await _auditorias(session, 'admin_staff', 'success'), 1);
      },
    );

    test('coordenador vê só os ACS da própria UBS e não lê a equipe', () async {
      final t = _token(_coordA, UserRole.coordinator);
      final acs = await endpoints.admin.acs(sessionBuilder, accessToken: t);
      expect(acs.map((a) => a.name), ['Ana ACS Sintética']);
      expect(acs.map((a) => a.ubsId).toSet(), {_ubsA});

      await expectLater(
        endpoints.admin.staff(sessionBuilder, accessToken: t),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await _auditorias(session, 'admin_acs', 'success'), 1);
      expect(await _auditorias(session, 'admin_staff', 'denied'), 1);
    });

    test(
      'acs e patient com token válido recebem AlertPermissionException nas duas e a recusa é auditada',
      () async {
        for (final (id, role, ma) in [
          (_acsA, UserRole.acs, _maA),
          (_paciente, UserRole.patient, _maA),
        ]) {
          final t = _token(id, role, ma: ma);
          await expectLater(
            endpoints.admin.acs(sessionBuilder, accessToken: t),
            throwsA(isA<AlertPermissionException>()),
          );
          await expectLater(
            endpoints.admin.staff(sessionBuilder, accessToken: t),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        expect(await _auditorias(session, 'admin_acs', 'denied'), 2);
        expect(await _auditorias(session, 'admin_staff', 'denied'), 2);
        expect(await _auditorias(session, 'admin_acs', 'success'), 0);
      },
    );

    test('coordenador sem UBS é recusado nas duas listagens', () async {
      final t = _token(_coordSemUbs, UserRole.coordinator);
      await expectLater(
        endpoints.admin.acs(sessionBuilder, accessToken: t),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        endpoints.admin.staff(sessionBuilder, accessToken: t),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(await _auditorias(session, 'admin_acs', 'denied'), 1);
      expect(await _auditorias(session, 'admin_staff', 'denied'), 1);
    });

    test('token adulterado e token expirado são recusados e não auditam leitura', () async {
      final bom = _token(_admin, UserRole.admin);
      final expirado = _token(_admin, UserRole.admin, now: DateTime.utc(2020));
      for (final t in ['${bom}x', expirado, '', 'lixo']) {
        await expectLater(
          endpoints.admin.acs(sessionBuilder, accessToken: t),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(await _auditorias(session, 'admin_acs', 'success'), 0);
      expect(await _auditorias(session, 'admin_acs', 'denied'), 0);
    });

    test(
      'admin cadastra um ACS: a senha volta uma vez, abre o login e a trilha registra created',
      () async {
        final t = _token(_admin, UserRole.admin);
        final r = await endpoints.admin.createAcs(
          sessionBuilder,
          accessToken: t,
          name: 'Nova ACS Sintética',
          enrollmentId: 'ACS-EP-ACC-9',
          microAreaId: _maA,
        );

        expect(r.acs.enrollmentId, 'ACS-EP-ACC-9');
        expect(r.acs.ubsId, _ubsA, reason: 'a UBS vem da microárea');
        expect(r.acs.microAreaId, _maA);
        expect(r.acs.active, isTrue);
        expect(r.initialPassword, isNotEmpty);

        // O ACS novo aparece na listagem de quem o cadastrou.
        final lista = await endpoints.admin.acs(sessionBuilder, accessToken: t);
        expect(lista.map((a) => a.enrollmentId), contains('ACS-EP-ACC-9'));
        expect(
          jsonEncode(lista.map((a) => a.toJson()).toList()),
          isNot(contains(r.initialPassword)),
          reason: 'a senha não volta em nenhuma listagem',
        );

        // A senha devolvida uma única vez é a que abre o login institucional.
        final login = await InstitutionalAuthService(
          store: AlertRuntimeHarness.store(sessionBuilder.build()),
          hasher: AlertRuntimeHarness.hasher,
          audit: _Audit(),
        ).login(matricula: 'ACS-EP-ACC-9', password: r.initialPassword);
        expect(login.role, UserRole.acs);
        expect(login.microAreaId, _maA);

        expect(await _auditorias(session, 'admin_acs', 'created'), 1);
        expect(await _auditorias(session, 'admin_acs', 'denied'), 0);
      },
    );

    test('coordenador cadastra na própria UBS e não na de outra', () async {
      final t = _token(_coordA, UserRole.coordinator);
      final r = await endpoints.admin.createAcs(
        sessionBuilder,
        accessToken: t,
        name: 'Nova ACS da UBS A',
        enrollmentId: 'ACS-EP-ACC-8',
        microAreaId: _maA,
      );
      expect(r.acs.ubsId, _ubsA);

      // Microárea de outra UBS: a mesma resposta de "não existe".
      await expectLater(
        endpoints.admin.createAcs(
          sessionBuilder,
          accessToken: t,
          name: 'Nova ACS da UBS B',
          enrollmentId: 'ACS-EP-ACC-7',
          microAreaId: _maB,
        ),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            'Microárea não encontrada.',
          ),
        ),
      );
      expect(await _auditorias(session, 'admin_acs', 'created'), 1);
      expect(await _auditorias(session, 'admin_acs', 'denied'), 1);
    });

    test('acs e patient não cadastram: a recusa é auditada como escrita', () async {
      for (final (id, role, ma) in [
        (_acsA, UserRole.acs, _maA),
        (_paciente, UserRole.patient, _maA),
      ]) {
        final t = _token(id, role, ma: ma);
        await expectLater(
          endpoints.admin.createAcs(
            sessionBuilder,
            accessToken: t,
            name: 'Nova ACS Sintética',
            enrollmentId: 'ACS-EP-ACC-9',
            microAreaId: _maA,
          ),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(await _auditorias(session, 'admin_acs', 'denied'), 2);
      expect(
        await User.db.findFirstRow(
          session,
          where: (u) => u.name.equals('Nova ACS Sintética'),
        ),
        isNull,
      );
    });

    test('a listagem não devolve CPF, hash de CPF nem senha', () async {
      final t = _token(_admin, UserRole.admin);
      final json = jsonEncode(
        (await endpoints.admin.acs(sessionBuilder, accessToken: t))
            .map((a) => a.toJson())
            .toList(),
      );
      expect(json, contains('Ana ACS Sintética'));
      expect(json, contains('ACS-EP-ACC-1'));
      expect(json, isNot(contains('cpf')));
      expect(json, isNot(contains('admin-ep-acc-$_acsA')));
      expect(json, isNot(contains('Hash')));
    });

    test(
      'coordenador vincula um ACS da própria UBS a outra microárea dela e a trilha registra micro_area_changed',
      () async {
        final t = _token(_coordA, UserRole.coordinator);
        final r = await endpoints.admin.setAcsMicroArea(
          sessionBuilder,
          accessToken: t,
          acsId: _acsA,
          microAreaId: _maA2,
        );

        expect(r.id, _acsA);
        expect(r.microAreaId, _maA2);
        expect(r.microAreaName, 'Microárea A2');
        expect(r.ubsId, _ubsA, reason: 'a UBS vem da microárea-alvo');

        // A listagem do coordenador já reflete o vínculo novo.
        final lista = await endpoints.admin.acs(sessionBuilder, accessToken: t);
        expect(
          lista.singleWhere((a) => a.id == _acsA).microAreaName,
          'Microárea A2',
        );

        expect(await _auditorias(session, 'admin_acs', 'micro_area_changed'), 1);
        expect(await _auditorias(session, 'admin_acs', 'denied'), 0);
      },
    );

    test(
      'microárea de outra UBS e ACS de outra UBS: a mesma recusa de "não encontrado", auditada denied',
      () async {
        final t = _token(_coordA, UserRole.coordinator);
        await expectLater(
          endpoints.admin.setAcsMicroArea(
            sessionBuilder,
            accessToken: t,
            acsId: _acsA,
            microAreaId: _maB,
          ),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Microárea não encontrada.',
            ),
          ),
        );
        await expectLater(
          endpoints.admin.setAcsMicroArea(
            sessionBuilder,
            accessToken: t,
            acsId: _acsB,
            microAreaId: _maA,
          ),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'ACS não encontrado.',
            ),
          ),
        );

        expect(await _auditorias(session, 'admin_acs', 'denied'), 2);
        expect(await _auditorias(session, 'admin_acs', 'micro_area_changed'), 0);
        expect(
          (await User.db.findById(session, UuidValue.fromString(_acsB)))!.microAreaId,
          UuidValue.fromString(_maB),
          reason: 'nada mudou para o ACS de fora do escopo',
        );
      },
    );

    test(
      'o vínculo novo vale no próximo refresh: o JWT renovado carrega a microárea nova',
      () async {
        // 1. Cadastro pela UBS A: o ACS nasce vinculado à Microárea A, e a senha
        //    mostrada uma única vez é a que abre o login (RF07).
        final t = _token(_admin, UserRole.admin);
        final r = await endpoints.admin.createAcs(
          sessionBuilder,
          accessToken: t,
          name: 'Nova ACS Vínculo',
          enrollmentId: 'ACS-EP-VINC-1',
          microAreaId: _maA,
        );
        const aparelho = 'aparelho-vinculo-1';
        final login = await InstitutionalAuthService(
          store: AlertRuntimeHarness.store(sessionBuilder.build()),
          hasher: AlertRuntimeHarness.hasher,
          audit: _Audit(),
        ).login(
          matricula: 'ACS-EP-VINC-1',
          password: r.initialPassword,
          deviceId: aparelho,
        );
        expect(login.microAreaId, _maA);

        // O JWT emitido no login carrega a microárea antiga — é ele que o app
        // usa até o próximo refresh.
        final antes = AlertRuntimeHarness.verify(
          AlertRuntime.instance.auth.issueToken(login),
        )!;
        expect(antes.microAreaId, _maA);

        // 2. O refresh token daquele aparelho (o mesmo `deviceId` do login),
        //    emitido como `auth.loginInstitutional` o emite.
        final refreshToken = await RefreshTokenService(
          store: OrmRefreshTokenStore(session: () => session),
          audit: _Audit(),
        ).issue(login);

        // 3. O coordenador da UBS A move o ACS para a outra microárea da UBS.
        await endpoints.admin.setAcsMicroArea(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          acsId: r.acs.id,
          microAreaId: _maA2,
        );

        // 4. A renovação relê `users.microAreaId` do banco a cada rotação: o
        //    JWT novo já vale no território novo, sem novo login (INV-01).
        final renovada = await endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: refreshToken,
          deviceId: aparelho,
        );
        final depois = AlertRuntimeHarness.verify(renovada.accessToken)!;
        expect(depois.id, r.acs.id);
        expect(
          depois.microAreaId,
          _maA2,
          reason: 'a microárea do JWT renovado é a relida do banco, não a do token antigo',
        );
        expect(
          renovada.refreshToken,
          isNot(refreshToken),
          reason: 'a rotação devolve um filho novo',
        );
      },
    );
  });
}
