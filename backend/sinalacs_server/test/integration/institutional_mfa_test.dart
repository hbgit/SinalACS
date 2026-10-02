import 'dart:typed_data';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
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

      expect(await store.registerStep(_acsId, 100), isTrue);
      expect((await _linha(session)).totpLastStep, 100);

      // Mesmo passo e passo menor: nada muda, e o store diz que não gravou.
      expect(await store.registerStep(_acsId, 100), isFalse);
      expect(await store.registerStep(_acsId, 99), isFalse);
      expect((await _linha(session)).totpLastStep, 100);

      expect(await store.registerStep(_acsId, 101), isTrue);
      expect((await _linha(session)).totpLastStep, 101);
    });

    test('saveSecret não sobrescreve MFA ativa; enable só ativa o segredo pendente que conferiu',
        () async {
      final session = sessionBuilder.build();
      final store = OrmAcsCredentialStore(session: () => session);
      const a = SealedSecret(ciphertextBase64: 'cifra-sintetica-a', keyVersion: 1);
      const b = SealedSecret(ciphertextBase64: 'cifra-sintetica-b', keyVersion: 1);
      final at = DateTime.now().toUtc();

      expect(await store.saveSecret(_acsId, a, at), isTrue);
      // Um novo início trocou o segredo: o código do antigo não ativa o novo.
      expect(await store.saveSecret(_acsId, b, at), isTrue);
      expect(await store.enable(_acsId, a, 10, at), isFalse);
      expect((await _linha(session)).totpEnabledAt, isNull);

      expect(await store.enable(_acsId, b, 10, at), isTrue);
      // Ativa: segunda confirmação e novo início são recusados pela linha.
      expect(await store.enable(_acsId, b, 11, at), isFalse);
      expect(await store.saveSecret(_acsId, a, at), isFalse);
      final linha = await _linha(session);
      expect(linha.totpSecretEncrypted, b.ciphertextBase64);
      expect(linha.totpLastStep, 10);
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

  // Concorrência de verdade exige o rollback DESLIGADO: com ele, todas as
  // `Session` do harness dividem o mesmo `TransactionManager` e chamadas
  // simultâneas são recusadas (ver o grupo "rajada" de
  // `institutional_login_test.dart`). Sem rollback, cada tentativa abre a sua
  // conexão. Pelo serviço com store ORM e cofre reais, e trilha de mentira:
  // auditoria commitada quebraria a cadeia que outras suítes conferem.
  withServerpod(
    'Dada a MFA por TOTP, sem rollback automático (concorrência)',
    (sessionBuilder, endpoints) {
      test('o mesmo código válido em requisições simultâneas abre UMA sessão só', () async {
        await _seedCorrida(sessionBuilder.build());
        try {
          final segredo = await _ativarMfaCorrida(sessionBuilder);
          final codigo = Totp.code(
            segredo,
            DateTime.now().toUtc().add(const Duration(seconds: Totp.period)),
          );

          final resultados = await Future.wait([
            for (var i = 0; i < _concorrentes; i++)
              _servicoCorrida(sessionBuilder)
                  .login(matricula: _corridaMatricula, password: _senha, totpCode: codigo)
                  .then<Object?>((u) => u, onError: (Object e) => e),
          ]);

          expect(resultados.whereType<AuthenticatedUser>(), hasLength(1),
              reason: 'RFC 6238 §5.2: um código validado não vale de novo');
          expect(
            resultados.where((r) => r is! AuthenticatedUser),
            everyElement(isA<AuthenticationFailedException>()),
          );
        } finally {
          await _limparCorrida(sessionBuilder.build());
        }
      });

      test('a mesma confirmação em requisições simultâneas ativa UMA vez só', () async {
        await _seedCorrida(sessionBuilder.build());
        try {
          final inicio = await _servicoCorrida(sessionBuilder)
              .beginTotpEnrollment(matricula: _corridaMatricula, password: _senha);
          final codigo = Totp.code(_deBase32(inicio.secretBase32), DateTime.now().toUtc());

          final resultados = await Future.wait([
            for (var i = 0; i < _concorrentes; i++)
              _servicoCorrida(sessionBuilder)
                  .confirmTotpEnrollment(matricula: _corridaMatricula, password: _senha, code: codigo)
                  .then<Object?>((_) => 'ativou', onError: (Object e) => e),
          ]);

          expect(resultados.where((r) => r == 'ativou'), hasLength(1));
          expect(
            resultados.where((r) => r != 'ativou'),
            everyElement(isA<AuthenticationFailedException>()),
          );
        } finally {
          await _limparCorrida(sessionBuilder.build());
        }
      });
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}

const _concorrentes = 5;
const _corridaAcsId = '00000000-0000-4000-8000-000000000091';
const _corridaMicroAreaId = '00000000-0000-4000-8000-000000000092';
const _corridaUbsId = '00000000-0000-4000-8000-000000000093';
const _corridaMatricula = 'ACS-MFA-CORRIDA-001';

/// Uma `Session` por chamada, como no servidor: conexões independentes.
InstitutionalAuthService _servicoCorrida(TestSessionBuilder sessionBuilder) {
  final store = OrmAcsCredentialStore(session: () => sessionBuilder.build());
  return InstitutionalAuthService(
    store: store,
    hasher: AlertRuntimeHarness.hasher,
    audit: _SemAuditoria(),
    totpStore: store,
    vault: HealthCipherTotpVault(AlertRuntime.instance.healthDataCipher),
  );
}

/// Ativa a MFA (begin + confirm, em sequência) e devolve o segredo.
Future<Uint8List> _ativarMfaCorrida(TestSessionBuilder sessionBuilder) async {
  final inicio = await _servicoCorrida(sessionBuilder)
      .beginTotpEnrollment(matricula: _corridaMatricula, password: _senha);
  final segredo = _deBase32(inicio.secretBase32);
  await _servicoCorrida(sessionBuilder).confirmTotpEnrollment(
    matricula: _corridaMatricula,
    password: _senha,
    code: Totp.code(segredo, DateTime.now().toUtc()),
  );
  return segredo;
}

/// Idempotente: limpa primeiro, para uma execução que morreu no meio não
/// deixar chave duplicada.
Future<void> _seedCorrida(Session session) async {
  await _limparCorrida(session);
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_corridaUbsId),
      name: 'UBS MFA Corrida',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_corridaMicroAreaId),
      name: 'Microárea MFA Corrida',
      ubsId: UuidValue.fromString(_corridaUbsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_corridaAcsId),
      cpfHash: 'development-acs-mfa-corrida',
      name: 'ACS de desenvolvimento (MFA corrida)',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_corridaMicroAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_corridaAcsId),
      enrollmentId: _corridaMatricula,
      ubsId: UuidValue.fromString(_corridaUbsId),
      active: true,
    ),
  );
  await AlertRuntimeHarness.store(session).saveCredential(
        _corridaAcsId,
        await AlertRuntimeHarness.hasher.derive(_senha),
        now,
      );
}

Future<void> _limparCorrida(Session session) async {
  final id = UuidValue.fromString(_corridaAcsId);
  await UserCredential.db.deleteWhere(session, where: (t) => t.userId.equals(id));
  await Acs.db.deleteWhere(session, where: (t) => t.id.equals(id));
  await User.db.deleteWhere(session, where: (t) => t.id.equals(id));
  await MicroArea.db.deleteWhere(
    session,
    where: (t) => t.id.equals(UuidValue.fromString(_corridaMicroAreaId)),
  );
  await Ubs.db.deleteWhere(session, where: (t) => t.id.equals(UuidValue.fromString(_corridaUbsId)));
}
