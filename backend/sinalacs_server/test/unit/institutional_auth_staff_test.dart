import 'dart:math';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

import '../support/institutional_auth_fixtures.dart';

/// Login institucional por audiência (#39): o mesmo serviço atende o ACS
/// (com território) e o staff do backoffice (coordenador/administrador, sem
/// território e com MFA sempre obrigatória). Dados sintéticos.
const _codigo = 'ABCD-EFGH-JKLM-NPQR-STUV-WXYZ-23';
const _mensagemCodigo = 'Código de ativação inválido ou expirado.';
const _staffId = '00000000-0000-4000-8000-000000000090';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _matricula = 'ADM-001';
const _senha = 'senha-sintetica-de-teste';
const _mensagemGenerica = 'Matrícula ou senha inválidos.';

void main() {
  final hasher = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);
  final cofre = FakeTotpVault();
  final segredo = Uint8List.fromList(List<int>.generate(20, (i) => i + 1));
  final t0 = DateTime.utc(2026, 10, 6, 12);

  Future<({InstitutionalAuthService servico, FakeCredentialStore store, RecordingAudit audit, FakeStaffActivationStore ativacao})>
      montar({
    bool comCodigo = true,
    CredentialAudience audience = CredentialAudience.staff,
    UserRole role = UserRole.admin,
    String? microAreaId,
    bool active = true,
    bool comMfa = true,
    bool exigir = false,
    String acsId = _staffId,
  }) async {
    final store = FakeCredentialStore(
      AcsCredentialRecord(
        acsId: acsId,
        microAreaId: microAreaId,
        active: active,
        role: role,
        digest: await hasher.derive(_senha),
        failedAttempts: 0,
        lockedUntil: null,
        totp: comMfa
            ? TotpEnrollment(sealed: await cofre.seal(segredo), enabled: true, lastStep: null)
            : null,
      ),
      matricula: _matricula,
    );
    final audit = RecordingAudit();
    final ativacao = FakeStaffActivationStore();
    if (comCodigo) {
      await ativacao.issue(
        acsId,
        codeHash: StaffActivationCode.hash(_codigo),
        expiresAt: t0.add(StaffActivationCode.defaultValidity),
        issuedBy: 'operador',
        at: t0,
      );
    }
    final servico = InstitutionalAuthService(
      store: store,
      hasher: hasher,
      audit: audit,
      totpStore: store,
      activationStore: ativacao,
      vault: cofre,
      requireMfa: exigir,
      audience: audience,
      random: Random(7),
    );
    return (servico: servico, store: store, audit: audit, ativacao: ativacao);
  }

  test('o papel do registro vale acs por omissão (os fakes antigos não mudam)', () {
    const record = AcsCredentialRecord(
      acsId: _acsId,
      microAreaId: _microAreaId,
      active: true,
      digest: PasswordDigestStub.value,
      failedAttempts: 0,
      lockedUntil: null,
    );
    expect(record.role, UserRole.acs);
  });

  group('audiência staff', () {
    test('sem MFA ativa recebe MfaEnrollmentRequired mesmo com requireMfa=false', () async {
      final m = await montar(comMfa: false, exigir: false);
      await expectLater(
        m.servico.login(matricula: _matricula, password: _senha, now: t0),
        throwsA(isA<MfaEnrollmentRequiredException>()),
      );
      expect(m.audit.results, contains('denied_mfa_not_enrolled'));
      expect(m.store.successfulLogins, 0);
    });

    test('com MFA ativa e código válido recebe sessão sem microárea e com o papel da conta',
        () async {
      for (final role in [UserRole.admin, UserRole.coordinator]) {
        final m = await montar(role: role);
        final user = await m.servico.login(
          matricula: _matricula,
          password: _senha,
          totpCode: Totp.code(segredo, t0),
          now: t0,
        );
        expect(user.id, _staffId);
        expect(user.role, role);
        expect(user.microAreaId, isNull);
        expect(m.audit.results, contains('granted'));
      }
    });

    test('eventos de login do staff gravam o recurso staff_session', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: _matricula, password: 'outra', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      await m.servico.login(
        matricula: _matricula,
        password: _senha,
        totpCode: Totp.code(segredo, t0),
        now: t0,
      );
      expect(m.audit.results, ['denied_credentials', 'granted']);
      expect(m.audit.resourceTypes, everyElement('staff_session'));
      expect(m.audit.events.map((e) => e.actionType), everyElement('login'));
    });

    test('não exige microárea (staff não tem território)', () async {
      final m = await montar(microAreaId: null);
      final user = await m.servico.login(
        matricula: _matricula,
        password: _senha,
        totpCode: Totp.code(segredo, t0),
        now: t0,
      );
      expect(user.microAreaId, isNull);
      expect(m.audit.results, isNot(contains('denied_no_territory')));
    });

    test('mesmo com microárea na linha, a sessão do staff sai sem microárea', () async {
      final m = await montar(microAreaId: _microAreaId);
      final user = await m.servico.login(
        matricula: _matricula,
        password: _senha,
        totpCode: Totp.code(segredo, t0),
        now: t0,
      );
      expect(user.microAreaId, isNull);
    });

    test('conta cujo papel não é de staff é recusada com a mensagem genérica', () async {
      for (final role in [UserRole.acs, UserRole.patient]) {
        final m = await montar(role: role);
        await expectLater(
          m.servico.login(
            matricula: _matricula,
            password: _senha,
            totpCode: Totp.code(segredo, t0),
            now: t0,
          ),
          throwsA(isA<AuthenticationFailedException>()
              .having((e) => e.message, 'message', _mensagemGenerica)),
        );
        expect(m.audit.results, contains('denied_role'));
        expect(m.store.successfulLogins, 0);
      }
    });

    test('papel errado com senha errada não revela o papel (só denied_credentials)', () async {
      final m = await montar(role: UserRole.acs);
      await expectLater(
        m.servico.login(matricula: _matricula, password: 'errada', now: t0),
        throwsA(isA<AuthenticationFailedException>()
            .having((e) => e.message, 'message', _mensagemGenerica)),
      );
      expect(m.audit.results, ['denied_credentials']);
      expect(m.store.record.failedAttempts, 1);
    });

    test('conta de staff inativa é recusada', () async {
      final m = await montar(active: false);
      await expectLater(
        m.servico.login(
          matricula: _matricula,
          password: _senha,
          totpCode: Totp.code(segredo, t0),
          now: t0,
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.audit.results, contains('denied_inactive'));
      expect(m.store.successfulLogins, 0);
    });

    test('código TOTP errado conta tentativa também para o staff', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: _matricula, password: _senha, totpCode: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.record.failedAttempts, 1);
      expect(m.audit.results, contains('denied_totp'));
    });

    test('a ativação da MFA também recusa papel que não é de staff', () async {
      final m = await montar(role: UserRole.acs, comMfa: false);
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: _matricula, password: _senha, now: t0),
        throwsA(isA<AuthenticationFailedException>()
            .having((e) => e.message, 'message', _mensagemGenerica)),
      );
      expect(m.store.record.totp, isNull);
    });

    test('a ativação da MFA do staff não exige microárea', () async {
      final m = await montar(comMfa: false);
      final inicio =
          await m.servico.beginTotpEnrollment(
              matricula: _matricula, password: _senha, activationCode: _codigo, now: t0);
      expect(inicio.secretBase32, isNotEmpty);
      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      await m.servico.confirmTotpEnrollment(
        matricula: _matricula,
        password: _senha,
        activationCode: _codigo,
        code: Totp.code(segredoSorteado, t0),
        now: t0,
      );
      expect(m.store.record.totp!.enabled, isTrue);
    });
  });

  group('código de ativação do staff (#48)', () {
    Matcher recusa() => throwsA(isA<AuthenticationFailedException>()
        .having((e) => e.message, 'message', _mensagemCodigo));

    test('begin sem código é recusado com a mensagem única e conta falha', () async {
      final m = await montar(comMfa: false);
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: _matricula, password: _senha, now: t0),
        recusa(),
      );
      expect(m.store.record.failedAttempts, 1);
      expect(m.store.record.totp, isNull);
      expect(m.audit.results, contains('denied_staff_activation_code'));
    });

    test('begin com código errado é recusado e não grava segredo', () async {
      final m = await montar(comMfa: false);
      await expectLater(
        m.servico.beginTotpEnrollment(
            matricula: _matricula, password: _senha, activationCode: 'ZZZZ-ZZZZ', now: t0),
        recusa(),
      );
      expect(m.store.record.totp, isNull);
    });

    test('begin com código expirado (1 s depois) é recusado', () async {
      final m = await montar(comMfa: false);
      await expectLater(
        m.servico.beginTotpEnrollment(
          matricula: _matricula,
          password: _senha,
          activationCode: _codigo,
          now: t0.add(StaffActivationCode.defaultValidity).add(const Duration(seconds: 1)),
        ),
        recusa(),
      );
    });

    test('begin sem código emitido (nunca emitido ou já consumido) é recusado', () async {
      final m = await montar(comMfa: false, comCodigo: false);
      await expectLater(
        m.servico.beginTotpEnrollment(
            matricula: _matricula, password: _senha, activationCode: _codigo, now: t0),
        recusa(),
      );
    });

    test('begin com o código certo devolve segredo; repetir com o mesmo código também', () async {
      final m = await montar(comMfa: false);
      final a = await m.servico.beginTotpEnrollment(
          matricula: _matricula, password: _senha, activationCode: _codigo, now: t0);
      final b = await m.servico.beginTotpEnrollment(
          matricula: _matricula, password: _senha, activationCode: _codigo, now: t0);
      expect(a.secretBase32, isNotEmpty);
      expect(b.secretBase32, isNotEmpty);
    });

    test('código com minúsculas, espaços e hífens vale como o original', () async {
      final m = await montar(comMfa: false);
      final inicio = await m.servico.beginTotpEnrollment(
        matricula: _matricula,
        password: _senha,
        activationCode: _codigo.toLowerCase().replaceAll('-', ' '),
        now: t0,
      );
      expect(inicio.secretBase32, isNotEmpty);
    });

    test('confirm sem o código é recusado, mesmo com o TOTP certo', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(
          matricula: _matricula, password: _senha, activationCode: _codigo, now: t0);
      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      await expectLater(
        m.servico.confirmTotpEnrollment(
          matricula: _matricula,
          password: _senha,
          code: Totp.code(segredoSorteado, t0),
          now: t0,
        ),
        recusa(),
      );
      expect(m.store.record.totp!.enabled, isFalse);
    });

    test('confirm com código e TOTP certos ativa a MFA e apaga o código', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(
          matricula: _matricula, password: _senha, activationCode: _codigo, now: t0);
      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      await m.servico.confirmTotpEnrollment(
        matricula: _matricula,
        password: _senha,
        activationCode: _codigo,
        code: Totp.code(segredoSorteado, t0),
        now: t0,
      );
      expect(m.store.record.totp!.enabled, isTrue);
      expect(await m.ativacao.find(_staffId), isNull);
    });

    test('depois da ativação o código não serve: a conta já tem MFA', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(
          matricula: _matricula, password: _senha, activationCode: _codigo, now: t0);
      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      await m.servico.confirmTotpEnrollment(
        matricula: _matricula,
        password: _senha,
        activationCode: _codigo,
        code: Totp.code(segredoSorteado, t0),
        now: t0,
      );
      await expectLater(
        m.servico.beginTotpEnrollment(
            matricula: _matricula, password: _senha, activationCode: _codigo, now: t0),
        throwsA(isA<AuthenticationFailedException>()
            .having((e) => e.message, 'message', contains('já está ativa'))),
      );
    });

    test('conta com MFA ativa recebe "já está ativa" mesmo com código errado', () async {
      final m = await montar();
      await expectLater(
        m.servico.beginTotpEnrollment(
            matricula: _matricula, password: _senha, activationCode: 'ERRADO', now: t0),
        throwsA(isA<AuthenticationFailedException>()
            .having((e) => e.message, 'message', contains('já está ativa'))),
      );
      expect(m.audit.results, isNot(contains('denied_staff_activation_code')));
    });

    test('reemitir invalida o código anterior', () async {
      final m = await montar(comMfa: false);
      await m.ativacao.issue(
        _staffId,
        codeHash: StaffActivationCode.hash('NOVO-CODIGO'),
        expiresAt: t0.add(StaffActivationCode.defaultValidity),
        issuedBy: 'operador-2',
        at: t0,
      );
      await expectLater(
        m.servico.beginTotpEnrollment(
            matricula: _matricula, password: _senha, activationCode: _codigo, now: t0),
        recusa(),
      );
    });

    test('5 códigos errados bloqueiam a conta', () async {
      final m = await montar(comMfa: false);
      for (var i = 0; i < InstitutionalAuthService.maxFailedAttempts; i++) {
        await expectLater(
          m.servico.beginTotpEnrollment(
              matricula: _matricula, password: _senha, activationCode: 'ERRADO', now: t0),
          throwsA(isA<AuthenticationFailedException>()),
        );
      }
      expect(m.store.record.lockedUntil, isNotNull);
    });
  });

  group('audiência acs (regressão)', () {
    test('continua exigindo microárea', () async {
      final m = await montar(
        audience: CredentialAudience.acs,
        role: UserRole.acs,
        microAreaId: null,
        comMfa: false,
        acsId: _acsId,
      );
      await expectLater(
        m.servico.login(matricula: _matricula, password: _senha, now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.audit.results, contains('denied_no_territory'));
    });

    test('continua emitindo papel acs com a microárea, e sem MFA obrigatória por omissão',
        () async {
      final m = await montar(
        audience: CredentialAudience.acs,
        role: UserRole.acs,
        microAreaId: _microAreaId,
        comMfa: false,
        acsId: _acsId,
      );
      final user = await m.servico.login(matricula: _matricula, password: _senha, now: t0);
      expect(user.role, UserRole.acs);
      expect(user.microAreaId, _microAreaId);
    });

    test('eventos de login do ACS continuam gravando o recurso session', () async {
      final m = await montar(
        audience: CredentialAudience.acs,
        role: UserRole.acs,
        microAreaId: _microAreaId,
        comMfa: false,
        acsId: _acsId,
      );
      await expectLater(
        m.servico.login(matricula: _matricula, password: 'outra', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      await m.servico.login(matricula: _matricula, password: _senha, now: t0);
      expect(m.audit.results, ['denied_credentials', 'granted']);
      expect(m.audit.resourceTypes, everyElement('session'));
    });

    test('a audiência por omissão do serviço é acs', () async {
      final store = FakeCredentialStore(
        AcsCredentialRecord(
          acsId: _acsId,
          microAreaId: null,
          active: true,
          digest: await hasher.derive(_senha),
          failedAttempts: 0,
          lockedUntil: null,
        ),
        matricula: _matricula,
      );
      final servico = InstitutionalAuthService(store: store, hasher: hasher, audit: RecordingAudit());
      expect(servico.audience, CredentialAudience.acs);
    });
  });
}

/// Digest constante só para o teste de construção do registro (nunca é
/// verificado contra senha nenhuma).
abstract final class PasswordDigestStub {
  static const value = PasswordDigest(
    hashBase64: 'AAAA',
    saltBase64: 'AAAA',
    memoryKb: 512,
    iterations: 1,
    parallelism: 1,
  );
}
