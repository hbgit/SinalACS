import 'dart:convert';
import 'dart:typed_data';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_cipher_totp_vault.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Login institucional do staff do backoffice (#39) contra Postgres real:
/// prova a travessia `staff_accounts.enrollmentId → users.role →
/// user_credentials` do `OrmAcsCredentialStore(staff: true)` e que as duas
/// tabelas de matrícula não se cruzam — matrícula de ACS não existe para o
/// login do staff, e matrícula de staff não existe para o login do ACS.
///
/// Dados sintéticos; ids próprios, distintos das outras suítes.
const _adminId = '00000000-0000-4000-8000-0000000000a1';
const _adminMatricula = 'ADM-INT-001';
const _acsId = '00000000-0000-4000-8000-0000000000a2';
const _acsMatricula = 'ACS-001';
const _microAreaId = '00000000-0000-4000-8000-0000000000a3';
const _ubsId = '00000000-0000-4000-8000-0000000000a4';
const _senha = 'senha-sintetica-de-teste';
const _mensagemGenerica = 'Matrícula ou senha inválidos.';

/// Segredo TOTP sintético, gravado já ativo (como se a ativação tivesse
/// acontecido): o caso aqui é o login, não a ativação.
final _segredo = Uint8List.fromList(List<int>.generate(20, (i) => 40 + i));

Future<void> _seed(Session session) async {
  final now = DateTime.now().toUtc();

  // Administrador: sem microárea, com linha em staff_accounts.
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_adminId),
      cpfHash: 'development-staff-admin',
      name: 'Administrador sintético',
      birthDate: DateTime.utc(1980),
      role: UserRole.admin,
      microAreaId: null,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await StaffAccount.db.insertRow(
    session,
    StaffAccount(id: UuidValue.fromString(_adminId), enrollmentId: _adminMatricula, active: true),
  );
  await AlertRuntimeHarness.store(session)
      .saveCredential(_adminId, await AlertRuntimeHarness.hasher.derive(_senha), now);
  final sealed = await HealthCipherTotpVault(AlertRuntime.instance.healthDataCipher).seal(_segredo);
  final credencial = (await UserCredential.db.findFirstRow(
    session,
    where: (t) => t.userId.equals(UuidValue.fromString(_adminId)),
  ))!;
  await UserCredential.db.updateRow(
    session,
    credencial
      ..totpSecretEncrypted = sealed.ciphertextBase64
      ..totpKeyVersion = sealed.keyVersion
      ..totpEnabledAt = now
      ..totpLastStep = null,
  );

  // ACS com território, mesma senha: a matrícula ACS-001 do login do ACS.
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Staff',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea Staff',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-staff-acs',
      name: 'ACS sintético',
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
      enrollmentId: _acsMatricula,
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await AlertRuntimeHarness.store(session)
      .saveCredential(_acsId, await AlertRuntimeHarness.hasher.derive(_senha), now);
}

class _SemAuditoria extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

InstitutionalAuthService _servico(Session session, {required bool staff}) {
  final store = OrmAcsCredentialStore(session: () => session, staff: staff);
  return InstitutionalAuthService(
    store: store,
    hasher: AlertRuntimeHarness.hasher,
    audit: _SemAuditoria(),
    totpStore: store,
    vault: HealthCipherTotpVault(AlertRuntime.instance.healthDataCipher),
    audience: staff ? CredentialAudience.staff : CredentialAudience.acs,
  );
}

Map<String, dynamic> _payload(String token) => jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    ) as Map<String, dynamic>;

void main() {
  withServerpod('Dado o login institucional do staff do backoffice (#39)', (
    sessionBuilder,
    endpoints,
  ) {
    setUp(() async => _seed(sessionBuilder.build()));

    test('administrador com código válido recebe JWT com role admin e sem microárea', () async {
      final session = sessionBuilder.build();
      final agora = DateTime.now().toUtc();
      final user = await _servico(session, staff: true).login(
        matricula: _adminMatricula,
        password: _senha,
        totpCode: Totp.code(_segredo, agora),
        now: agora,
      );
      expect(user.id, _adminId);
      expect(user.role, UserRole.admin);
      expect(user.microAreaId, isNull);

      final token = AlertRuntime.instance.auth.issueToken(user);
      final payload = _payload(token);
      expect(payload['role'], 'admin');
      expect(payload.containsKey('micro_area_id'), isTrue);
      expect(payload['micro_area_id'], isNull);

      final linha = (await UserCredential.db.findFirstRow(
        session,
        where: (t) => t.userId.equals(UuidValue.fromString(_adminId)),
      ))!;
      expect(linha.totpLastStep, Totp.stepOf(agora));
    });

    test('administrador sem código recebe MfaRequiredException', () async {
      await expectLater(
        _servico(sessionBuilder.build(), staff: true)
            .login(matricula: _adminMatricula, password: _senha),
        throwsA(isA<MfaRequiredException>()),
      );
    });

    test('matrícula de ACS no login do staff é recusada com a mensagem genérica', () async {
      await expectLater(
        _servico(sessionBuilder.build(), staff: true).login(
          matricula: _acsMatricula,
          password: _senha,
          totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
        ),
        throwsA(isA<AuthenticationFailedException>()
            .having((e) => e.message, 'message', _mensagemGenerica)),
      );
    });

    test('matrícula de staff no login do ACS é recusada com a mensagem genérica', () async {
      await expectLater(
        _servico(sessionBuilder.build(), staff: false).login(
          matricula: _adminMatricula,
          password: _senha,
          totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
        ),
        throwsA(isA<AuthenticationFailedException>()
            .having((e) => e.message, 'message', _mensagemGenerica)),
      );
    });

    test('usuário admin com linha em acs não entra pelo login do ACS', () async {
      // Um admin que (por erro de cadastro) tem matrícula em `acs`: o store do
      // ACS só devolve linha de papel `acs`, então ele é "inexistente" ali.
      final session = sessionBuilder.build();
      await Acs.db.insertRow(
        session,
        Acs(
          id: UuidValue.fromString(_adminId),
          enrollmentId: 'ACS-ADM-001',
          ubsId: UuidValue.fromString(_ubsId),
          active: true,
        ),
      );
      final store = OrmAcsCredentialStore(session: () => session);
      expect(await store.findByEnrollmentId('ACS-ADM-001'), isNull);
      // A matrícula de ACS legítima continua sendo encontrada, com papel acs.
      expect((await store.findByEnrollmentId(_acsMatricula))?.role, UserRole.acs);
    });

    test('o store do staff devolve o papel gravado em users', () async {
      final record = await OrmAcsCredentialStore(session: () => sessionBuilder.build(), staff: true)
          .findByEnrollmentId(_adminMatricula);
      expect(record, isNotNull);
      expect(record!.role, UserRole.admin);
      expect(record.microAreaId, isNull);
      expect(record.active, isTrue);
      expect(record.totp?.enabled, isTrue);
    });
  });
}
