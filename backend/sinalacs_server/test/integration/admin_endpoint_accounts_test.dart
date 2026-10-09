import 'dart:convert';
import 'dart:typed_data';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_cipher_totp_vault.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `admin.acs`, `admin.staff`, `admin.createAcs`, `admin.setAcsMicroArea`,
/// `admin.setAcsActive`, `admin.resetAcsPassword` e `admin.resetAcsMfa` (#43)
/// pelo endpoint, com tokens reais e Postgres real: papel, escopo por UBS,
/// auditoria de cada leitura e minimização de PII. Dados sintéticos; ids
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

/// ACS da prova de desativação, criado dentro do próprio caso: a fixture
/// compartilhada não tem senha (nenhum outro caso loga por ela).
const _acsDesat = '00000000-0000-4000-8000-0000000000bc';
const _matriculaDesat = 'ACS-EP-DESAT-1';
const _senha = 'senha-sintetica-de-teste';

/// ACS da prova de redefinição de senha, criado dentro do próprio caso: é ele
/// que nasce bloqueado e tem a credencial substituída.
const _acsSenha = '00000000-0000-4000-8000-0000000000be';
const _matriculaSenha = 'ACS-EP-SENHA-1';

/// ACS da prova de redefinição de MFA, criado dentro do próprio caso: a MFA
/// dele é ativada pelo fluxo de verdade (segredo cifrado pelo cofre), e não
/// pelas colunas sintéticas da fixture compartilhada.
const _acsMfa = '00000000-0000-4000-8000-0000000000bf';
const _matriculaMfa = 'ACS-EP-MFA-1';

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
///
/// Com [digest], a senha é de verdade (Argon2id do custo reduzido do harness) e
/// abre o `auth.loginInstitutional` do endpoint; sem ele, o hash é o sintético
/// de sempre — nenhum caso desta suite loga por ele.
Future<void> _credencial(
  Session s,
  String userId, {
  bool mfaAtiva = false,
  PasswordDigest? digest,
}) =>
    UserCredential.db
        .insertRow(
          s,
          UserCredential(
            userId: UuidValue.fromString(userId),
            passwordHash: digest?.hashBase64 ?? 'hash-sintetico',
            passwordSalt: digest?.saltBase64 ?? 'salt-sintetico',
            memoryKb: digest?.memoryKb ?? 65536,
            iterations: digest?.iterations ?? 3,
            parallelism: digest?.parallelism ?? 1,
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

/// Linhas do usuário numa das tabelas de token — no total, ou só as vigentes
/// (`revokedAt IS NULL`). É a única leitura possível: nenhum endpoint devolve
/// estas tabelas, e é por SQL que a prova da desativação se faz.
Future<int> _tokens(
  Session s,
  String tabela,
  String userId, {
  bool soVigentes = false,
}) async {
  final filtro = soVigentes ? ' AND "revokedAt" IS NULL' : '';
  final linhas = await s.db.unsafeQuery(
    'SELECT count(*) FROM $tabela WHERE "userId" = @id::uuid$filtro',
    parameters: QueryParameters.named({'id': userId}),
  );
  return linhas.single[0] as int;
}

/// Base32 (RFC 4648, sem preenchimento) → bytes: o que o aplicativo
/// autenticador faz com o segredo devolvido por `beginTotpEnrollment`.
Uint8List _deBase32(String texto) {
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0;
  var valor = 0;
  final saida = <int>[];
  for (final c in texto.split('')) {
    valor = (valor << 5) | alfabeto.indexOf(c);
    bits += 5;
    if (bits >= 8) {
      saida.add((valor >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(saida);
}

/// Login do ACS com a MFA **obrigatória** ligada e o cofre de verdade: o
/// endpoint usa `config.requireAcsMfa`, que é falso no ambiente de teste, e é
/// com a exigência ligada que "a próxima entrada pede ativação de novo" vira
/// uma recusa observável.
InstitutionalAuthService _servicoDeLogin(Session session) {
  final store = OrmAcsCredentialStore(session: () => session);
  return InstitutionalAuthService(
    store: store,
    hasher: AlertRuntimeHarness.hasher,
    audit: _Audit(),
    totpStore: store,
    vault: HealthCipherTotpVault(AlertRuntime.instance.healthDataCipher),
    requireMfa: true,
  );
}

/// A linha de `user_credentials` do usuário, para as provas por SQL/ORM do
/// estado de bloqueio e das colunas `totp*`.
Future<UserCredential> _credencialDo(Session s, String userId) async =>
    (await UserCredential.db.findFirstRow(
      s,
      where: (t) => t.userId.equals(UuidValue.fromString(userId)),
    ))!;

/// Uma visita sintética bem formada do paciente da Microárea A. O lote nunca
/// chega a ser aplicado: com o token revogado, `syncDeferred` recusa na
/// resolução do token, antes de abrir a transação — se ele chegasse a rodar, a
/// exceção seria outra.
VisitSyncEntry _visita() => VisitSyncEntry(
  localId: '00000000-0000-4000-8000-0000000000bd',
  patientId: _paciente,
  scheduledAt: _t,
  completedAt: _t.add(const Duration(hours: 1)),
  status: 'realizada',
  riskLevelBefore: RiskLevel.green,
  notes: const {'campo': 'sintético'},
  version: 0,
  arrivalMethod: ArrivalMethod.manual,
);

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

    test(
      'desativar revoga refresh e envio diferido: refreshSession e syncDeferred são recusados depois',
      () async {
        const aparelho = 'aparelho-desativacao-1';
        await _usuario(
          session,
          _acsDesat,
          'Dora ACS Desativável',
          UserRole.acs,
          ma: _maA,
        );
        await Acs.db.insertRow(
          session,
          Acs(
            id: UuidValue.fromString(_acsDesat),
            enrollmentId: _matriculaDesat,
            ubsId: UuidValue.fromString(_ubsA),
            active: true,
          ),
        );
        await _credencial(
          session,
          _acsDesat,
          digest: await AlertRuntimeHarness.hasher.derive(_senha),
        );

        // 1. Login real pelo endpoint, com aparelho: emite a sessão (refresh) e
        //    o token do envio diferido, que até aqui sobrevivem a um ao outro.
        final login = await endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matriculaDesat,
          password: _senha,
          deviceId: aparelho,
        );
        final refreshToken = login.refreshToken;
        final uploadToken = login.uploadToken;
        expect(refreshToken, isNotNull);
        expect(uploadToken, isNotNull);

        // 2. A desativação pelo backoffice.
        final desativado = await endpoints.admin.setAcsActive(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
          acsId: _acsDesat,
          active: false,
        );
        expect(desativado.active, isFalse);

        // 3. SQL: as duas tabelas do usuário ficaram sem NENHUMA linha vigente
        //    (e as linhas existem — senão a asserção passaria por vacuidade).
        for (final tabela in ['acs_refresh_tokens', 'acs_upload_tokens']) {
          expect(await _tokens(session, tabela, _acsDesat), greaterThan(0));
          expect(
            await _tokens(session, tabela, _acsDesat, soVigentes: true),
            0,
            reason: '$tabela: toda linha do usuário desativado está revogada',
          );
        }

        // 4. A renovação é recusada — e a linha da trilha diz que a recusa veio
        //    da revogação, não do desvio pela conta inativa (`denied_inactive`).
        await expectLater(
          endpoints.auth.refreshSession(
            sessionBuilder,
            refreshToken: refreshToken!,
            deviceId: aparelho,
          ),
          throwsA(isA<SessionExpiredException>()),
        );
        expect(await _auditorias(session, 'session_refresh', 'denied_revoked'), 1);
        expect(await _auditorias(session, 'session_refresh', 'denied_inactive'), 0);

        // 5. O envio diferido é recusado na resolução do token, antes do lote:
        //    é o que impede o aparelho de um ACS desativado de subir visitas com
        //    a autoria dele durante os 7 dias de validade do token.
        await expectLater(
          endpoints.visits.syncDeferred(
            sessionBuilder,
            uploadToken: uploadToken!,
            deviceId: aparelho,
            visits: [_visita()],
          ),
          throwsA(isA<SessionExpiredException>()),
        );
        expect(
          await Visit.db.findFirstRow(
            session,
            where: (v) => v.localId.equals(
              UuidValue.fromString(_visita().localId),
            ),
          ),
          isNull,
          reason: 'nada foi gravado',
        );

        // 6. E o login por senha recusa com a mensagem da conta inativa.
        await expectLater(
          endpoints.auth.loginInstitutional(
            sessionBuilder,
            matricula: _matriculaDesat,
            password: _senha,
            deviceId: aparelho,
          ),
          throwsA(
            isA<AuthenticationFailedException>().having(
              (e) => e.message,
              'message',
              'Este acesso está inativo.',
            ),
          ),
        );

        // 7. Reativar devolve o acesso por um LOGIN NOVO: os tokens revogados
        //    não voltam à vida.
        await endpoints.admin.setAcsActive(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
          acsId: _acsDesat,
          active: true,
        );
        final novoLogin = await endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matriculaDesat,
          password: _senha,
          deviceId: aparelho,
        );
        expect(novoLogin.accessToken, isNotEmpty);
        expect(novoLogin.refreshToken, isNot(refreshToken));
        await expectLater(
          endpoints.auth.refreshSession(
            sessionBuilder,
            refreshToken: refreshToken,
            deviceId: aparelho,
          ),
          throwsA(isA<SessionExpiredException>()),
        );

        expect(await _auditorias(session, 'admin_acs', 'deactivated'), 1);
        expect(await _auditorias(session, 'admin_acs', 'activated'), 1);
        expect(await _auditorias(session, 'admin_acs', 'denied'), 0);
      },
    );

    test(
      'redefinir a senha devolve uma senha nova, grava o Argon2id novo e zera o bloqueio (failedAttempts, lockedUntil e lockStreak)',
      () async {
        // Fixture do caso: um ACS com senha de verdade — a fixture compartilhada
        // só guarda hash sintético, e é a senha que abre o login.
        await _usuario(session, _acsSenha, 'Sofia ACS Senha', UserRole.acs, ma: _maA);
        await Acs.db.insertRow(
          session,
          Acs(
            id: UuidValue.fromString(_acsSenha),
            enrollmentId: _matriculaSenha,
            ubsId: UuidValue.fromString(_ubsA),
            active: true,
          ),
        );
        await _credencial(
          session,
          _acsSenha,
          digest: await AlertRuntimeHarness.hasher.derive(_senha),
        );

        // 1. Conta bloqueada com duas rodadas de bloqueio no histórico
        //    (`lockStreak = 2`): nem a senha certa entra enquanto o bloqueio
        //    vale.
        final antes = await _credencialDo(session, _acsSenha);
        await UserCredential.db.updateRow(
          session,
          antes
            ..failedAttempts = 5
            ..lockedUntil = DateTime.now().toUtc().add(const Duration(hours: 1))
            ..lockStreak = 2,
        );
        await expectLater(
          endpoints.auth.loginInstitutional(
            sessionBuilder,
            matricula: _matriculaSenha,
            password: _senha,
          ),
          throwsA(isA<AuthenticationFailedException>()),
        );

        // 2. O coordenador da UBS A redefine a senha: a nova é sorteada pelo
        //    servidor, nunca escolhida pelo operador.
        final r = await endpoints.admin.resetAcsPassword(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          acsId: _acsSenha,
        );
        expect(r.newPassword, isNotEmpty);
        expect(r.newPassword, isNot(_senha));

        // 3. A linha está zerada: a credencial nova não herda o bloqueio da
        //    antiga (e o hash é o de outro Argon2id).
        final depois = await _credencialDo(session, _acsSenha);
        expect(depois.failedAttempts, 0);
        expect(depois.lockedUntil, isNull);
        expect(
          depois.lockStreak,
          0,
          reason: 'as rodadas de bloqueio da credencial que deixou de existir não sobrevivem',
        );
        expect(depois.passwordHash, isNot(antes.passwordHash));

        // 4. A senha nova abre o RF07; a antiga, não.
        final login = await endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matriculaSenha,
          password: r.newPassword,
        );
        expect(AlertRuntimeHarness.verify(login.accessToken)!.id, _acsSenha);
        await expectLater(
          endpoints.auth.loginInstitutional(
            sessionBuilder,
            matricula: _matriculaSenha,
            password: _senha,
          ),
          throwsA(isA<AuthenticationFailedException>()),
        );

        // 5. As sessões em curso não são revogadas por uma redefinição de senha
        //    (decisão D8): o que a trilha registra é a troca da credencial.
        expect(await _auditorias(session, 'admin_acs', 'password_reset'), 1);
        expect(await _auditorias(session, 'admin_acs', 'denied'), 0);
      },
    );

    test(
      'redefinir a MFA zera as quatro colunas totp* e a próxima entrada pede ativação de novo',
      () async {
        // Fixture do caso: ACS com senha de verdade e MFA ativada pelo fluxo
        // real (begin → confirm), como o app do ACS faz.
        await _usuario(session, _acsMfa, 'Marta ACS MFA', UserRole.acs, ma: _maA);
        await Acs.db.insertRow(
          session,
          Acs(
            id: UuidValue.fromString(_acsMfa),
            enrollmentId: _matriculaMfa,
            ubsId: UuidValue.fromString(_ubsA),
            active: true,
          ),
        );
        await _credencial(
          session,
          _acsMfa,
          digest: await AlertRuntimeHarness.hasher.derive(_senha),
        );

        final inicio = await endpoints.auth.beginTotpEnrollment(
          sessionBuilder,
          matricula: _matriculaMfa,
          password: _senha,
        );
        await endpoints.auth.confirmTotpEnrollment(
          sessionBuilder,
          matricula: _matriculaMfa,
          password: _senha,
          code: Totp.code(_deBase32(inicio.secretBase32), DateTime.now().toUtc()),
        );

        // Com a MFA ativa, a senha sozinha já não entra.
        final comMfa = _servicoDeLogin(session);
        await expectLater(
          comMfa.login(matricula: _matriculaMfa, password: _senha),
          throwsA(isA<MfaRequiredException>()),
        );
        final hashDaSenha = (await _credencialDo(session, _acsMfa)).passwordHash;

        // O coordenador da UBS A redefine a MFA.
        await endpoints.admin.resetAcsMfa(
          sessionBuilder,
          accessToken: _token(_coordA, UserRole.coordinator),
          acsId: _acsMfa,
        );

        // As QUATRO colunas voltam a NULL — inclusive `totpLastStep`, que
        // deixaria um código do segredo antigo valendo como replay.
        final linha = await _credencialDo(session, _acsMfa);
        expect(linha.totpSecretEncrypted, isNull);
        expect(linha.totpKeyVersion, isNull);
        expect(linha.totpEnabledAt, isNull);
        expect(linha.totpLastStep, isNull);
        expect(
          linha.passwordHash,
          hashDaSenha,
          reason: 'redefinir a MFA não toca no primeiro fator',
        );

        // A entrada seguinte pede a ativação de novo: é o caminho que a recusa
        // "Peça a redefinição à coordenação" não tinha.
        await expectLater(
          comMfa.login(matricula: _matriculaMfa, password: _senha),
          throwsA(
            isA<MfaEnrollmentRequiredException>().having(
              (e) => e.message,
              'message',
              'Ative a verificação em duas etapas antes de entrar.',
            ),
          ),
        );
        final novo = await endpoints.auth.beginTotpEnrollment(
          sessionBuilder,
          matricula: _matriculaMfa,
          password: _senha,
        );
        expect(
          novo.secretBase32,
          isNot(inicio.secretBase32),
          reason: 'o segredo novo não é o antigo (que não existe mais em lugar nenhum)',
        );

        final lista = await endpoints.admin.acs(
          sessionBuilder,
          accessToken: _token(_admin, UserRole.admin),
        );
        expect(lista.singleWhere((a) => a.id == _acsMfa).mfaActive, isFalse);
        expect(await _auditorias(session, 'admin_acs', 'mfa_reset'), 1);
      },
    );

    test('redefinir a MFA de um ACS sem MFA é idempotente e ainda audita mfa_reset', () async {
      // `_acsB` tem credencial e nenhum segredo em `user_credentials`: a
      // limpeza não acha nada a apagar e a operação conclui do mesmo jeito.
      await _credencial(session, _acsB);
      expect((await _credencialDo(session, _acsB)).totpSecretEncrypted, isNull);

      final t = _token(_admin, UserRole.admin);
      for (var i = 0; i < 2; i++) {
        await endpoints.admin.resetAcsMfa(sessionBuilder, accessToken: t, acsId: _acsB);
      }

      final depois = await _credencialDo(session, _acsB);
      expect(depois.totpSecretEncrypted, isNull);
      expect(depois.totpEnabledAt, isNull);
      expect(
        await _auditorias(session, 'admin_acs', 'mfa_reset'),
        2,
        reason: 'idempotente não é silencioso: cada pedido do operador vira uma linha',
      );
    });
  });
}
