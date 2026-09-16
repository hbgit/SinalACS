# Triagem Persistida e Identificada — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer `triage.evaluate` exigir autenticação, identificar o paciente pelo token e gravar cada triagem em `triage_sessions` com linha de auditoria.

**Architecture:** Um serviço de aplicação novo (`TriageSessionService`) envolve o `TriageEngine` já existente, aplica o papel, persiste por uma porta abstrata (`TriageSessionStore`) e audita por `AuditTrail`. A implementação ORM fica em `infrastructure/`, exatamente como `PatientDirectoryService`/`OrmPatientDirectoryStore`. O endpoint ganha um `accessToken` obrigatório e delega. O motor de risco **não muda** — ele continua puro e determinístico (INV-02); o que muda é que o resultado passa a ser gravado.

**Tech Stack:** Dart 3.8 · Serverpod 3.4.13 · PostgreSQL · `package:test`

**Spec:** [spec/validation_report.md](../../../spec/validation_report.md) — este plano fecha a lacuna **L-04** (§8, P0) e revive a tabela morta `triage_sessions` (§6).

## Global Constraints

- Idioma de documentação, comentários e mensagens de erro: **português**.
- **INV-02** — o risco vem SEMPRE de `TriageEngine.evaluate`. Nenhum campo de risco pode ser aceito do cliente, nem tornado editável.
- **INV-05** — `patientId` vem SEMPRE de `user.id` (o token). Nunca aceite `patientId` como parâmetro de método.
- **LGPD** — nenhum dado real de paciente em teste, log ou fixture. Use apenas os UUIDs sintéticos do seed (`00000000-0000-4000-8000-0000000000NN`).
- Nunca editar à mão nada em `lib/src/generated/` ou `migrations/` — rode `serverpod generate`.
- Nenhuma mudança de `.spy.yaml` de **tabela** neste plano, portanto **nenhuma migração nova**. `triage_sessions` já existe e já está migrada; ela só nunca teve escritor.
- A camada `application/` obtém `UuidValue` por `import 'package:serverpod/serverpod.dart' show UuidValue;`.
- Testes rodam de `backend/sinalacs_server`. Os de integração exigem `docker compose --profile test up -d postgres-test`.
- **Armadilha conhecida:** se `TEST_DATABASE_PASSWORD` do `.env` divergir do bloco `test:` de `config/passwords.yaml`, o Serverpod chama `exit(1)` sem esvaziar o stdout e a suíte morre com código 1 e **zero linhas de log**. Rode `./scripts/dev/bootstrap_env.sh --force`.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `lib/src/application/triage/triage_session_service.dart` (criar) | Porta `TriageSessionStore` + serviço que aplica papel, chama o motor, persiste e audita. |
| `lib/src/infrastructure/database/orm_triage_session_store.dart` (criar) | Implementação da porta sobre o ORM do Serverpod. |
| `lib/src/runtime/alert_runtime.dart` (modificar) | Fábrica `triageSessionServiceFor(session)`. |
| `lib/src/endpoints/triage_endpoint.dart` (modificar) | `accessToken` obrigatório; delega ao serviço; traduz `StateError` em `AlertPermissionException`. |
| `test/unit/triage_session_service_test.dart` (criar) | Motor, papel, `patientId` do token, auditoria, tolerância a auditoria fora do ar. |
| `test/integration/triage_session_persistence_test.dart` (criar) | Grava de verdade em Postgres e passa pelo endpoint. |
| `apps/patient/lib/core/network/backend_client.dart` (modificar) | Passa o token em `evaluateTriage`. |
| `apps/patient/integration_test/backend_connection_test.dart` (modificar) | Os testes de triagem passam a autenticar antes. |
| `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart` (modificar) | As duas chamadas diretas a `triage.evaluate` passam o token. |

**Nota de escopo:** `apps/patient/tool/live_check.dart` **não precisa de mudança** — ele usa uma única instância de `BackendClient`, faz `login()` na linha 32 e só chama `evaluateTriage` nas linhas 37 e 45.

