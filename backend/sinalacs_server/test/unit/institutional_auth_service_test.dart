import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _senha = 'senha-sintetica-de-teste';

/// Store em memória: o serviço é o que está sob teste, não o Postgres.
class _FakeStore implements AcsCredentialStore {
  _FakeStore({this.record});

  AcsCredentialRecord? record;
  final fieldsWritten = <String, Object?>{};

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async =>
      enrollmentId == 'ACS-001' ? record : null;

  @override
  Future<void> registerFailedAttempt(
    String acsId, {
    required int failedAttempts,
    required DateTime? lockedUntil,
  }) async {
    fieldsWritten['failedAttempts'] = failedAttempts;
    fieldsWritten['lockedUntil'] = lockedUntil;
    final current = record;
    if (current != null) {
      record = AcsCredentialRecord(
        acsId: current.acsId,
        microAreaId: current.microAreaId,
        active: current.active,
        digest: current.digest,
        failedAttempts: failedAttempts,
        lockedUntil: lockedUntil,
      );
    }
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    fieldsWritten['resetAt'] = at;
  }

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {
    fieldsWritten['saved'] = true;
  }
}

// `extends`, e não `implements`: `AuditTrail` é uma `abstract class` cujo
// `recordSafely` é herdado por todo implementador de propósito (ver o doc
// comment dele) — e `implements` obrigaria a reescrevê-lo aqui. Mesmo formato
// de `FakeAuditTrail` nos outros testes do repositório.
class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

/// Conta derivações e verificações no nível da interface.
///
/// É o único jeito de provar o custo do caminho da matrícula inexistente: a
/// asserção sobre a mensagem não distingue "derivou um hash e jogou fora" de
/// "não fez nada", e é justamente essa diferença que o relógio do atacante lê.
class _CountingHasher implements PasswordHasher {
  _CountingHasher(this._inner);

  final PasswordHasher _inner;
  int deriveCalls = 0;
  int matchCalls = 0;

  @override
  Future<PasswordDigest> derive(String password) {
    deriveCalls++;
    return _inner.derive(password);
  }

  @override
  Future<bool> matches(String password, PasswordDigest digest) {
    matchCalls++;
    return _inner.matches(password, digest);
  }
}

