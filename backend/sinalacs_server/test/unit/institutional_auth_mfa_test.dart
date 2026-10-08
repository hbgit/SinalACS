import 'dart:math';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

import '../support/institutional_auth_fixtures.dart';

const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _senha = 'senha-sintetica-de-teste';

void main() {
  final hasher = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);
  final cofre = FakeTotpVault();
  final segredo = Uint8List.fromList(List<int>.generate(20, (i) => i + 1));
  final t0 = DateTime.utc(2026, 10, 2, 12);

  Future<({InstitutionalAuthService servico, FakeCredentialStore store})> montar({
    bool comMfa = true,
    bool exigir = false,
  }) async {
    final digest = await hasher.derive(_senha);
    final sealed = await cofre.seal(segredo);
    final store = FakeCredentialStore(AcsCredentialRecord(
      acsId: _acsId,
      microAreaId: _microAreaId,
      active: true,
      digest: digest,
      failedAttempts: 0,
      lockedUntil: null,
      totp: comMfa ? TotpEnrollment(sealed: sealed, enabled: true, lastStep: null) : null,
    ));
    final servico = InstitutionalAuthService(
      store: store,
      hasher: hasher,
      audit: RecordingAudit(),
      totpStore: store,
      vault: cofre,
      requireMfa: exigir,
      random: Random(7),
    );
    return (servico: servico, store: store);
  }

  group('login com MFA ativa', () {
    test('senha certa sem código → MfaRequiredException, sem contar tentativa', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, now: t0),
        throwsA(isA<MfaRequiredException>()),
      );
      expect(m.store.record.failedAttempts, 0);
    });

    test('senha certa + código certo → entra e grava o passo usado', () async {
      final m = await montar();
      final user = await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      expect(user.id, _acsId);
      expect(m.store.lastRegisteredStep, Totp.stepOf(t0));
    });

    test('o login do ACS com MFA continua auditado no recurso session (não staff_session)',
        () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      final audit = m.servico.audit as RecordingAudit;
      expect(audit.results, ['denied_totp', 'granted']);
      expect(audit.resourceTypes, everyElement('session'));
    });

    test('recusa o mesmo código usado duas vezes (replay)', () async {
      final m = await montar();
      final codigo = Totp.code(segredo, t0);
      await m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: codigo, now: t0);

      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: codigo, now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('código do passo SEGUINTE ainda entra depois de um login (relógio adiantado)', () async {
      final m = await montar();
      await m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      final proximo = t0.add(const Duration(seconds: 30));
      final user = await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, proximo), now: proximo);
      expect(user.id, _acsId);
    });

    test('código errado conta tentativa e tranca no 5º erro', () async {
      final m = await montar();
      for (var i = 0; i < 4; i++) {
        await expectLater(
          m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
          throwsA(isA<AuthenticationFailedException>()),
        );
      }
      expect(m.store.record.failedAttempts, 4);
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.record.lockedUntil, isNotNull);
    });

    test('código errado não consome o passo (o certo logo depois entra)', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.lastRegisteredStep, isNull);
      final user = await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      expect(user.id, _acsId);
    });

    test('o store não avançou o passo (outra requisição gravou antes) → recusa', () async {
      // Duas requisições com o mesmo código leram o mesmo lastStep e as duas
      // passaram no verify; só a primeira avança a linha. A segunda não pode
      // receber sessão (RFC 6238 §5.2: código já validado não vale de novo).
      final m = await montar();
      m.store.perdeCorrida = true;
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.successfulLogins, 0);
      expect(m.store.record.failedAttempts, 1);
    });

    test('senha errada continua dando a mensagem única, com ou sem código', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: 'errada', totpCode: Totp.code(segredo, t0), now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });
  });

  group('login sem MFA ativa', () {
    test('com REQUIRE_ACS_MFA desligado, entra só com a senha', () async {
      final m = await montar(comMfa: false);
      expect((await m.servico.login(matricula: 'ACS-001', password: _senha, now: t0)).id, _acsId);
    });

    test('com REQUIRE_ACS_MFA ligado, a senha certa recebe MfaEnrollmentRequiredException', () async {
      final m = await montar(comMfa: false, exigir: true);
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, now: t0),
        throwsA(isA<MfaEnrollmentRequiredException>()),
      );
    });

    test('enrollment começado e NÃO confirmado não vale: entra só com a senha', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      expect(m.store.record.totp!.enabled, isFalse);
      expect((await m.servico.login(matricula: 'ACS-001', password: _senha, now: t0)).id, _acsId);
    });
  });

  group('ativação', () {
    test('begin devolve segredo e URI; confirm com o código certo ativa', () async {
      final m = await montar(comMfa: false);
      final inicio = await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      expect(inicio.otpauthUri, startsWith('otpauth://totp/SinalACS:ACS-001?secret=${inicio.secretBase32}'));

      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      await m.servico.confirmTotpEnrollment(
        matricula: 'ACS-001',
        password: _senha,
        code: Totp.code(segredoSorteado, t0),
        now: t0,
      );
      expect(m.store.enabledCalls, 1);
      expect(m.store.record.totp!.enabled, isTrue);
    });

    test('confirm com código errado não ativa e conta tentativa', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      await expectLater(
        m.servico.confirmTotpEnrollment(matricula: 'ACS-001', password: _senha, code: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.enabledCalls, 0);
      expect(m.store.record.failedAttempts, 1);
    });

    test('confirm que perdeu a corrida (ativação já gravada por outra) é recusado', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      m.store.perdeCorrida = true;
      await expectLater(
        m.servico.confirmTotpEnrollment(
          matricula: 'ACS-001',
          password: _senha,
          code: Totp.code(segredoSorteado, t0),
          now: t0,
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.enabledCalls, 0);
      expect(m.store.record.failedAttempts, 1);
    });

    test('begin que perdeu a corrida para uma ativação concorrente é recusado', () async {
      final m = await montar(comMfa: false);
      m.store.perdeCorrida = true;
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('begin com senha errada é recusado como o login (mensagem única)', () async {
      final m = await montar(comMfa: false);
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: 'errada'),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('begin com MFA já ativa é recusado (redefinir exige a coordenação)', () async {
      final m = await montar();
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });
  });
}