---

### Task 1: Serviço de triagem persistida

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/triage/triage_session_service.dart`
- Test: `backend/sinalacs_server/test/unit/triage_session_service_test.dart`

**Interfaces:**
- Consumes: `TriageEngine.evaluate({required bool chestPain, difficultyBreathing, fever, persistentVomiting, bleeding, severeWeakness}) → RiskLevel` (de `lib/src/application/triage/triage_engine.dart`); `AuthenticatedUser {String id, UserRole role, String? microAreaId, String deviceId}`; `AuditTrail.recordSafely(AuditEvent)`; `TriageSession`, `TriageAnswer`, `RiskLevel`, `UserRole` (do protocolo gerado).
- Produces:
  - `abstract interface class TriageSessionStore { Future<TriageSession> insert(TriageSession session); }`
  - `class TriageSessionService` com construtor `({required TriageSessionStore store, required AuditTrail audit, TriageEngine engine = const TriageEngine(), DateTime Function()? clock})`
  - `Future<RiskLevel> evaluateAndRecord({required AuthenticatedUser user, required bool chestPain, required bool difficultyBreathing, required bool fever, required bool persistentVomiting, required bool bleeding, required bool severeWeakness})`

- [ ] **Step 1: Escrever o teste que falha**

Crie `backend/sinalacs_server/test/unit/triage_session_service_test.dart`:

```dart
import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

