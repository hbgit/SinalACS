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

/// MFA por TOTP (RF07) contra Postgres real: prova que as quatro colunas
/// `totp*` de `user_credentials` são gravadas e relidas pelo
/// `OrmAcsCredentialStore` — o que o store falso do teste unitário não
/// alcança — e que o segredo passa pelo cofre de verdade
/// (`HealthCipherTotpVault`, AES-256-GCM) sem nunca ir em claro para a linha.
///
/// Dados sintéticos; ids próprios, distintos das outras suítes.
const _acsId = '00000000-0000-4000-8000-000000000081';
const _microAreaId = '00000000-0000-4000-8000-000000000082';
const _ubsId = '00000000-0000-4000-8000-000000000083';
const _matricula = 'ACS-MFA-001';
const _senha = 'senha-sintetica-de-teste';

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS MFA',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea MFA',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs-mfa',
      name: 'ACS de desenvolvimento (MFA)',
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
  await AlertRuntimeHarness.store(session).saveCredential(
        _acsId,
        await AlertRuntimeHarness.hasher.derive(_senha),
        now,
      );
}

Future<UserCredential> _linha(Session session) async => (await UserCredential.db.findFirstRow(
      session,
      where: (t) => t.userId.equals(UuidValue.fromString(_acsId)),
    ))!;

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

class _SemAuditoria extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

void main() {
  withServerpod('Dada a MFA por TOTP do login institucional (RF07)', (
    sessionBuilder,
    endpoints,
  ) {
    setUp(() async => _seed(sessionBuilder.build()));

    test('begin → confirm → login com código, e o replay é recusado', () async {
      final session = sessionBuilder.build();

      final inicio = await endpoints.auth.beginTotpEnrollment(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
      );
      final segredo = _deBase32(inicio.secretBase32);
      expect(segredo, hasLength(20));
      expect(Totp.base32(segredo), inicio.secretBase32);

      // Pendente: segredo cifrado na linha, MFA ainda não vale.
      final pendente = await _linha(session);
      expect(pendente.totpSecretEncrypted, isNotNull);
      expect(pendente.totpSecretEncrypted, isNot(contains(inicio.secretBase32)));
      expect(pendente.totpKeyVersion, isNotNull);
      expect(pendente.totpEnabledAt, isNull);
      expect(pendente.totpLastStep, isNull);

      // E pendente não bloqueia o login só com a senha.
      final semMfa = await endpoints.auth.loginInstitutional(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
      );
      expect(semMfa.accessToken, isNotEmpty);

      final agora = DateTime.now().toUtc();
      await endpoints.auth.confirmTotpEnrollment(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
        code: Totp.code(segredo, agora),
      );
      final ativa = await _linha(session);
      expect(ativa.totpEnabledAt, isNotNull);
      final passoDaAtivacao = ativa.totpLastStep;
      expect(passoDaAtivacao, isNotNull);

      // Ativa: a senha sozinha não entra mais.
      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
        ),
        throwsA(isA<MfaRequiredException>()),
      );

      // O código usado na ativação não serve para entrar (o passo dele já foi
      // gravado); o do passo seguinte serve — está dentro da janela de ±1.
      final codigoUsado = Totp.code(segredo, agora);
      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
          totpCode: codigoUsado,
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect((await _linha(session)).failedAttempts, 1);

      final proximo = agora.add(const Duration(seconds: Totp.period));
      final codigo = Totp.code(segredo, proximo);
      final login = await endpoints.auth.loginInstitutional(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
        totpCode: codigo,
      );
      expect(AlertRuntimeHarness.verify(login.accessToken)?.id, _acsId);
      final depois = await _linha(session);
      expect(depois.totpLastStep, Totp.stepOf(proximo));
      expect(depois.failedAttempts, 0);

      // Replay do código que acabou de entrar: recusado pelo passo gravado.
      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
          totpCode: codigo,
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // Com a MFA ativa, uma nova ativação é recusada e não troca o segredo.
      await expectLater(
        endpoints.auth.beginTotpEnrollment(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect((await _linha(session)).totpSecretEncrypted, ativa.totpSecretEncrypted);
    });

    test('registerStep só deixa o passo avançar, nunca voltar', () async {
      final session = sessionBuilder.build();
      final store = OrmAcsCredentialStore(session: () => session);

      await store.registerStep(_acsId, 100);
      expect((await _linha(session)).totpLastStep, 100);

      await store.registerStep(_acsId, 99);
      expect((await _linha(session)).totpLastStep, 100);

      await store.registerStep(_acsId, 101);
      expect((await _linha(session)).totpLastStep, 101);
    });

    test('com requireMfa ligado, ACS sem MFA ativa recebe MfaEnrollmentRequiredException',
        () async {
      final session = sessionBuilder.build();
      final store = OrmAcsCredentialStore(session: () => session);
      final servico = InstitutionalAuthService(
        store: store,
        hasher: AlertRuntimeHarness.hasher,
        audit: _SemAuditoria(),
        totpStore: store,
        vault: HealthCipherTotpVault(AlertRuntime.instance.healthDataCipher),
        requireMfa: true,
      );

      await expectLater(
        servico.login(matricula: _matricula, password: _senha),
        throwsA(isA<MfaEnrollmentRequiredException>()),
      );
      // Não é tentativa errada: a senha conferiu.
      expect((await _linha(session)).failedAttempts, 0);
    });
  });
}
