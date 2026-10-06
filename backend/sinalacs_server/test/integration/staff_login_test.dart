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
    StaffAccount(
      id: UuidValue.fromString(_adminId),
      enrollmentId: _adminMatricula,
      active: true,
    ),
  );
  await AlertRuntimeHarness.store(session).saveCredential(
    _adminId,
    await AlertRuntimeHarness.hasher.derive(_senha),
    now,
  );
  final sealed = await HealthCipherTotpVault(
    AlertRuntime.instance.healthDataCipher,
  ).seal(_segredo);
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
  await AlertRuntimeHarness.store(session).saveCredential(
    _acsId,
    await AlertRuntimeHarness.hasher.derive(_senha),
    now,
  );
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

/// Decodifica base32 (RFC 4648, sem padding) como o app autenticador faz com
/// o segredo devolvido por `beginStaffTotpEnrollment`.
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

/// O seed grava o admin com MFA ativa; a ativação pelo endpoint parte de um
/// admin sem MFA, então zera as colunas de TOTP.
Future<void> _semMfa(Session session) async {
  final credencial = (await UserCredential.db.findFirstRow(
    session,
    where: (t) => t.userId.equals(UuidValue.fromString(_adminId)),
  ))!;
  await UserCredential.db.updateRow(
    session,
    credencial
      ..totpSecretEncrypted = null
      ..totpKeyVersion = null
      ..totpEnabledAt = null
      ..totpLastStep = null,
  );
}

Future<UserCredential> _credencialAdmin(Session session) async =>
    (await UserCredential.db.findFirstRow(
      session,
      where: (t) => t.userId.equals(UuidValue.fromString(_adminId)),
    ))!;

Map<String, dynamic> _payload(String token) =>
    jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(token.split('.')[1])),
          ),
        )
        as Map<String, dynamic>;