void main() {
  final hasher = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);

  Future<InstitutionalAuthService> build({
    bool active = true,
    String? microAreaId = _microAreaId,
    int failedAttempts = 0,
    DateTime? lockedUntil,
  }) async {
    final digest = await hasher.derive(_senha);
    return InstitutionalAuthService(
      store: _FakeStore(
        record: AcsCredentialRecord(
          acsId: _acsId,
          microAreaId: microAreaId,
          active: active,
          digest: digest,
          failedAttempts: failedAttempts,
          lockedUntil: lockedUntil,
        ),
      ),
      hasher: hasher,
      audit: _RecordingAudit(),
    );
  }

  group('login institucional', () {
    test('aceita matrícula e senha corretas e devolve ACS territorializado', () async {
      final service = await build();

      final user = await service.login(matricula: 'ACS-001', password: _senha);

      expect(user.id, _acsId);
      expect(user.role, UserRole.acs);
      expect(user.microAreaId, _microAreaId);
    });

    test('ignora espaços em volta da matrícula', () async {
      final service = await build();
      final user = await service.login(matricula: '  ACS-001  ', password: _senha);
      expect(user.id, _acsId);
    });

    test('recusa matrícula inexistente com a MESMA exceção da senha errada', () async {
      final service = await build();

      // `then<Object?>` explícito: sem ele o Dart exige que o `onError`
      // devolva `AuthenticatedUser`, e o handler de captura do erro não
      // compila em tempo de execução.
      final inexistente = await service
          .login(matricula: 'ACS-999', password: _senha)
          .then<Object?>((_) => null, onError: (Object error) => error);
      final senhaErrada = await service
          .login(matricula: 'ACS-001', password: 'outra')
          .then<Object?>((_) => null, onError: (Object error) => error);

      expect(inexistente, isA<AuthenticationFailedException>());
      expect(senhaErrada, isA<AuthenticationFailedException>());
      // A mensagem idêntica é o ponto: mensagens diferentes diriam quais
      // matrículas existem.
      expect(
        (inexistente! as AuthenticationFailedException).message,
        (senhaErrada! as AuthenticationFailedException).message,
      );
    });

    test('conta a tentativa errada sem bloquear antes do limite', () async {
      final service = await build(failedAttempts: 0);
      final store = service.store as _FakeStore;

      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra'),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(store.fieldsWritten['failedAttempts'], 1);
      expect(store.fieldsWritten['lockedUntil'], isNull);
    });

    test('bloqueia ao atingir o limite de tentativas', () async {
      final service = await build(failedAttempts: 4);
      final store = service.store as _FakeStore;
      final agora = DateTime.utc(2026, 9, 18, 12);

      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra', now: agora),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(store.fieldsWritten['failedAttempts'], 5);
      expect(
        store.fieldsWritten['lockedUntil'],
        agora.add(InstitutionalAuthService.lockDuration),
      );
    });

    test('recusa enquanto o bloqueio está ativo, sem recontar tentativa', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = await build(
        lockedUntil: agora.add(const Duration(minutes: 5)),
      );
      final store = service.store as _FakeStore;

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha, now: agora),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // Nem senha certa passa durante o bloqueio, e a tentativa recusada por
      // bloqueio não estende o castigo.
      expect(store.fieldsWritten['failedAttempts'], isNull);
      expect(store.fieldsWritten['lockedUntil'], isNull);
    });

    test('aceita de novo depois de o bloqueio vencer', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = await build(
        lockedUntil: agora.subtract(const Duration(minutes: 1)),
      );

      final user = await service.login(
        matricula: 'ACS-001',
        password: _senha,
        now: agora,
      );

      expect(user.id, _acsId);
    });

    test('zera o contador no login bem-sucedido', () async {
      final service = await build(failedAttempts: 3);
      final store = service.store as _FakeStore;
      final agora = DateTime.utc(2026, 9, 18, 12);

      await service.login(matricula: 'ACS-001', password: _senha, now: agora);

      expect(store.fieldsWritten['resetAt'], agora);
    });

    test('recusa ACS inativo — e só depois de a senha conferir', () async {
      final service = await build(active: false);

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(
          isA<AuthenticationFailedException>().having(
            (error) => error.message,
            'message',
            contains('inativo'),
          ),
        ),
      );
    });

    test('recusa ACS sem microárea', () async {
      final service = await build(microAreaId: null);

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('recusa matrícula ou senha em branco sem tocar no banco', () async {
      final service = await build();
      final store = service.store as _FakeStore;

      await expectLater(
        service.login(matricula: '   ', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(store.fieldsWritten, isEmpty);
    });

    test('marca o deviceId ausente em vez de inventar um', () async {
      final service = await build();
      final user = await service.login(matricula: 'ACS-001', password: _senha);

      // Mesma convenção de `orm_onboarding_store.dart`, que grava
      // 'nao-aplicavel-onboarding' em ipHash/userAgent: ausência explícita, e
      // não um valor fabricado que pareça medição.
      expect(user.deviceId, 'nao-aplicavel-login-institucional');
    });

    test('audita cada desfecho', () async {
      final service = await build();
      final audit = service.audit as _RecordingAudit;

      await service.login(matricula: 'ACS-001', password: _senha);
      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra'),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(
        audit.events.map((event) => event.result).toList(),
        ['granted', 'denied_credentials'],
      );
      expect(audit.events.every((event) => event.resourceType == 'session'), isTrue);
    });
  });

  group('superfície de segurança', () {
    /// A mensagem genérica medida na própria implementação, e não um literal:
    /// assim o teste continua medindo a propriedade ("é indistinguível") em
    /// vez da redação exata da frase.
    Future<String> mensagemGenerica() async {
      final service = await build();
      try {
        await service.login(matricula: 'ACS-001', password: 'outra');
      } on AuthenticationFailedException catch (error) {
        return error.message;
      }
      fail('senha errada deveria ter falhado');
    }

    test('deriva um hash descartado quando a matrícula não existe', () async {
      final contando = _CountingHasher(hasher);
      final service = InstitutionalAuthService(
        store: _FakeStore(),
        hasher: contando,
        audit: _RecordingAudit(),
      );

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // Sem a derivação descartada a resposta volta em microssegundos e o
      // relógio entrega a lista de matrículas que a mensagem única esconde.
      expect(contando.deriveCalls, 1);
      expect(contando.matchCalls, 0);
    });

    test('não revela a inatividade a quem não acertou a senha', () async {
      final generica = await mensagemGenerica();
      final service = await build(active: false);
      final audit = service.audit as _RecordingAudit;

      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra'),
        throwsA(
          isA<AuthenticationFailedException>().having(
            (error) => error.message,
            'message',
            generica,
          ),
        ),
      );
      expect(audit.events.single.result, 'denied_credentials');
    });

    test('não revela a ausência de território a quem não acertou a senha', () async {
      final generica = await mensagemGenerica();
      final service = await build(microAreaId: null);
      final audit = service.audit as _RecordingAudit;

      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra'),
        throwsA(
          isA<AuthenticationFailedException>().having(
            (error) => error.message,
            'message',
            generica,
          ),
        ),
      );
      expect(audit.events.single.result, 'denied_credentials');
    });

    test('recusa ACS sem microárea com mensagem própria, depois da senha', () async {
      final generica = await mensagemGenerica();
      final service = await build(microAreaId: null);
      final audit = service.audit as _RecordingAudit;

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(
          isA<AuthenticationFailedException>()
              .having((error) => error.message, 'message', isNot(generica))
              .having((error) => error.message, 'message', contains('microárea')),
        ),
      );
      expect(audit.events.single.result, 'denied_no_territory');
    });

    test('audita bloqueio, inatividade e ausência de território', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);

      final bloqueado = await build(
        lockedUntil: agora.add(const Duration(minutes: 5)),
      );
      await expectLater(
        bloqueado.login(matricula: 'ACS-001', password: _senha, now: agora),
        throwsA(isA<AuthenticationFailedException>()),
      );

      final inativo = await build(active: false);
      await expectLater(
        inativo.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );

      final semTerritorio = await build(microAreaId: null);
      await expectLater(
        semTerritorio.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // Um evento por desfecho, resultado distinto em cada um: a trilha tem
      // de dizer qual das recusas foi.
      final eventos = [
        (bloqueado.audit as _RecordingAudit).events.single,
        (inativo.audit as _RecordingAudit).events.single,
        (semTerritorio.audit as _RecordingAudit).events.single,
      ];
      expect(
        eventos.map((event) => event.result).toList(),
        ['denied_locked', 'denied_inactive', 'denied_no_territory'],
      );
      expect(
        eventos.map((event) => event.resourceType).toSet(),
        {'session'},
      );
    });

    test('linha corrompida é erro de servidor, não tentativa contada', () async {
      final service = await build();
      final store = service.store as _FakeStore;

      // As duas formas de corrupção que `matches` recusa lançando: salt curto
      // (ArgumentError) e base64 inválido (FormatException). Nenhuma pode
      // virar "senha errada" — converter a corrupção em tentativa contada
      // gastaria o acesso de um ACS por um defeito de dado, e cinco linhas
      // quebradas o bloqueariam sem atacante nenhum. As exceções sobem.
      store.record = AcsCredentialRecord(
        acsId: _acsId,
        microAreaId: _microAreaId,
        active: true,
        digest: const PasswordDigest(
          hashBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          saltBase64: 'AAAA',
          memoryKb: 512,
          iterations: 1,
          parallelism: 1,
        ),
        failedAttempts: 0,
        lockedUntil: null,
      );

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.fieldsWritten, isEmpty);

      final real = await hasher.derive(_senha);
      store.record = AcsCredentialRecord(
        acsId: _acsId,
        microAreaId: _microAreaId,
        active: true,
        digest: PasswordDigest(
          hashBase64: '###',
          saltBase64: real.saltBase64,
          memoryKb: real.memoryKb,
          iterations: real.iterations,
          parallelism: real.parallelism,
        ),
        failedAttempts: 0,
        lockedUntil: null,
      );

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<FormatException>()),
      );
      expect(store.fieldsWritten, isEmpty);
    });

    test('o login bem-sucedido reseta em vez de contar tentativa', () async {
      final service = await build(failedAttempts: 3);
      final store = service.store as _FakeStore;

      await service.login(matricula: 'ACS-001', password: _senha);

      // O par que importa: zera o contador E não grava tentativa falha. Sem a
      // segunda metade, uma implementação que contasse a tentativa antes de
      // conferir a senha passaria neste teste.
      expect(store.fieldsWritten.containsKey('failedAttempts'), isFalse);
      expect(store.fieldsWritten['resetAt'], isNotNull);
    });

    test('propaga o deviceId informado em vez do marcador', () async {
      final service = await build();

      final user = await service.login(
        matricula: 'ACS-001',
        password: _senha,
        deviceId: 'tablet-da-unidade-01',
      );

      expect(user.deviceId, 'tablet-da-unidade-01');
    });
  });
}
