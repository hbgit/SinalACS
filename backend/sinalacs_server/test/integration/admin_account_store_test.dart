import 'dart:convert';
import 'dart:math';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_account_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_otp_challenge_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_upload_token_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Gestão de contas do backoffice (#43) contra Postgres real: escopo por UBS,
/// ACS ainda sem território e `mfaActive`. Dados sintéticos; ids próprios.
///
/// UBS A (microárea A): dois ACS — um com MFA ativa, um ainda sem microárea.
/// UBS B (microárea B): um ACS com MFA **pendente** (segredo gravado, ativação
/// não confirmada), que não conta como ativa, e outro sem nenhuma credencial.
const _ubsA = '00000000-0000-4000-8000-0000000000a1';
const _ubsB = '00000000-0000-4000-8000-0000000000a2';
const _maA = '00000000-0000-4000-8000-0000000000a3';
const _maB = '00000000-0000-4000-8000-0000000000a4';
const _acsA = '00000000-0000-4000-8000-0000000000a5';
const _acsSemMicroarea = '00000000-0000-4000-8000-0000000000a6';
const _acsBPendente = '00000000-0000-4000-8000-0000000000a7';
const _acsBSemCredencial = '00000000-0000-4000-8000-0000000000a8';
const _admin = '00000000-0000-4000-8000-0000000000a9';
const _coordA = '00000000-0000-4000-8000-0000000000aa';
const _coordSemUbs = '00000000-0000-4000-8000-0000000000ab';

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
        cpfHash: 'admin-acc-$id',
        name: nome,
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

/// Credencial de login; `totpEnabledAt` só entra quando a MFA está ativa.
Future<void> _credencial(
  Session s,
  String userId, {
  bool mfaAtiva = false,
  bool mfaPendente = false,
}) => UserCredential.db
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
        totpSecretEncrypted: mfaAtiva || mfaPendente ? 'segredo-sintetico' : null,
        totpKeyVersion: mfaAtiva || mfaPendente ? 1 : null,
        totpEnabledAt: mfaAtiva ? _t : null,
      ),
    )
    .then((_) {});

Future<void> _acs(
  Session s,
  String id,
  String matricula,
  String ubs,
) => Acs.db
    .insertRow(
      s,
      Acs(
        id: UuidValue.fromString(id),
        enrollmentId: matricula,
        ubsId: UuidValue.fromString(ubs),
        active: true,
      ),
    )
    .then((_) {});

Future<void> _staff(
  Session s,
  String id,
  String matricula, {
  String? ubs,
}) => StaffAccount.db
    .insertRow(
      s,
      StaffAccount(
        id: UuidValue.fromString(id),
        enrollmentId: matricula,
        active: true,
        ubsId: ubs == null ? null : UuidValue.fromString(ubs),
      ),
    )
    .then((_) {});

/// Auditoria de mentira: o que se prova aqui é o efeito da operação nas tabelas
/// (transação, login com a senha gerada), e a trilha do serviço já tem os
/// próprios testes contra um `AuditTrail` que registra de verdade.
/// `_RecordingAudit`, de `institutional_login_test.dart`, pelo mesmo motivo.
class _Audit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

/// O mesmo store real, com a pré-checagem de matrícula desligada: abre de
/// propósito a janela entre "a matrícula está livre" e o INSERT, que na
/// produção só outra requisição simultânea abre.
class _SemPreChecagem extends OrmAdminAccountStore {
  _SemPreChecagem({required super.session});

  @override
  Future<bool> enrollmentIdTaken(String enrollmentId) async => false;
}

/// Serviço montado como o endpoint o monta (`adminAccountServiceFor`), com o
/// hasher de custo reduzido do harness: a integração prova o caminho, não o
/// custo do Argon2id.
AdminAccountService _servico(
  Session session,
  AdminAccountStore store, {
  required AuditTrail audit,
}) => AdminAccountService(
  store: store,
  credentials: OrmAcsCredentialStore(session: () => session),
  totpStore: OrmAcsCredentialStore(session: () => session),
  activationStore: OrmAcsCredentialStore(session: () => session, staff: true),
  refreshStore: OrmRefreshTokenStore(session: () => session),
  uploadStore: OrmUploadTokenStore(session: () => session),
  hasher: AlertRuntimeHarness.hasher,
  audit: audit,
  clock: () => _t,
  random: Random(1),
);

