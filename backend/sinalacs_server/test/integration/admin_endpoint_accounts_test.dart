import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// `admin.acs` e `admin.staff` (#43) pelo endpoint, com tokens reais e Postgres
/// real: papel, escopo por UBS, auditoria de cada leitura e minimização de PII.
/// Dados sintéticos; ids próprios.
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
  });
}