const _acs = AuthenticatedUser(
  id: _acsId,
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

class FakeTriageSessionStore implements TriageSessionStore {
  final List<TriageSession> saved = <TriageSession>[];

  @override
  Future<TriageSession> insert(TriageSession session) async {
    final stored = session.copyWith(
      id: UuidValue.fromString('00000000-0000-4000-8000-0000000000aa'),
    );
    saved.add(stored);
    return stored;
  }
}

/// Mesmo molde de `patient_directory_service_test.dart`.
class FakeAuditTrail extends AuditTrail {
  FakeAuditTrail({this.failOnRecord = false});

  final bool failOnRecord;
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async {
    if (failOnRecord) throw StateError('trilha de auditoria fora do ar');
    events.add(event);
  }
}

void main() {
  late FakeTriageSessionStore store;
  late FakeAuditTrail audit;
  late TriageSessionService service;

  final relogio = DateTime.utc(2026, 9, 16, 12, 0, 0);

  setUp(() {
    store = FakeTriageSessionStore();
    audit = FakeAuditTrail();
    service = TriageSessionService(
      store: store,
      audit: audit,
      clock: () => relogio,
    );
  });

  Future<RiskLevel> avaliar({
    AuthenticatedUser user = _patient,
    bool chestPain = false,
    bool difficultyBreathing = false,
    bool fever = false,
    bool persistentVomiting = false,
    bool bleeding = false,
    bool severeWeakness = false,
  }) =>
      service.evaluateAndRecord(
        user: user,
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      );

  test('o risco continua vindo do motor determinístico', () async {
    expect(await avaliar(chestPain: true), RiskLevel.red);
    expect(await avaliar(fever: true), RiskLevel.yellow);
    expect(await avaliar(), RiskLevel.green);
  });

  test('grava a sessão com o patientId do token, nunca de parâmetro', () async {
    await avaliar(chestPain: true);

    expect(store.saved, hasLength(1));
    final sessao = store.saved.single;
    expect(sessao.patientId, UuidValue.fromString(_patientId));
    expect(sessao.deviceId, 'patient-device-001');
    expect(sessao.createdAt, relogio);
  });

  test('o risco gravado é o mesmo que o motor devolveu (INV-02)', () async {
    final risco = await avaliar(bleeding: true);

    expect(risco, RiskLevel.red);
    expect(store.saved.single.resultRisk, RiskLevel.red);
    expect(store.saved.single.resultDisplay, 'Vermelho');
  });

  test('grava as seis respostas com chave estável, não com texto de UI', () async {
    await avaliar(chestPain: true, fever: true);

    final respostas = store.saved.single.answers;
    expect(respostas, hasLength(6));
    expect(
      respostas.map((r) => r.question),
      [
        'chestPain',
        'difficultyBreathing',
        'fever',
        'persistentVomiting',
        'bleeding',
        'severeWeakness',
      ],
    );
    expect(respostas.map((r) => r.answer), ['sim', 'não', 'sim', 'não', 'não', 'não']);
  });

  test('recusa quem não é paciente', () async {
    expect(
      () => avaliar(user: _acs),
      throwsA(isA<StateError>()),
    );
  });

  test('não grava nada quando o papel é recusado', () async {
    await expectLater(() => avaliar(user: _acs), throwsA(isA<StateError>()));

    expect(store.saved, isEmpty);
    expect(audit.events, isEmpty);
  });

  test('a gravação deixa linha de auditoria apontando a sessão', () async {
    await avaliar(chestPain: true);

    expect(audit.events, hasLength(1));
    final evento = audit.events.single;
    expect(evento.actionType, 'write');
    expect(evento.resourceType, 'triage_session');
    expect(evento.result, 'granted');
    expect(evento.userId, _patientId);
    // Diferente do diretório de pacientes, aqui o evento é sobre UM recurso
    // específico, então `resourceId` é preenchido — e é o id da sessão, nunca
    // o conteúdo clínico.
    expect(evento.resourceId, '00000000-0000-4000-8000-0000000000aa');
  });

  test('uma trilha de auditoria fora do ar não impede a triagem', () async {
    audit = FakeAuditTrail(failOnRecord: true);
    service = TriageSessionService(store: store, audit: audit, clock: () => relogio);

    expect(await avaliar(chestPain: true), RiskLevel.red);
    expect(store.saved, hasLength(1));
  });
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/triage_session_service_test.dart`
Expected: FAIL na compilação — `Error: Couldn't resolve the package 'triage_session_service.dart'` / `TriageSessionService isn't defined`.

- [ ] **Step 3: Implementar o serviço**

Crie `backend/sinalacs_server/lib/src/application/triage/triage_session_service.dart`:

```dart
import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_engine.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência da sessão de triagem.
///
/// Mesmo padrão de `AlertStore`/`VisitStore`/`PatientDirectoryStore`: interface
/// aqui, implementação ORM em `infrastructure/`, para o serviço ser testável
/// sem Postgres.
abstract interface class TriageSessionStore {
  /// Devolve a sessão gravada, já com o `id` atribuído pelo banco.
  Future<TriageSession> insert(TriageSession session);
}

/// Registra a triagem estruturada do paciente.
///
/// Existe porque `TriageEndpoint` era uma função pura: calculava o risco e o
/// descartava. `triage_sessions` estava modelada e migrada desde a base, sem
/// nenhum escritor — não havia histórico clínico, nem vínculo entre a triagem
/// e o paciente, e a auditoria da LGPD (RF17) não cobria a triagem.
///
/// O cálculo continua no [TriageEngine], inalterado: este serviço não decide
/// risco, só persiste o que o motor determinou (INV-02).
class TriageSessionService {
  TriageSessionService({
    required TriageSessionStore store,
    required AuditTrail audit,
    TriageEngine engine = const TriageEngine(),
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _engine = engine,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final TriageSessionStore _store;
  final AuditTrail _audit;
  final TriageEngine _engine;
  final DateTime Function() _clock;

  /// Chaves estáveis das perguntas.
  ///
  /// Deliberadamente os nomes dos campos do motor, e **não** o texto exibido na
  /// tela: a cópia de UI muda com redesign, e um prontuário cujas perguntas
  /// mudam de identidade a cada release não é auditável.
  static const _questionKeys = <String>[
    'chestPain',
    'difficultyBreathing',
    'fever',
    'persistentVomiting',
    'bleeding',
    'severeWeakness',
  ];

  /// Classifica e registra a triagem do próprio paciente autenticado.
  ///
  /// O `patientId` vem SEMPRE de [AuthenticatedUser.id], nunca de um parâmetro:
  /// aceitar um id do cliente permitiria gravar triagem em nome de outra
  /// pessoa (INV-05).
  Future<RiskLevel> evaluateAndRecord({
    required AuthenticatedUser user,
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    if (user.role != UserRole.patient) {
      throw StateError('Somente o paciente pode registrar a própria triagem.');
    }

    final risk = _engine.evaluate(
      chestPain: chestPain,
      difficultyBreathing: difficultyBreathing,
      fever: fever,
      persistentVomiting: persistentVomiting,
      bleeding: bleeding,
      severeWeakness: severeWeakness,
    );

    final respostas = <bool>[
      chestPain,
      difficultyBreathing,
      fever,
      persistentVomiting,
      bleeding,
      severeWeakness,
    ];

    final gravada = await _store.insert(TriageSession(
      patientId: UuidValue.fromString(user.id),
      answers: [
        for (var i = 0; i < _questionKeys.length; i++)
          TriageAnswer(
            question: _questionKeys[i],
            answer: respostas[i] ? 'sim' : 'não',
          ),
      ],
      resultRisk: risk,
      resultDisplay: _displayFor(risk),
      createdAt: _clock(),
      deviceId: user.deviceId,
    ));

    // Best-effort, igual ao diretório de pacientes: uma trilha fora do ar não
    // pode impedir uma triagem clínica de acontecer.
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'triage_session',
      resourceId: gravada.id?.uuid,
      result: 'granted',
    ));

    return risk;
  }

  static String _displayFor(RiskLevel risk) => switch (risk) {
        RiskLevel.red => 'Vermelho',
        RiskLevel.yellow => 'Amarelo',
        RiskLevel.green => 'Verde',
      };
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/triage_session_service_test.dart`
Expected: PASS — 8 testes.

- [ ] **Step 5: Confirmar que nada mais quebrou**

Run: `cd backend && dart analyze && cd sinalacs_server && dart test test/unit`
Expected: analyze limpo; toda a suíte unitária passa (69 anteriores + 8 novos = 77).

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/triage/triage_session_service.dart \
        backend/sinalacs_server/test/unit/triage_session_service_test.dart
git commit -s -m "feat(backend): registrar a sessão de triagem com paciente e auditoria"
```

---


### Task 2: Store ORM da sessão de triagem

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_triage_session_store.dart`
- Test: `backend/sinalacs_server/test/integration/triage_session_persistence_test.dart`

**Interfaces:**
- Consumes: `TriageSessionStore` (Task 1); `TriageSession.db.insertRow(Session, TriageSession, {Transaction? transaction})` do ORM gerado.
- Produces: `class OrmTriageSessionStore implements TriageSessionStore` com construtor `({required Session Function() session, Transaction? transaction})`.

- [ ] **Step 1: Escrever o teste de integração que falha**

Crie `backend/sinalacs_server/test/integration/triage_session_persistence_test.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_triage_session_store.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Desenvolvimento',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea 12',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'development-patient',
      name: 'Paciente de desenvolvimento',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await Patient.db.insertRow(
    session,
    Patient(
      id: UuidValue.fromString(_patientId),
      emergencyContact: 'Contato de desenvolvimento',
      isChronic: false,
      chronicConditions: const [],
    ),
  );
}

void main() {
  withServerpod('Dado a persistência da triagem', (sessionBuilder, endpoints) {
    test('a sessão de triagem é gravada de verdade em triage_sessions', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final service = TriageSessionService(
        store: OrmTriageSessionStore(session: () => session),
        audit: OrmAuditTrail(
          session: () => session,
          chainSecret: 'test-audit-chain-secret',
        ),
        clock: () => DateTime.utc(2026, 9, 16, 12, 0, 0),
      );

      final risco = await service.evaluateAndRecord(
        user: _patient,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(risco, RiskLevel.red);

      final gravadas = await TriageSession.db.find(session);
      expect(gravadas, hasLength(1));
      expect(gravadas.single.patientId, UuidValue.fromString(_patientId));
      expect(gravadas.single.resultRisk, RiskLevel.red);
      expect(gravadas.single.resultDisplay, 'Vermelho');
      // As seis respostas sobrevivem à ida e volta do JSON da coluna.
      expect(gravadas.single.answers, hasLength(6));
      expect(gravadas.single.answers.first.question, 'chestPain');
      expect(gravadas.single.answers.first.answer, 'sim');
    });

    test('a gravação deixa linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final service = TriageSessionService(
        store: OrmTriageSessionStore(session: () => session),
        audit: OrmAuditTrail(
          session: () => session,
          chainSecret: 'test-audit-chain-secret',
        ),
      );

      await service.evaluateAndRecord(
        user: _patient,
        chestPain: false,
        difficultyBreathing: false,
        fever: true,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      final logs = await AuditLog.db.find(session);
      expect(logs, hasLength(1));
      expect(logs.single.actionType, 'write');
      expect(logs.single.resourceType, 'triage_session');
      expect(logs.single.result, 'granted');
      expect(logs.single.resourceId, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Subir o Postgres de teste e confirmar que o teste falha**

```bash
docker compose --profile test up -d postgres-test
cd backend/sinalacs_server && dart test test/integration/triage_session_persistence_test.dart
```
Expected: FAIL na compilação — `OrmTriageSessionStore isn't defined`.

- [ ] **Step 3: Implementar o store**

Crie `backend/sinalacs_server/lib/src/infrastructure/database/orm_triage_session_store.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [TriageSessionStore] sobre o ORM do Serverpod.
///
/// `TriageSession.patientId` tem chave estrangeira para `patients`, então a
/// gravação falha se o paciente do token não existir no banco — é o que
/// garante que uma triagem nunca fique órfã de prontuário.
class OrmTriageSessionStore implements TriageSessionStore {
  OrmTriageSessionStore({
    required Session Function() session,
    Transaction? transaction,
  })  : _session = session,
        _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

  @override
  Future<TriageSession> insert(TriageSession session) => TriageSession.db.insertRow(
        _session(),
        session,
        transaction: _transaction,
      );
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/integration/triage_session_persistence_test.dart`
Expected: PASS — 2 testes.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_triage_session_store.dart \
        backend/sinalacs_server/test/integration/triage_session_persistence_test.dart
git commit -s -m "feat(backend): persistir a sessão de triagem pelo ORM"
```

---


### Task 3: Endpoint autenticado

**Files:**
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart`
- Test: `backend/sinalacs_server/test/integration/triage_session_persistence_test.dart` (acrescentar)

**Interfaces:**
- Consumes: `TriageSessionService` (Task 1), `OrmTriageSessionStore` (Task 2), `AlertRuntime.instance.auth.verifyToken(String) → AuthenticatedUser?`, `AlertRuntime.instance.auditTrailFor(Session) → AuditTrail`.
- Produces: `AlertRuntime.triageSessionServiceFor(Session session) → TriageSessionService`; nova assinatura `TriageEndpoint.evaluate(Session, {required String accessToken, required bool chestPain, ...}) → Future<TriageResult>`.

- [ ] **Step 1: Acrescentar os testes de endpoint que falham**

Acrescente estes três testes dentro do `withServerpod` de `test/integration/triage_session_persistence_test.dart`, depois dos existentes:

```dart
    test('o endpoint recusa token inválido', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      await expectLater(
        endpoints.triage.evaluate(
          sessionBuilder,
          accessToken: 'token-que-nao-vale',
          chestPain: true,
          difficultyBreathing: false,
          fever: false,
          persistentVomiting: false,
          bleeding: false,
          severeWeakness: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o endpoint recusa quem não é paciente', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.triage.evaluate(
          sessionBuilder,
          accessToken: login.accessToken,
          chestPain: true,
          difficultyBreathing: false,
          fever: false,
          persistentVomiting: false,
          bleeding: false,
          severeWeakness: false,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o endpoint classifica e grava a triagem do paciente autenticado', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final resultado = await endpoints.triage.evaluate(
        sessionBuilder,
        accessToken: login.accessToken,
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(resultado.risk, RiskLevel.green);

      final gravadas = await TriageSession.db.find(session);
      expect(gravadas, hasLength(1));
      expect(gravadas.single.resultRisk, RiskLevel.green);
    });
```

E acrescente, no topo do `main()`, antes do `withServerpod`, a configuração que habilita o dev-login — mesmo padrão de `red_alert_cycle_test.dart`:

```dart
void main() {
  setUpAll(() {
    AlertRuntime.instance.overrideConfig(AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    ));
  });

  tearDownAll(() => AlertRuntime.instance.overrideConfig(null));

  withServerpod('Dado a persistência da triagem', (sessionBuilder, endpoints) {
```

Acrescente também os imports que faltam no topo do arquivo:

```dart
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/integration/triage_session_persistence_test.dart`
Expected: FAIL na compilação — `No named parameter with the name 'accessToken'`.

- [ ] **Step 3: Adicionar a fábrica no runtime**

Em `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`, acrescente o import:

```dart
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_triage_session_store.dart';
```

e o método, logo depois de `patientDirectoryServiceFor`:

```dart
  /// Constrói o serviço de triagem persistida para uma requisição.
  TriageSessionService triageSessionServiceFor(Session session) =>
      TriageSessionService(
        store: OrmTriageSessionStore(session: () => session),
        audit: auditTrailFor(session),
      );
```

- [ ] **Step 4: Trocar o endpoint**

Substitua o conteúdo de `backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart` por:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Motor de triagem determinístico, inspirado no Protocolo de Manchester.
///
/// A mesma entrada produz sempre a mesma saída, sem modelo probabilístico e sem
/// campo editável: a classificação de risco não é alterável por intervenção
/// manual no fluxo de triagem (INV-02).
///
/// Passou a exigir `accessToken` e a gravar em `triage_sessions`: antes disso o
/// endpoint era uma função pura, respondia sem autenticação alguma, e o
/// resultado clínico era descartado — não havia prontuário, nem vínculo com o
/// paciente, nem auditoria da triagem (RF17).
class TriageEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<TriageResult> evaluate(
    Session session, {
    required String accessToken,
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    final user = AlertRuntime.instance.auth.verifyToken(accessToken);
    if (user == null) {
      throw AlertPermissionException(message: 'token inválido ou expirado');
    }

    try {
      final risk = await AlertRuntime.instance
          .triageSessionServiceFor(session)
          .evaluateAndRecord(
            user: user,
            chestPain: chestPain,
            difficultyBreathing: difficultyBreathing,
            fever: fever,
            persistentVomiting: persistentVomiting,
            bleeding: bleeding,
            severeWeakness: severeWeakness,
          );
      return TriageResult(risk: risk);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
```

- [ ] **Step 5: Regenerar o cliente tipado**

```bash
cd backend/sinalacs_server && serverpod generate
```
Expected: regenera `lib/src/generated/` e `backend/sinalacs_client/lib/src/protocol/`. **Nenhuma migração** — nenhum `.spy.yaml` de tabela mudou. Se `serverpod` não estiver instalado: `dart pub global activate serverpod_cli`.

- [ ] **Step 6: Rodar os testes de integração**

Run: `cd backend/sinalacs_server && dart test test/integration/triage_session_persistence_test.dart`
Expected: PASS — 5 testes.

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
        backend/sinalacs_server/lib/src/endpoints/triage_endpoint.dart \
        backend/sinalacs_server/lib/src/generated backend/sinalacs_client/lib/src/protocol \
        backend/sinalacs_server/test/integration/triage_session_persistence_test.dart
git commit -s -m "feat(backend): exigir autenticação em triage.evaluate"
```

---


### Task 4: Consertar os chamadores quebrados

O `accessToken` obrigatório quebra três arquivos. Esta tarefa deixa o repositório verde de novo — sem ela, `dart test` e `flutter test integration_test` do paciente falham.

**Files:**
- Modify: `apps/patient/lib/core/network/backend_client.dart:119-138`
- Modify: `apps/patient/integration_test/backend_connection_test.dart` (testes de triagem, linhas ~53, 61, 69, 88)
- Modify: `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart:146,155`

**Interfaces:**
- Consumes: nova assinatura de `triage.evaluate` (Task 3); `BackendClient._requireToken() → Future<String>`, que já existe em `apps/patient/lib/core/network/backend_client.dart:80-88`.
- Produces: nada novo — a interface `PatientBackend.evaluateTriage` **não muda de assinatura**, então nenhum fake de teste de widget precisa ser tocado.

- [ ] **Step 1: Rodar os testes quebrados para ver a falha**

```bash
cd backend/sinalacs_server && dart test test/integration/red_alert_cycle_test.dart
```
Expected: FAIL — `Required named parameter 'accessToken' must be provided` nas linhas 146 e 155.

- [ ] **Step 2: Consertar o teste do backend**

Em `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart`, o teste de triagem passa a autenticar antes. Substitua o corpo do teste que chama `triage.evaluate` por:

```dart
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final vermelho = await endpoints.triage.evaluate(
        sessionBuilder,
        accessToken: login.accessToken,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
      expect(vermelho.risk, RiskLevel.red);

      final verde = await endpoints.triage.evaluate(
        sessionBuilder,
        accessToken: login.accessToken,
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
      expect(verde.risk, RiskLevel.green);
```

- [ ] **Step 3: Rodar a suíte inteira do backend**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — **96 testes**: os 83 que já existiam, mais os 8 unitários da Task 1, mais os 5 de integração das Tasks 2 e 3. Nenhum teste anterior é removido por este plano.

- [ ] **Step 4: Consertar o cliente do app do paciente**

Em `apps/patient/lib/core/network/backend_client.dart`, no método `evaluateTriage`, passe o token — o helper `_requireToken()` já existe e já é usado por `createRedAlert`:

```dart
  @override
  Future<RiskLevel> evaluateTriage({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    final token = await _requireToken();
    final result = await _guard(
      () => _client.triage.evaluate(
        accessToken: token,
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      ),
    );
    return result.risk;
  }
```

- [ ] **Step 5: Consertar os testes de integração do paciente**

`apps/patient/integration_test/backend_connection_test.dart` cria um `BackendClient` novo em cada `setUp`, e os testes de triagem **não** autenticavam. Acrescente `await backend.login();` como primeira linha dos dois testes de triagem — o que chama `evaluateTriage` nas linhas ~53/61/69 e o de determinismo na linha ~88:

```dart
  test('a triagem é classificada pelo motor do servidor', () async {
    await backend.login();

    final red = await backend.evaluateTriage(
```

```dart
  test('a mesma resposta produz sempre o mesmo risco', () async {
    await backend.login();

    final results = <RiskLevel>[];
```

- [ ] **Step 6: Validar contra a stack real**

```bash
docker compose up --build -d
./scripts/dev/sync_dev_ca.sh
cd apps/patient && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=http://10.0.2.2:8080/
```
Expected: PASS — 7 testes. Se `flutter analyze` acusar import não usado, remova-o.

- [ ] **Step 7: Validar o `live_check` (não deve precisar de mudança)**

```bash
cd apps/patient && dart run tool/live_check.dart
```
Expected: `OK — o app fala com o backend.` Ele já faz `login()` na linha 32, antes das chamadas de triagem nas linhas 37 e 45. Se falhar com "Sessão não iniciada", a ordem mudou — corrija movendo o login para antes.

- [ ] **Step 8: Commit**

```bash
git add apps/patient/lib/core/network/backend_client.dart \
        apps/patient/integration_test/backend_connection_test.dart \
        backend/sinalacs_server/test/integration/red_alert_cycle_test.dart
git commit -s -m "fix(patient): autenticar antes de chamar triage.evaluate"
```

---


### Task 5: Atualizar a documentação

**Files:**
- Modify: `backend/CLAUDE.md`
- Modify: `spec/validation_report.md`

**Interfaces:**
- Consumes: o comportamento final das tarefas 1 a 4.
- Produces: nada de código.

- [ ] **Step 1: Registrar o endpoint novo em `backend/CLAUDE.md`**

Na linha 60 de `backend/CLAUDE.md` (o parágrafo que começa com `**Serverpod is RPC, not REST**`), a lista de endpoints contém exatamente este trecho:

```
`alerts.acknowledge`, `triage.evaluate`, `visits.sync`
```

Substitua-o por:

```
`alerts.acknowledge`, `triage.evaluate` (exige `accessToken`; classifica pelo `TriageEngine` determinístico, grava a sessão em `triage_sessions` com o `patientId` vindo do token — nunca de parâmetro, INV-05 — e escreve uma linha `write`/`triage_session` em `audit_logs`; só o papel `patient` é aceito, um ACS recebe `AlertPermissionException`), `visits.sync`
```

- [ ] **Step 2: Corrigir a contagem de testes em `backend/CLAUDE.md`**

O mesmo arquivo contém exatamente este trecho, já desatualizado antes deste plano:

```
83 tests: 69 unit + 14 integration
```

Substitua por:

```
96 tests: 77 unit + 19 integration
```

- [ ] **Step 3: Atualizar o relatório de validação**

Em `spec/validation_report.md`, §6, acrescente logo abaixo da tabela de tabelas mortas:

```markdown
**Atualização (L-04 fechada):** `triage_sessions` passou a ter escritor —
`TriageSessionService`, gravado por `triage.evaluate`, que agora exige token e
identifica o paciente. `consent_logs` continua sem escritor.
```

Em §8, substitua a linha de L-04 por:

```markdown
- **L-04 · ~~A triagem não deixa registro.~~** RESOLVIDO — `triage.evaluate`
  exige `accessToken`, grava em `triage_sessions` e audita. Ver
  `docs/superpowers/plans/2026-09-16-triagem-persistida.md`.
```

Em §3, substitua a linha RF04 por:

```markdown
| RF04 | Formulário de triagem estruturada | **backend** | `triage.evaluate` exige token, classifica pelo motor determinístico e grava em `triage_sessions` com auditoria. |
```

e a linha RNF06 por:

```markdown
| RNF06 | RBAC | **ausente** | Todo endpoint é `requireLogin => false`; só há checagem ad-hoc de `user.role`. `triage.evaluate` deixou de ser público (exige token e papel `patient`), mas não existe camada formal de RBAC. |
```

- [ ] **Step 4: Rodar a bateria completa uma última vez**

```bash
cd backend && dart analyze
cd sinalacs_server && dart test
```
Expected: analyze limpo; 96 testes passando.

- [ ] **Step 5: Commit**

```bash
git add backend/CLAUDE.md spec/validation_report.md
git commit -s -m "docs: registrar a triagem persistida e fechar L-04"
```

---

## Fora de escopo (planos separados)

| Subsistema | Lacunas | Por que separado |
|---|---|---|
| Leitura de status para o paciente | L-03, INV-05 | Depende deste plano (precisa de triagem gravada para ter o que ler). |
| Endpoints do backoffice | L-01, papel `admin` | Depende deste plano para os contadores amarelo/verde terem fonte. |
| RBAC formal | L-09, RNF06 | Transversal a todos os endpoints. |
| Consentimento LGPD | `consent_logs` morta | Independente. |
| Sync bidirecional | RF15 | Independente. |
| TLS no RPC | L-08, RNF04 | Infraestrutura, não código de aplicação. |
| Cobertura de teste faltante | L-13, M1.3 | Independente. |
| Criptografia de coluna | RNF03, INV-04 servidor | Decisão de produto antes de código. |
| Código morto | L-14 | Independente. |
| Instrumentação de latência | RNF01 | Independente. |