AuthenticatedUser _operador(String id, UserRole role) => AuthenticatedUser(
  id: id,
  role: role,
  microAreaId: null,
  deviceId: 'sem-aparelho',
);

Future<int> _contar(Session s, String consulta) async {
  final linhas = await s.db.unsafeQuery(consulta);
  return linhas.single[0] as int;
}

/// A senha da corrida de matrícula: o `insertAcs` direto precisa de um digest.
Future<PasswordDigest> _digestSintetico() =>
    AlertRuntimeHarness.hasher.derive('senha-sintetica-de-teste');

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

  // Nomes em ordem alfabética de propósito: a listagem ordena por nome e id.
  await _usuario(s, _acsA, 'Ana ACS Sintética', UserRole.acs, ma: _maA);
  await _acs(s, _acsA, 'ACS-ACC-1', _ubsA);
  await _credencial(s, _acsA, mfaAtiva: true);

  await _usuario(s, _acsSemMicroarea, 'Bruno ACS Sintético', UserRole.acs);
  await _acs(s, _acsSemMicroarea, 'ACS-ACC-2', _ubsA);

  await _usuario(s, _acsBPendente, 'Carla ACS Sintética', UserRole.acs, ma: _maB);
  await _acs(s, _acsBPendente, 'ACS-ACC-3', _ubsB);
  await _credencial(s, _acsBPendente, mfaPendente: true);

  await _usuario(s, _acsBSemCredencial, 'Dora ACS Sintética', UserRole.acs, ma: _maB);
  await _acs(s, _acsBSemCredencial, 'ACS-ACC-4', _ubsB);

  await _usuario(s, _admin, 'Elisa Administradora Sintética', UserRole.admin);
  await _staff(s, _admin, 'ADM-ACC-1');
  await _credencial(s, _admin, mfaAtiva: true);

  await _usuario(s, _coordA, 'Fábio Coordenador Sintético', UserRole.coordinator);
  await _staff(s, _coordA, 'COO-ACC-1', ubs: _ubsA);

  await _usuario(s, _coordSemUbs, 'Gilda Coordenadora Sintética', UserRole.coordinator);
  await _staff(s, _coordSemUbs, 'COO-ACC-2');
}

