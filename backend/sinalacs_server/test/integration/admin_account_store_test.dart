import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_account_store.dart';
import 'package:test/test.dart';

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
  });
}