void main() {
  withServerpod('Dado o login institucional do staff do backoffice (#39)', (
    sessionBuilder,
    endpoints,
  ) {
    setUp(() async => _seed(sessionBuilder.build()));

    test(
      'administrador com código válido recebe JWT com role admin e sem microárea',
      () async {
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
      },
    );

    test('administrador sem código recebe MfaRequiredException', () async {
      await expectLater(
        _servico(
          sessionBuilder.build(),
          staff: true,
        ).login(matricula: _adminMatricula, password: _senha),
        throwsA(isA<MfaRequiredException>()),
      );
    });

    test(
      'matrícula de ACS no login do staff é recusada com a mensagem genérica',
      () async {
        await expectLater(
          _servico(sessionBuilder.build(), staff: true).login(
            matricula: _acsMatricula,
            password: _senha,
            totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
          ),
          throwsA(
            isA<AuthenticationFailedException>().having(
              (e) => e.message,
              'message',
              _mensagemGenerica,
            ),
          ),
        );
      },
    );

    test(
      'matrícula de staff no login do ACS é recusada com a mensagem genérica',
      () async {
        await expectLater(
          _servico(sessionBuilder.build(), staff: false).login(
            matricula: _adminMatricula,
            password: _senha,
            totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
          ),
          throwsA(
            isA<AuthenticationFailedException>().having(
              (e) => e.message,
              'message',
              _mensagemGenerica,
            ),
          ),
        );
      },
    );

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
      expect(
        (await store.findByEnrollmentId(_acsMatricula))?.role,
        UserRole.acs,
      );
    });

    test('o store do staff devolve o papel gravado em users', () async {
      final record = await OrmAcsCredentialStore(
        session: () => sessionBuilder.build(),
        staff: true,
      ).findByEnrollmentId(_adminMatricula);
      expect(record, isNotNull);
      expect(record!.role, UserRole.admin);
      expect(record.microAreaId, isNull);
      expect(record.active, isTrue);
      expect(record.totp?.enabled, isTrue);
    });

    test(
      'auth.loginStaff com credenciais e código certos devolve só o JWT de 15 min',
      () async {
        final agora = DateTime.now().toUtc();
        final result = await endpoints.auth.loginStaff(
          sessionBuilder,
          matricula: _adminMatricula,
          password: _senha,
          totpCode: Totp.code(_segredo, agora),
        );
        expect(result.tokenType, 'Bearer');
        expect(result.refreshToken, isNull);
        expect(result.uploadToken, isNull);
        final user = AlertRuntimeHarness.verify(result.accessToken)!;
        expect(user.id, _adminId);
        expect(user.role, UserRole.admin);
        expect(user.microAreaId, isNull);
        expect(user.deviceId, InstitutionalAuthService.deviceIdAbsent);
        expect(
          AlertRuntimeHarness.tokenLifetime(result.accessToken),
          const Duration(minutes: 15),
        );
      },
    );

    test(
      'auth.loginStaff grava em audit_logs o recurso staff_session, não session',
      () async {
        await endpoints.auth.loginStaff(
          sessionBuilder,
          matricula: _adminMatricula,
          password: _senha,
          totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
        );
        final linhas = await AuditLog.db.find(
          sessionBuilder.build(),
          where: (t) =>
              t.userId.equals(UuidValue.fromString(_adminId)) &
              t.actionType.equals('login'),
        );
        expect(linhas.map((l) => l.result), contains('granted'));
        expect(linhas.map((l) => l.resourceType), everyElement('staff_session'));
      },
    );

    test('auth.loginStaff sem código recebe MfaRequiredException', () async {
      await expectLater(
        endpoints.auth.loginStaff(
          sessionBuilder,
          matricula: _adminMatricula,
          password: _senha,
        ),
        throwsA(isA<MfaRequiredException>()),
      );
    });

    test(
      'cinco senhas erradas bloqueiam a conta do staff (reuso do bloqueio)',
      () async {
        for (var i = 0; i < InstitutionalAuthService.maxFailedAttempts; i++) {
          await expectLater(
            endpoints.auth.loginStaff(
              sessionBuilder,
              matricula: _adminMatricula,
              password: 'errada',
            ),
            throwsA(isA<AuthenticationFailedException>()),
          );
        }
        final credencial = (await UserCredential.db.findFirstRow(
          sessionBuilder.build(),
          where: (t) => t.userId.equals(UuidValue.fromString(_adminId)),
        ))!;
        expect(
          credencial.failedAttempts,
          InstitutionalAuthService.maxFailedAttempts,
        );
        expect(credencial.lockedUntil, isNotNull);
        // Bloqueada: nem a senha certa com o código certo entra.
        await expectLater(
          endpoints.auth.loginStaff(
            sessionBuilder,
            matricula: _adminMatricula,
            password: _senha,
            totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
          ),
          throwsA(isA<AuthenticationFailedException>()),
        );
      },
    );

    test(
      'token de admin é recusado por um caminho só de ACS (patients.listMicroArea)',
      () async {
        final result = await endpoints.auth.loginStaff(
          sessionBuilder,
          matricula: _adminMatricula,
          password: _senha,
          totpCode: Totp.code(_segredo, DateTime.now().toUtc()),
        );
        await expectLater(
          endpoints.patients.listMicroArea(
            sessionBuilder,
            accessToken: result.accessToken,
          ),
          throwsA(isA<AlertPermissionException>()),
        );
      },
    );

    group('ativação de MFA do staff pelo endpoint', () {
      test('begin devolve segredo e URI otpauth e não ativa a MFA', () async {
        final session = sessionBuilder.build();
        await _semMfa(session);

        final inicio = await endpoints.auth.beginStaffTotpEnrollment(
          sessionBuilder,
          matricula: _adminMatricula,
          password: _senha,
        );

        expect(inicio.secretBase32, isNotEmpty);
        expect(inicio.otpauthUri, startsWith('otpauth://totp/'));
        final cred = await _credencialAdmin(session);
        expect(
          cred.totpSecretEncrypted,
          isNotNull,
          reason: 'segredo pendente gravado',
        );
        expect(
          cred.totpEnabledAt,
          isNull,
          reason: 'MFA só vale depois do confirm',
        );
      });

      test(
        'confirm com código certo ativa; depois disso loginStaff exige o código',
        () async {
          final session = sessionBuilder.build();
          await _semMfa(session);
          final inicio = await endpoints.auth.beginStaffTotpEnrollment(
            sessionBuilder,
            matricula: _adminMatricula,
            password: _senha,
          );
          final codigo = Totp.code(
            _deBase32(inicio.secretBase32),
            DateTime.now().toUtc(),
          );

          await endpoints.auth.confirmStaffTotpEnrollment(
            sessionBuilder,
            matricula: _adminMatricula,
            password: _senha,
            code: codigo,
          );

          expect((await _credencialAdmin(session)).totpEnabledAt, isNotNull);
          await expectLater(
            endpoints.auth.loginStaff(
              sessionBuilder,
              matricula: _adminMatricula,
              password: _senha,
            ),
            throwsA(isA<MfaRequiredException>()),
          );
        },
      );

      test(
        'confirm com código errado não ativa a MFA e conta uma tentativa',
        () async {
          final session = sessionBuilder.build();
          await _semMfa(session);
          final inicio = await endpoints.auth.beginStaffTotpEnrollment(
            sessionBuilder,
            matricula: _adminMatricula,
            password: _senha,
          );
          // Código garantidamente diferente do válido (e dos passos vizinhos).
          final certo = Totp.code(
            _deBase32(inicio.secretBase32),
            DateTime.now().toUtc(),
          );
          final errado = certo == '000000' ? '111111' : '000000';

          await expectLater(
            endpoints.auth.confirmStaffTotpEnrollment(
              sessionBuilder,
              matricula: _adminMatricula,
              password: _senha,
              code: errado,
            ),
            throwsA(isA<AuthenticationFailedException>()),
          );

          final cred = await _credencialAdmin(session);
          expect(cred.totpEnabledAt, isNull);
          expect(cred.failedAttempts, 1);
        },
      );

      test(
        'begin com senha errada é recusado com a mensagem genérica',
        () async {
          await _semMfa(sessionBuilder.build());
          await expectLater(
            endpoints.auth.beginStaffTotpEnrollment(
              sessionBuilder,
              matricula: _adminMatricula,
              password: 'senha-errada',
            ),
            throwsA(
              isA<AuthenticationFailedException>().having(
                (e) => e.message,
                'message',
                _mensagemGenerica,
              ),
            ),
          );
        },
      );

      test(
        'begin com matrícula de ACS é recusado como matrícula inexistente',
        () async {
          await expectLater(
            endpoints.auth.beginStaffTotpEnrollment(
              sessionBuilder,
              matricula: _acsMatricula,
              password: _senha,
            ),
            throwsA(
              isA<AuthenticationFailedException>().having(
                (e) => e.message,
                'message',
                _mensagemGenerica,
              ),
            ),
          );
        },
      );
    });
  });
}