void main() {
  withServerpod('Dada a gestão de contas do backoffice (#43)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmAdminAccountStore store;
    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = OrmAdminAccountStore(session: () => session);
    });

    test('o escopo de sistema vê os ACS das duas UBS, com o território de cada um', () async {
      final lista = await store.acsList(const AdminScope.system());
      expect(lista.map((a) => a.name), [
        'Ana ACS Sintética',
        'Bruno ACS Sintético',
        'Carla ACS Sintética',
        'Dora ACS Sintética',
      ]);
      final ana = lista.first;
      expect(ana.enrollmentId, 'ACS-ACC-1');
      expect(ana.ubsId, _ubsA);
      expect(ana.ubsName, 'UBS A');
      expect(ana.microAreaId, _maA);
      expect(ana.microAreaName, 'Microárea A');
      expect(ana.active, isTrue);
    });

    test('o escopo de UBS A não vê o ACS da UBS B', () async {
      final lista = await store.acsList(const AdminScope.ubs(_ubsA));
      expect(lista.map((a) => a.name), [
        'Ana ACS Sintética',
        'Bruno ACS Sintético',
      ]);
      expect(lista.map((a) => a.ubsId).toSet(), {_ubsA});
    });

    test('ACS sem microárea aparece na listagem com microAreaId nulo', () async {
      final lista = await store.acsList(const AdminScope.ubs(_ubsA));
      final bruno = lista.singleWhere((a) => a.name == 'Bruno ACS Sintético');
      expect(bruno.microAreaId, isNull);
      expect(bruno.microAreaName, isNull);
      expect(bruno.ubsName, 'UBS A');
    });

    test('mfaActive reflete totpEnabledAt: pendente não conta como ativa', () async {
      final lista = await store.acsList(const AdminScope.system());
      final porNome = {for (final a in lista) a.name: a.mfaActive};
      expect(porNome['Ana ACS Sintética'], isTrue);
      expect(
        porNome['Carla ACS Sintética'],
        isFalse,
        reason: 'segredo gravado sem ativação confirmada não é MFA ativa',
      );
      expect(porNome['Dora ACS Sintética'], isFalse, reason: 'sem credencial');
    });

    test('acsById devolve o ACS do escopo e nulo fora dele', () async {
      final dentro = await store.acsById(const AdminScope.ubs(_ubsA), _acsA);
      expect(dentro?.name, 'Ana ACS Sintética');
      expect(
        await store.acsById(const AdminScope.ubs(_ubsB), _acsA),
        isNull,
        reason: 'ACS da UBS A não existe para o escopo da UBS B',
      );
      expect(await store.acsById(const AdminScope.system(), _acsA), isNotNull);
    });

    test('acsById e staffById com id que não é UUID devolvem nulo, sem erro de SQL', () async {
      for (final id in ['lixo', '123', '']) {
        expect(await store.acsById(const AdminScope.system(), id), isNull);
        expect(await store.staffById(id), isNull);
      }
    });

    test('staffList traz papel, UBS e mfaActive de cada conta', () async {
      final lista = await store.staffList();
      expect(lista.map((s) => s.name), [
        'Elisa Administradora Sintética',
        'Fábio Coordenador Sintético',
        'Gilda Coordenadora Sintética',
      ]);
      final elisa = lista.first;
      expect(elisa.enrollmentId, 'ADM-ACC-1');
      expect(elisa.role, UserRole.admin);
      expect(elisa.ubsName, isNull, reason: 'o administrador vê o sistema inteiro');
      expect(elisa.mfaActive, isTrue);
      final fabio = lista.singleWhere((s) => s.role == UserRole.coordinator && s.ubsName != null);
      expect(fabio.ubsName, 'UBS A');
      expect(fabio.mfaActive, isFalse);
    });

    test('staffById devolve a conta e nulo para id desconhecido', () async {
      expect(
        (await store.staffById(_coordA))?.enrollmentId,
        'COO-ACC-1',
      );
      expect(await store.staffById(_acsA), isNull, reason: 'ACS não é conta de equipe');
    });

    test('ubsOf é a UBS do coordenador; nulo para o administrador e para id inválido', () async {
      expect(await store.ubsOf(_coordA), _ubsA);
      expect(await store.ubsOf(_admin), isNull);
      expect(await store.ubsOf(_coordSemUbs), isNull);
      expect(await store.ubsOf('lixo'), isNull);
    });

    test('microAreaFor devolve a UBS dona da microárea, e nulo fora do formato de UUID', () async {
      expect(await store.microAreaFor(_maA), (name: 'Microárea A', ubsId: _ubsA));
      expect(await store.microAreaFor('00000000-0000-4000-8000-0000000000ff'), isNull);
      expect(await store.microAreaFor('lixo'), isNull, reason: 'sem erro de sintaxe do ::uuid');
    });

    test('enrollmentIdTaken só é verdadeiro para matrícula de ACS existente', () async {
      expect(await store.enrollmentIdTaken('ACS-ACC-1'), isTrue);
      expect(await store.enrollmentIdTaken('ACS-ACC-9'), isFalse);
      expect(await store.enrollmentIdTaken('ADM-ACC-1'), isFalse, reason: 'matrícula de staff não é de ACS');
    });

    group('createAcs (#43, cadastro)', () {
      late _Audit auditoria;
      late AdminAccountService servico;
      final admin = _operador(_admin, UserRole.admin);

      setUp(() {
        auditoria = _Audit();
        servico = _servico(session, store, audit: auditoria);
      });

      test('cadastro grava users+acs+user_credentials e o ACS consegue logar com a senha gerada', () async {
        final r = await servico.createAcs(
          admin,
          name: 'Nova ACS Sintética',
          enrollmentId: 'ACS-43-1',
          microAreaId: _maA,
        );

        expect(r.acs.name, 'Nova ACS Sintética');
        expect(r.acs.enrollmentId, 'ACS-43-1');
        expect(r.acs.ubsId, _ubsA, reason: 'a UBS vem da microárea, nunca do pedido');
        expect(r.acs.ubsName, 'UBS A');
        expect(r.acs.microAreaId, _maA);
        expect(r.acs.microAreaName, 'Microárea A');
        expect(r.acs.active, isTrue);
        expect(r.acs.mfaActive, isFalse, reason: 'cadastro não ativa MFA nenhuma');

        final id = UuidValue.fromString(r.acs.id);
        final usuario = await User.db.findById(session, id);
        expect(usuario!.role, UserRole.acs);
        expect(usuario.microAreaId, UuidValue.fromString(_maA));
        expect((await Acs.db.findById(session, id))!.enrollmentId, 'ACS-43-1');
        final credencial = await UserCredential.db.findFirstRow(
          session,
          where: (t) => t.userId.equals(id),
        );
        expect(credencial, isNotNull);
        expect(
          jsonEncode(credencial!.toJson()),
          isNot(contains(r.initialPassword)),
          reason: 'a senha em claro não é gravada em coluna nenhuma',
        );

        // A prova que interessa: a senha mostrada uma única vez é a que abre o
        // login institucional (RF07), já com o território do cadastro.
        final login = await InstitutionalAuthService(
          store: AlertRuntimeHarness.store(session),
          hasher: AlertRuntimeHarness.hasher,
          audit: _Audit(),
        ).login(matricula: 'ACS-43-1', password: r.initialPassword);
        expect(login.id, r.acs.id);
        expect(login.role, UserRole.acs);
        expect(login.microAreaId, _maA);

        expect(auditoria.events.single.actionType, 'write');
        expect(auditoria.events.single.resourceType, 'admin_acs');
        expect(auditoria.events.single.result, 'created');
        expect(auditoria.events.single.resourceId, r.acs.id);
      });

      test('falha injetada depois de users não deixa órfão: nem users, nem acs, nem credencial', () async {
        final quebrado = OrmAdminAccountStore(
          session: () => session,
          debugFailAfterUsersInsert: true,
        );
        final servicoQuebrado = _servico(session, quebrado, audit: _Audit());

        await expectLater(
          servicoQuebrado.createAcs(
            admin,
            name: 'Fantasma Sintética',
            enrollmentId: 'ACS-43-2',
            microAreaId: _maA,
          ),
          throwsA(isA<StateError>()),
        );

        expect(
          await User.db.findFirstRow(
            session,
            where: (t) => t.name.equals('Fantasma Sintética'),
          ),
          isNull,
          reason: 'a transação desfez o INSERT de users',
        );
        expect(
          await Acs.db.findFirstRow(
            session,
            where: (t) => t.enrollmentId.equals('ACS-43-2'),
          ),
          isNull,
        );
        expect(
          await _contar(session, 'SELECT count(*) FROM user_credentials'),
          3,
          reason: 'só as credenciais do seed: nenhuma órfã ficou para trás',
        );
      });

      test('matrícula repetida devolve null (corrida) e o serviço responde validação, não 500', () async {
        await servico.createAcs(
          admin,
          name: 'Primeira ACS Sintética',
          enrollmentId: 'ACS-43-3',
          microAreaId: _maA,
        );

        // Caso comum: a pré-checagem barra antes de qualquer escrita.
        await expectLater(
          servico.createAcs(
            admin,
            name: 'Segunda ACS Sintética',
            enrollmentId: 'ACS-43-3',
            microAreaId: _maA,
          ),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Já existe um ACS com esta matrícula.',
            ),
          ),
        );

        // Corrida: o índice único é quem barra, e o store traduz o 23505 em
        // `null` — não em erro de banco.
        final semPreChecagem = _SemPreChecagem(session: () => session);
        expect(
          await semPreChecagem.insertAcs(
            name: 'Segunda ACS Sintética',
            enrollmentId: 'ACS-43-3',
            microAreaId: _maA,
            ubsId: _ubsA,
            digest: await _digestSintetico(),
            at: _t,
          ),
          isNull,
        );

        // E o serviço, com a janela aberta, responde a MESMA validação.
        await expectLater(
          _servico(session, semPreChecagem, audit: _Audit()).createAcs(
            admin,
            name: 'Terceira ACS Sintética',
            enrollmentId: 'ACS-43-3',
            microAreaId: _maA,
          ),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Já existe um ACS com esta matrícula.',
            ),
          ),
        );

        expect(
          await Acs.db.find(
            session,
            where: (t) => t.enrollmentId.equals('ACS-43-3'),
          ),
          hasLength(1),
        );
        expect(
          await User.db.find(
            session,
            where: (t) => t.name.equals('Terceira ACS Sintética'),
          ),
          isEmpty,
          reason: 'o cadastro perdido da corrida não deixou usuário nenhum',
        );
      });

      test('o CPF placeholder e a data sentinela do ACS não abrem login passwordless de paciente', () async {
        final r = await servico.createAcs(
          admin,
          name: 'Nova ACS Sintética',
          enrollmentId: 'ACS-43-4',
          microAreaId: _maA,
        );
        final usuario = (await User.db.findById(
          session,
          UuidValue.fromString(r.acs.id),
        ))!;

        expect(usuario.cpfHash, 'acs-sem-cpf-${r.acs.id}');
        expect(usuario.birthDate, DateTime.utc(1900, 1, 1));
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(usuario.cpfHash),
          isFalse,
          reason: 'o login procura por `hasher.hash(cpf)`, sempre 64 dígitos hexadecimais',
        );

        // O passo exato do login passwordless: `verifyOtp` procura pelo HMAC
        // do CPF digitado, e o placeholder do ACS não tem como ser um.
        final otpStore = OrmOtpChallengeStore(session: () => session);
        final hmacDoCpf = AlertRuntime.instance.cpfHasherForTests.hash(
          Cpf.tryParse('52998224725')!,
        );
        expect(await otpStore.findByCpfHash(hmacDoCpf), isNull);

        // Controle: o mesmo caminho ACHA um paciente de verdade — o nulo acima
        // é ausência de ACS, não um lookup que nunca devolve nada.
        const paciente = '00000000-0000-4000-8000-0000000000ac';
        await User.db.insertRow(
          session,
          User(
            id: UuidValue.fromString(paciente),
            cpfHash: hmacDoCpf,
            name: 'Paciente Sintética',
            birthDate: DateTime.utc(1990),
            role: UserRole.patient,
            microAreaId: UuidValue.fromString(_maA),
            createdAt: _t,
            updatedAt: _t,
          ),
        );
        expect((await otpStore.findByCpfHash(hmacDoCpf))?.userId, paciente);
      });
    });

    group('setAcsMicroArea (#43, vínculo)', () {
      late _Audit auditoria;
      late AdminAccountService servico;
      final admin = _operador(_admin, UserRole.admin);
      final coordA = _operador(_coordA, UserRole.coordinator);

      setUp(() {
        auditoria = _Audit();
        servico = _servico(session, store, audit: auditoria);
      });

      test('coordenador vincula à própria UBS o ACS que ainda não tinha território', () async {
        final r = await servico.setAcsMicroArea(
          coordA,
          acsId: _acsSemMicroarea,
          microAreaId: _maA,
        );

        expect(r.microAreaId, _maA);
        expect(r.microAreaName, 'Microárea A');
        expect(r.ubsId, _ubsA, reason: 'a UBS vem da microárea-alvo');

        final usuario = (await User.db.findById(
          session,
          UuidValue.fromString(_acsSemMicroarea),
        ))!;
        expect(usuario.microAreaId, UuidValue.fromString(_maA));
        expect(usuario.updatedAt, _t, reason: 'o carimbo do vínculo é o do serviço');
        expect(
          (await Acs.db.findById(session, UuidValue.fromString(_acsSemMicroarea)))!
              .ubsId,
          UuidValue.fromString(_ubsA),
          reason: 'a UBS do ACS não muda quando a microárea é da mesma UBS',
        );

        // A listagem do coordenador já o mostra no território novo.
        final lista = await store.acsList(const AdminScope.ubs(_ubsA));
        expect(
          lista.singleWhere((a) => a.id == _acsSemMicroarea).microAreaName,
          'Microárea A',
        );

        expect(auditoria.events.single.actionType, 'write');
        expect(auditoria.events.single.resourceType, 'admin_acs');
        expect(auditoria.events.single.result, 'micro_area_changed');
        expect(auditoria.events.single.resourceId, _acsSemMicroarea);
      });

      test('admin move o ACS para microárea de outra UBS e a UBS dele muda junto', () async {
        await servico.setAcsMicroArea(admin, acsId: _acsA, microAreaId: _maB);

        expect(
          (await Acs.db.findById(session, UuidValue.fromString(_acsA)))!.ubsId,
          UuidValue.fromString(_ubsB),
          reason: 'a UBS do vínculo sai da microárea-alvo, nunca do chamador',
        );
        expect(
          (await User.db.findById(session, UuidValue.fromString(_acsA)))!.microAreaId,
          UuidValue.fromString(_maB),
        );

        final ubsA = await store.acsList(const AdminScope.ubs(_ubsA));
        expect(ubsA.map((a) => a.id), isNot(contains(_acsA)));
        final ubsB = await store.acsList(const AdminScope.ubs(_ubsB));
        final ana = ubsB.singleWhere((a) => a.id == _acsA);
        expect(ana.ubsName, 'UBS B');
        expect(ana.microAreaName, 'Microárea B');
      });

      test('o escopo dentro do UPDATE: ACS de outra UBS não é movido nem chamando o store direto', () async {
        // Sem a pré-checagem do serviço: quem barra é o predicado de escopo
        // repetido no `WHERE` do UPDATE (a defesa em profundidade do TOCTOU).
        expect(
          await store.setAcsMicroArea(
            acsId: _acsBPendente,
            microAreaId: _maA,
            ubsId: _ubsA,
            scope: const AdminScope.ubs(_ubsA),
            at: _t,
          ),
          isNull,
        );
        // E um id fora do formato de UUID devolve o mesmo nulo, sem erro de SQL.
        expect(
          await store.setAcsMicroArea(
            acsId: 'lixo',
            microAreaId: _maA,
            ubsId: _ubsA,
            scope: const AdminScope.system(),
            at: _t,
          ),
          isNull,
        );

        expect(
          (await Acs.db.findById(session, UuidValue.fromString(_acsBPendente)))!.ubsId,
          UuidValue.fromString(_ubsB),
        );
        expect(
          (await User.db.findById(session, UuidValue.fromString(_acsBPendente)))!
              .microAreaId,
          UuidValue.fromString(_maB),
          reason: 'nenhuma das duas escritas da transação rodou',
        );
      });

      test('ACS inexistente recebe a mesma recusa do escopo, auditada denied', () async {
        await expectLater(
          servico.setAcsMicroArea(
            coordA,
            acsId: '00000000-0000-4000-8000-0000000000ff',
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
        expect(auditoria.events.single.actionType, 'write');
        expect(auditoria.events.single.result, 'denied');
      });

      test('ACS órfão (sem a linha de users) não move nada: a transação desfaz o UPDATE de acs', () async {
        // O acs não tem FK para users, então esta linha inconsistente é
        // gravável — e é o que prova que o vínculo é atômico: a segunda escrita
        // não acha o usuário e a transação inteira volta atrás.
        const orfao = '00000000-0000-4000-8000-0000000000ad';
        await _acs(session, orfao, 'ACS-ACC-ORFAO', _ubsA);
        await expectLater(
          store.setAcsMicroArea(
            acsId: orfao,
            microAreaId: _maB,
            ubsId: _ubsB,
            scope: const AdminScope.system(),
            at: _t,
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          (await Acs.db.findById(session, UuidValue.fromString(orfao)))!.ubsId,
          UuidValue.fromString(_ubsA),
          reason: 'o UPDATE de acs foi desfeito junto com a escrita que faltou',
        );
      });
    });
  });
}
