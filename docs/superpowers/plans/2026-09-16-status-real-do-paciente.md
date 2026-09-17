# Status Real para o Paciente — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir a tela de Status do app do paciente — hoje uma árvore `const` que anuncia uma solicitação inexistente — por dado real do próprio paciente, lido de um endpoint novo que aplica INV-05.

**Architecture:** Um serviço de aplicação (`PatientStatusService`) lê o último alerta e a última triagem do paciente autenticado por uma porta abstrata (`PatientStatusStore`), audita a leitura e devolve um DTO minimizado. A implementação ORM fica em `infrastructure/`, no mesmo padrão de `PatientDirectoryService`/`OrmPatientDirectoryStore` e `TriageSessionService`/`OrmTriageSessionStore`. Um endpoint novo `status.myRequest` expõe isso, e a tela do paciente passa a consumi-lo.

**Tech Stack:** Dart 3.8 · Serverpod 3.4.13 · PostgreSQL · Flutter 3.44.8 · `package:test` / `flutter_test`

**Spec:** [spec/validation_report.md](../../../spec/validation_report.md) — este plano fecha **L-03** (§8, P0) e move **RF05** de `ausente` para `backend`. É também onde **INV-05** (§3) deixa de ser "vacuamente verdadeira": o relatório registra que ela só se sustenta hoje porque não existe endpoint de leitura voltado ao paciente, e que "vira risco real no momento em que RF05 for implementado".

## Global Constraints

- Idioma de documentação, comentários, mensagens de erro e textos de UI: **português**.
- **INV-05 — a razão de ser deste plano.** O `patientId` da consulta vem SEMPRE de `user.id` (o token verificado). Nenhum método deste plano pode aceitar um `patientId` como parâmetro: seria entregar ao dispositivo a chance de pedir o prontuário de outra pessoa. Esta é a invariante que o relatório previu que seria testada aqui.
- **Minimização LGPD.** O DTO devolvido ao paciente carrega só o que a tela precisa. `locationHash`, `deviceId`, `acsId`, `microAreaId`, `mqttTopic`, `retryCount` e `version` **não** saem do servidor. `acsId` em particular revelaria qual agente foi designado.
- **INV-02** — nenhum risco é recalculado ou editável aqui; este plano só **lê** valores que `TriageEngine` já determinou.
- **LGPD** — nenhum dado real de paciente em teste, log ou fixture. Só os UUIDs sintéticos do seed (`00000000-0000-4000-8000-0000000000NN`).
- Nunca editar à mão nada em `lib/src/generated/` ou `migrations/` — rode `serverpod generate`.
- **Nenhuma migração nova.** O único `.spy.yaml` criado aqui fica em `models/api/` e **não é tabela** — migrações existem só para tabelas. Se você se pegar querendo rodar `serverpod create-migration`, pare e reporte BLOCKED.
- A camada `application/` obtém `UuidValue` por `import 'package:serverpod/serverpod.dart' show UuidValue;`.
- Testes do backend rodam de `backend/sinalacs_server`; os de integração exigem `docker compose --profile test up -d postgres-test` na raiz.
- **Armadilha conhecida:** se `TEST_DATABASE_PASSWORD` do `.env` divergir do bloco `test:` de `config/passwords.yaml`, o Serverpod chama `exit(1)` sem esvaziar o stdout e a suíte morre com código 1 e **zero linhas de log**. Rode `./scripts/dev/bootstrap_env.sh --force`.
- O ponto de partida é **98 testes** no backend (79 unitários + 19 de integração) e **19** no app do paciente, todos passando. Note que `backend/CLAUDE.md` está desatualizado e ainda diz `96 tests: 77 unit + 19 integration` — a onda de correção do plano anterior acrescentou 2 testes unitários sem atualizar o documento. A Task 5 corrige isso.

---

## Contexto que justifica a urgência

`apps/patient/lib/app/app.dart:214` liga a triagem à tela de status:

```dart
PatientDestination.triage => TriageScreen(onComplete: () => _select(PatientDestination.status)),
```

Ou seja: ao **terminar a triagem**, o paciente é levado exatamente para a tela que afirma existir uma "Solicitação de visita #4082 · Triagem Vermelha · criada hoje às 09:30" em análise. A tela é `const` — o texto é o mesmo para todo mundo, sempre. Um paciente pode sair da triagem acreditando que um pedido de socorro está sendo tratado quando nada foi registrado.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `backend/sinalacs_server/lib/src/application/patients/patient_status_service.dart` (criar) | Porta `PatientStatusStore`, exceção de autorização, e o serviço que aplica papel, lê, audita e minimiza. |
| `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_status_store.dart` (criar) | Implementação da porta sobre o ORM. |
| `backend/sinalacs_server/lib/src/models/api/patient_request_status.spy.yaml` (criar) | DTO de transporte. **Não é tabela.** |
| `backend/sinalacs_server/lib/src/endpoints/status_endpoint.dart` (criar) | Endpoint `status.myRequest`. |
| `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (modificar) | Fábrica `patientStatusServiceFor(session)`. |
| `backend/sinalacs_server/test/unit/patient_status_service_test.dart` (criar) | Papel, INV-05, minimização, auditoria, ausência de solicitação. |
| `backend/sinalacs_server/test/integration/patient_status_test.dart` (criar) | Leitura real em Postgres e passagem pelo endpoint, incluindo isolamento entre pacientes. |
| `apps/patient/lib/core/network/backend_client.dart` (modificar) | Método `myRequestStatus()` na interface e no cliente real. |
| `apps/patient/test/support/fake_patient_backend.dart` (modificar) | Implementar o método novo — senão o fake para de compilar. |
| `apps/patient/lib/app/app.dart` (modificar) | `StatusScreen` deixa de ser `const` e passa a ler do backend. |
| `apps/patient/test/patient_app_mvp_test.dart` (modificar) | Teste de widget da tela com dado do fake. |

**Fora de escopo deste plano**, deliberadamente: as outras telas fabricadas do paciente (Perguntas, Perfil clínico, Lembretes) e o histórico de triagens. A tela de Status mostra a solicitação **corrente**; histórico é outro requisito.

---

### Task 1: Serviço de status do paciente

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/patients/patient_status_service.dart`
- Test: `backend/sinalacs_server/test/unit/patient_status_service_test.dart`

**Interfaces:**
- Consumes: `AuthenticatedUser {String id, UserRole role, String? microAreaId, String deviceId}` de `lib/src/application/auth/development_auth_service.dart`; `AuditTrail.recordSafely(AuditEvent)` de `lib/src/application/audit/audit_trail.dart`; `Alert`, `TriageSession`, `AlertStatus`, `RiskLevel`, `UserRole` do protocolo gerado.
- Produces:
  - `class StatusAuthorizationException implements Exception { final String message; }`
  - `abstract interface class PatientStatusStore { Future<Alert?> latestAlertFor(UuidValue patientId); Future<TriageSession?> latestTriageFor(UuidValue patientId); }`
  - `class PatientStatusView` com campos `alertId`, `status`, `riskLevel`, `triggeredAt`, `acknowledgedAt`, `lastTriageRisk`, `lastTriageAt` (todos anuláveis)
  - `class PatientStatusService({required PatientStatusStore store, required AuditTrail audit})` com `Future<PatientStatusView> forPatient(AuthenticatedUser user)`

- [ ] **Step 1: Escrever o teste que falha**

Crie `backend/sinalacs_server/test/unit/patient_status_service_test.dart`:

```dart
import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_status_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _otherPatientId = '00000000-0000-4000-8000-000000000005';
const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _alertId = '00000000-0000-4000-8000-0000000000b1';

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

class FakePatientStatusStore implements PatientStatusStore {
  FakePatientStatusStore({this.alerts = const {}, this.triages = const {}});

  final Map<String, Alert> alerts;
  final Map<String, TriageSession> triages;
  final List<String> consultados = <String>[];

  @override
  Future<Alert?> latestAlertFor(UuidValue patientId) async {
    consultados.add(patientId.uuid);
    return alerts[patientId.uuid];
  }

  @override
  Future<TriageSession?> latestTriageFor(UuidValue patientId) async {
    consultados.add(patientId.uuid);
    return triages[patientId.uuid];
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

Alert _alerta({required String patientId, AlertStatus status = AlertStatus.pending}) => Alert(
      id: UuidValue.fromString(_alertId),
      patientId: UuidValue.fromString(patientId),
      acsId: UuidValue.fromString(_acsId),
      microAreaId: UuidValue.fromString(_microAreaId),
      triggeredAt: DateTime.utc(2026, 9, 16, 9, 30),
      acknowledgedAt: status == AlertStatus.pending ? null : DateTime.utc(2026, 9, 16, 9, 34),
      riskLevel: RiskLevel.red,
      locationHash: 'hash-secreto-01',
      status: status,
      mqttTopic: 'sinalacs/v1/microareas/$_microAreaId/alerts',
      deviceId: 'patient-device-001',
      retryCount: 0,
      version: 1,
    );

TriageSession _triagem(String patientId) => TriageSession(
      patientId: UuidValue.fromString(patientId),
      answers: [const TriageAnswer(question: 'chestPain', answer: 'sim')],
      resultRisk: RiskLevel.red,
      resultDisplay: 'Vermelho',
      createdAt: DateTime.utc(2026, 9, 16, 9, 28),
      deviceId: 'patient-device-001',
    );

void main() {
  late FakeAuditTrail audit;

  PatientStatusService servico(FakePatientStatusStore store) =>
      PatientStatusService(store: store, audit: audit);

  setUp(() {
    audit = FakeAuditTrail();
  });

  test('devolve o alerta e a triagem do próprio paciente', () async {
    final store = FakePatientStatusStore(
      alerts: {_patientId: _alerta(patientId: _patientId)},
      triages: {_patientId: _triagem(_patientId)},
    );

    final view = await servico(store).forPatient(_patient);

    expect(view.alertId, _alertId);
    expect(view.status, AlertStatus.pending);
    expect(view.riskLevel, RiskLevel.red);
    expect(view.triggeredAt, DateTime.utc(2026, 9, 16, 9, 30));
    expect(view.acknowledgedAt, isNull);
    expect(view.lastTriageRisk, RiskLevel.red);
    expect(view.lastTriageAt, DateTime.utc(2026, 9, 16, 9, 28));
  });

  test('INV-05: consulta SEMPRE o id do token, nunca outro', () async {
    final store = FakePatientStatusStore(
      alerts: {
        _patientId: _alerta(patientId: _patientId),
        _otherPatientId: _alerta(patientId: _otherPatientId),
      },
    );

    await servico(store).forPatient(_patient);

    // Só o próprio id foi para a store. Se algum dia o serviço ganhar um
    // parâmetro de paciente, este teste é o que quebra primeiro.
    expect(store.consultados.toSet(), {_patientId});
  });

  test('não vaza campo que a tela não precisa (minimização LGPD)', () async {
    final store = FakePatientStatusStore(
      alerts: {_patientId: _alerta(patientId: _patientId)},
    );

    final view = await servico(store).forPatient(_patient);

    // A prova real de minimização é a AUSÊNCIA dos campos em PatientStatusView
    // e no .spy.yaml — não há getter de locationHash, acsId, deviceId,
    // microAreaId, mqttTopic, retryCount nem version para asserir aqui.
    // Este teste fixa o que SAI, para que acrescentar um campo exija editá-lo.
    expect(view.alertId, _alertId);
    expect(view.status, AlertStatus.pending);
    expect(view.riskLevel, RiskLevel.red);
    expect(view.lastTriageRisk, isNull);
    expect(view.lastTriageAt, isNull);
  });

  test('paciente sem solicitação recebe uma visão vazia, não um erro', () async {
    final view = await servico(FakePatientStatusStore()).forPatient(_patient);

    expect(view.alertId, isNull);
    expect(view.status, isNull);
    expect(view.riskLevel, isNull);
    expect(view.triggeredAt, isNull);
    expect(view.lastTriageRisk, isNull);
  });

  test('alerta confirmado carrega o instante da confirmação', () async {
    final store = FakePatientStatusStore(
      alerts: {
        _patientId: _alerta(patientId: _patientId, status: AlertStatus.acknowledged),
      },
    );

    final view = await servico(store).forPatient(_patient);

    expect(view.status, AlertStatus.acknowledged);
    expect(view.acknowledgedAt, DateTime.utc(2026, 9, 16, 9, 34));
  });

  test('recusa quem não é paciente', () async {
    expect(
      () => servico(FakePatientStatusStore()).forPatient(_acs),
      throwsA(isA<StatusAuthorizationException>()),
    );
  });

  test('a leitura grava auditoria sem enumerar conteúdo clínico', () async {
    final store = FakePatientStatusStore(
      alerts: {_patientId: _alerta(patientId: _patientId)},
    );

    await servico(store).forPatient(_patient);

    expect(audit.events, hasLength(1));
    final evento = audit.events.single;
    expect(evento.actionType, 'read');
    expect(evento.resourceType, 'patient_request_status');
    expect(evento.result, 'granted');
    expect(evento.userId, _patientId);
    expect(evento.resourceId, _alertId);
  });

  test('uma trilha de auditoria fora do ar não impede a leitura', () async {
    audit = FakeAuditTrail(failOnRecord: true);
    final store = FakePatientStatusStore(
      alerts: {_patientId: _alerta(patientId: _patientId)},
    );

    final view = await servico(store).forPatient(_patient);

    expect(view.alertId, _alertId);
  });
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/patient_status_service_test.dart`
Expected: FAIL na compilação — `Couldn't resolve the package` / `PatientStatusService isn't defined`.

- [ ] **Step 3: Implementar o serviço**

Crie `backend/sinalacs_server/lib/src/application/patients/patient_status_service.dart`:

```dart
import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Recusa de autorização na leitura de status.
///
/// Classe Dart comum, de propósito: não é modelo `.spy.yaml`, porque o
/// endpoint a traduz para `AlertPermissionException`, que já atravessa o
/// protocolo. Espelha `TriageAuthorizationException`; unificar as duas é
/// trabalho do plano de RBAC formal (L-09), não deste.
class StatusAuthorizationException implements Exception {
  const StatusAuthorizationException(this.message);

  final String message;

  @override
  String toString() => 'StatusAuthorizationException: $message';
}

/// Leitura do alerta e da triagem mais recentes de um paciente.
///
/// Mesmo padrão de `PatientDirectoryStore`/`TriageSessionStore`: interface
/// aqui, implementação ORM em `infrastructure/`.
abstract interface class PatientStatusStore {
  Future<Alert?> latestAlertFor(UuidValue patientId);

  Future<TriageSession?> latestTriageFor(UuidValue patientId);
}

/// O que o paciente vê sobre a própria solicitação.
///
/// Todos os campos são anuláveis porque um paciente que nunca disparou alerta
/// nem fez triagem é um caso normal, não um erro.
class PatientStatusView {
  const PatientStatusView({
    this.alertId,
    this.status,
    this.riskLevel,
    this.triggeredAt,
    this.acknowledgedAt,
    this.lastTriageRisk,
    this.lastTriageAt,
  });

  final String? alertId;
  final AlertStatus? status;
  final RiskLevel? riskLevel;
  final DateTime? triggeredAt;
  final DateTime? acknowledgedAt;
  final RiskLevel? lastTriageRisk;
  final DateTime? lastTriageAt;
}

/// Status da solicitação corrente do paciente autenticado (RF05).
///
/// Existe porque a tela de Status do app era uma árvore `const` que anunciava
/// uma solicitação inexistente a qualquer paciente — e o fluxo de triagem leva
/// direto até ela, então alguém que acabara de responder os sintomas via uma
/// "triagem vermelha em análise" que nunca foi registrada.
///
/// Este é o primeiro endpoint de LEITURA voltado ao paciente. Até ele existir,
/// INV-05 ("o paciente nunca acessa dado de outro paciente") era verdadeira
/// por vacuidade: não havia o que ler. A partir daqui ela precisa ser aplicada,
/// e o ponto onde isso acontece é o [forPatient] abaixo.
class PatientStatusService {
  PatientStatusService({
    required PatientStatusStore store,
    required AuditTrail audit,
  })  : _store = store,
        _audit = audit;

  final PatientStatusStore _store;
  final AuditTrail _audit;

  /// O id consultado vem SEMPRE de [AuthenticatedUser.id], nunca de um
  /// parâmetro — aceitar um `patientId` do cliente seria entregar ao aparelho
  /// a chance de pedir o prontuário de outra pessoa (INV-05).
  Future<PatientStatusView> forPatient(AuthenticatedUser user) async {
    if (user.role != UserRole.patient) {
      throw const StatusAuthorizationException(
        'Somente o paciente pode consultar a própria solicitação.',
      );
    }

    final patientId = UuidValue.fromString(user.id);
    final alert = await _store.latestAlertFor(patientId);
    final triage = await _store.latestTriageFor(patientId);

    // Best-effort, como em PatientDirectoryService e TriageSessionService: uma
    // trilha fora do ar não pode impedir o paciente de ver o próprio status.
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'patient_request_status',
      resourceId: alert?.id?.uuid,
      result: 'granted',
    ));

    // Minimização (spec/lgpd_design.md): locationHash, acsId, microAreaId,
    // deviceId, mqttTopic, retryCount e version NÃO saem daqui. `acsId`
    // revelaria qual agente foi designado, e nada disso ajuda o paciente a
    // entender onde está o próprio pedido.
    return PatientStatusView(
      alertId: alert?.id?.uuid,
      status: alert?.status,
      riskLevel: alert?.riskLevel,
      triggeredAt: alert?.triggeredAt,
      acknowledgedAt: alert?.acknowledgedAt,
      lastTriageRisk: triage?.resultRisk,
      lastTriageAt: triage?.createdAt,
    );
  }
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/patient_status_service_test.dart`
Expected: PASS — 8 testes.

- [ ] **Step 5: Confirmar que nada mais quebrou**

Run: `cd backend && dart analyze && cd sinalacs_server && dart test test/unit`
Expected: analyze limpo; 87 testes unitários (79 anteriores + 8 novos).

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/patients/patient_status_service.dart \
        backend/sinalacs_server/test/unit/patient_status_service_test.dart
git commit -s -m "feat(backend): ler o status da solicitação do próprio paciente"
```

---

### Task 2: Store ORM da leitura de status

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_status_store.dart`
- Test: `backend/sinalacs_server/test/integration/patient_status_test.dart`

**Interfaces:**
- Consumes: `PatientStatusStore`, `PatientStatusService`, `PatientStatusView` (Task 1); `Alert.db.find`, `TriageSession.db.find` do ORM gerado; `OrmAuditTrail({required Session Function() session, required String chainSecret})`.
- Produces: `class OrmPatientStatusStore implements PatientStatusStore` com construtor `({required Session Function() session})`.

- [ ] **Step 1: Escrever o teste de integração que falha**

Crie `backend/sinalacs_server/test/integration/patient_status_test.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_status_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_patient_status_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// UUIDs sintéticos do seed de desenvolvimento.
const _patientId = '00000000-0000-4000-8000-000000000001';
const _otherPatientId = '00000000-0000-4000-8000-000000000005';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _ubsId = '00000000-0000-4000-8000-000000000004';

const _patient = AuthenticatedUser(
  id: _patientId,
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
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
  for (final id in [_patientId, _otherPatientId]) {
    await User.db.insertRow(
      session,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'development-$id',
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
        id: UuidValue.fromString(id),
        emergencyContact: 'Contato de desenvolvimento',
        isChronic: false,
        chronicConditions: const [],
      ),
    );
  }
}

Future<void> _inserirAlerta(
  Session session, {
  required String patientId,
  required DateTime triggeredAt,
  AlertStatus status = AlertStatus.pending,
}) async {
  await Alert.db.insertRow(
    session,
    Alert(
      patientId: UuidValue.fromString(patientId),
      microAreaId: UuidValue.fromString(_microAreaId),
      triggeredAt: triggeredAt,
      riskLevel: RiskLevel.red,
      locationHash: 'hash-secreto-01',
      status: status,
      mqttTopic: 'sinalacs/v1/microareas/$_microAreaId/alerts',
      deviceId: 'patient-device-001',
      retryCount: 0,
      version: 1,
    ),
  );
}

PatientStatusService _servico(Session session) => PatientStatusService(
      store: OrmPatientStatusStore(session: () => session),
      audit: OrmAuditTrail(
        session: () => session,
        chainSecret: 'test-audit-chain-secret',
      ),
    );

void main() {
  withServerpod('Dado o status da solicitação do paciente', (sessionBuilder, endpoints) {
    setUp(() {
      AlertRuntime.instance.overrideConfig(_config());
    });

    tearDown(() {
      AlertRuntime.instance.overrideConfig(null);
    });

    test('devolve o alerta MAIS RECENTE do paciente, contra Postgres real', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      await _inserirAlerta(session, patientId: _patientId, triggeredAt: DateTime.utc(2026, 9, 15, 8));
      await _inserirAlerta(session, patientId: _patientId, triggeredAt: DateTime.utc(2026, 9, 16, 9, 30));

      final view = await _servico(session).forPatient(_patient);

      expect(view.triggeredAt, DateTime.utc(2026, 9, 16, 9, 30));
      expect(view.status, AlertStatus.pending);
    });

    test('INV-05: não devolve o alerta de outro paciente', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      // Só o OUTRO paciente tem alerta.
      await _inserirAlerta(session, patientId: _otherPatientId, triggeredAt: DateTime.utc(2026, 9, 16, 9, 30));

      final view = await _servico(session).forPatient(_patient);

      expect(view.alertId, isNull);
      expect(view.triggeredAt, isNull);
    });

    test('a leitura grava linha real em audit_logs', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      await _inserirAlerta(session, patientId: _patientId, triggeredAt: DateTime.utc(2026, 9, 16, 9, 30));

      await _servico(session).forPatient(_patient);

      final logs = await AuditLog.db.find(session);
      expect(logs, hasLength(1));
      expect(logs.single.actionType, 'read');
      expect(logs.single.resourceType, 'patient_request_status');
      expect(logs.single.result, 'granted');
    });
  });
}
```

- [ ] **Step 2: Subir o Postgres de teste e confirmar que o teste falha**

```bash
docker compose --profile test up -d postgres-test
cd backend/sinalacs_server && dart test test/integration/patient_status_test.dart
```
Expected: FAIL na compilação — `OrmPatientStatusStore isn't defined`.

- [ ] **Step 3: Implementar o store**

Crie `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_status_store.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/patient_status_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [PatientStatusStore] sobre o ORM do Serverpod.
///
/// Sempre filtra por `patientId` — o serviço só passa o id vindo do token, e
/// esta é a consulta onde INV-05 vira SQL.
class OrmPatientStatusStore implements PatientStatusStore {
  OrmPatientStatusStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<Alert?> latestAlertFor(UuidValue patientId) => Alert.db.findFirstRow(
        _session(),
        where: (alert) => alert.patientId.equals(patientId),
        orderBy: (alert) => alert.triggeredAt,
        orderDescending: true,
      );

  @override
  Future<TriageSession?> latestTriageFor(UuidValue patientId) =>
      TriageSession.db.findFirstRow(
        _session(),
        where: (triage) => triage.patientId.equals(patientId),
        orderBy: (triage) => triage.createdAt,
        orderDescending: true,
      );
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/integration/patient_status_test.dart`
Expected: PASS — 3 testes.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_status_store.dart \
        backend/sinalacs_server/test/integration/patient_status_test.dart
git commit -s -m "feat(backend): consultar alerta e triagem mais recentes pelo ORM"
```

---

### Task 3: Endpoint `status.myRequest`

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/api/patient_request_status.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/endpoints/status_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`
- Test: `backend/sinalacs_server/test/integration/patient_status_test.dart` (acrescentar)

**Interfaces:**
- Consumes: `PatientStatusService`, `PatientStatusView`, `StatusAuthorizationException` (Task 1); `OrmPatientStatusStore` (Task 2); `AlertRuntime.instance.auth.verifyToken(String) → AuthenticatedUser?`; `AlertRuntime.instance.auditTrailFor(Session) → AuditTrail`.
- Produces: modelo gerado `PatientRequestStatus`; `AlertRuntime.patientStatusServiceFor(Session) → PatientStatusService`; endpoint `status.myRequest(Session, {required String accessToken}) → Future<PatientRequestStatus>`.

- [ ] **Step 1: Criar o modelo de transporte**

Crie `backend/sinalacs_server/lib/src/models/api/patient_request_status.spy.yaml`:

```yaml
### Status da solicitação corrente do paciente (RF05).
###
### Não é tabela: é só o formato de transporte da leitura feita por
### PatientStatusService. Todos os campos são anuláveis porque um paciente que
### nunca disparou alerta nem fez triagem é caso normal, não erro.
###
### Minimização (spec/lgpd_design.md): locationHash, acsId, microAreaId,
### deviceId, mqttTopic, retryCount e version NÃO aparecem aqui de propósito.
### `acsId` revelaria qual agente foi designado; nenhum deles ajuda o paciente
### a entender onde está o próprio pedido.
class: PatientRequestStatus
fields:
  alertId: String?
  status: AlertStatus?
  riskLevel: RiskLevel?
  triggeredAt: DateTime?
  acknowledgedAt: DateTime?
  lastTriageRisk: RiskLevel?
  lastTriageAt: DateTime?
```

- [ ] **Step 2: Criar o endpoint**

Crie `backend/sinalacs_server/lib/src/endpoints/status_endpoint.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/patient_status_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Acompanhamento da solicitação pelo próprio paciente (RF05).
///
/// Endpoint separado de `patients`, que é a superfície do ACS
/// (`patients.listMicroArea`): a audiência aqui é o paciente, e misturar as
/// duas tornaria o mapeamento de papéis ambíguo quando o RBAC formal (L-09)
/// chegar.
///
/// É o primeiro endpoint de LEITURA voltado ao paciente no sistema. Até ele,
/// INV-05 era verdadeira por vacuidade — não havia o que ler.
class StatusEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<PatientRequestStatus> myRequest(
    Session session, {
    required String accessToken,
  }) async {
    final user = AlertRuntime.instance.auth.verifyToken(accessToken);
    if (user == null) {
      throw AlertPermissionException(message: 'token inválido ou expirado');
    }

    try {
      final view = await AlertRuntime.instance
          .patientStatusServiceFor(session)
          .forPatient(user);

      return PatientRequestStatus(
        alertId: view.alertId,
        status: view.status,
        riskLevel: view.riskLevel,
        triggeredAt: view.triggeredAt,
        acknowledgedAt: view.acknowledgedAt,
        lastTriageRisk: view.lastTriageRisk,
        lastTriageAt: view.lastTriageAt,
      );
    } on StatusAuthorizationException catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
```

- [ ] **Step 3: Adicionar a fábrica no runtime**

Em `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`, acrescente aos imports:

```dart
import 'package:sinalacs_server/src/application/patients/patient_status_service.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_patient_status_store.dart';
```

e o método, logo depois de `patientDirectoryServiceFor`:

```dart
  /// Constrói a leitura de status do paciente para uma requisição.
  PatientStatusService patientStatusServiceFor(Session session) =>
      PatientStatusService(
        store: OrmPatientStatusStore(session: () => session),
        audit: auditTrailFor(session),
      );
```

- [ ] **Step 4: Regenerar o cliente tipado**

```bash
cd backend/sinalacs_server && ~/.pub-cache/bin/serverpod generate
```
Expected: regenera `lib/src/generated/` e `backend/sinalacs_client/lib/src/protocol/` com `PatientRequestStatus` e o endpoint `status`. **Nenhuma migração** — `patient_request_status.spy.yaml` não declara `table:`. Se aparecer uma migração nova, pare e reporte BLOCKED. O CLI está em `~/.pub-cache/bin/serverpod` (3.4.13, a mesma versão do projeto); não rode `dart pub global activate`, e ignore o aviso sobre o Serverpod 4.0.0.

- [ ] **Step 5: Acrescentar os testes de endpoint**

Acrescente estes três testes dentro do `withServerpod` de `test/integration/patient_status_test.dart`, depois dos existentes:

```dart
    test('o endpoint recusa token inválido', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      await expectLater(
        endpoints.status.myRequest(sessionBuilder, accessToken: 'token-que-nao-vale'),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o endpoint recusa quem não é paciente', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

      await expectLater(
        endpoints.status.myRequest(sessionBuilder, accessToken: login.accessToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('o endpoint devolve o status do paciente autenticado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      await _inserirAlerta(
        session,
        patientId: _patientId,
        triggeredAt: DateTime.utc(2026, 9, 16, 9, 30),
        status: AlertStatus.acknowledged,
      );

      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final resultado = await endpoints.status.myRequest(
        sessionBuilder,
        accessToken: login.accessToken,
      );

      expect(resultado.status, AlertStatus.acknowledged);
      expect(resultado.riskLevel, RiskLevel.red);
      expect(resultado.triggeredAt, DateTime.utc(2026, 9, 16, 9, 30));
    });
```

- [ ] **Step 6: Rodar os testes**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — **112 testes**: os 98 que já existiam, mais os 8 unitários da Task 1, mais os 3 de integração da Task 2 e os 3 desta tarefa. A divisão fica 87 unitários + 25 de integração.

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib/src/models/api/patient_request_status.spy.yaml \
        backend/sinalacs_server/lib/src/endpoints/status_endpoint.dart \
        backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
        backend/sinalacs_server/lib/src/generated backend/sinalacs_client/lib/src/protocol \
        backend/sinalacs_server/test/integration/patient_status_test.dart
git commit -s -m "feat(backend): expor status.myRequest para o paciente"
```

---

### Task 4: A tela de Status passa a mostrar a verdade

**Files:**
- Modify: `apps/patient/lib/core/network/backend_client.dart` (interface `PatientBackend` e classe `BackendClient`)
- Modify: `apps/patient/test/support/fake_patient_backend.dart`
- Modify: `apps/patient/lib/app/app.dart` (`StatusScreen`, por volta da linha 676)
- Test: `apps/patient/test/patient_app_mvp_test.dart`

**Interfaces:**
- Consumes: `PatientRequestStatus` do `sinalacs_client` regenerado (Task 3); `BackendClient._requireToken() → Future<String>`, que já existe por volta da linha 80; `BackendScope.of(context) → PatientBackend`.
- Produces: `Future<PatientRequestStatus> myRequestStatus()` na interface `PatientBackend`.

- [ ] **Step 1: Acrescentar o método à interface e ao cliente real**

Em `apps/patient/lib/core/network/backend_client.dart`, dentro de `abstract class PatientBackend`, depois de `createRedAlert`:

```dart
  Future<PatientRequestStatus> myRequestStatus();
```

E em `class BackendClient`, depois do método `createRedAlert`:

```dart
  /// Status da solicitação corrente do paciente autenticado.
  ///
  /// O servidor deriva o paciente do token; o app nunca envia um id (INV-05).
  @override
  Future<PatientRequestStatus> myRequestStatus() async {
    final token = await _requireToken();
    return _guard(() => _client.status.myRequest(accessToken: token));
  }
```

- [ ] **Step 2: Implementar o método no fake (senão os testes de widget param de compilar)**

Em `apps/patient/test/support/fake_patient_backend.dart`, acrescente um campo configurável e o método:

```dart
  /// Status que o "servidor" devolve para a tela de acompanhamento.
  PatientRequestStatus requestStatus = PatientRequestStatus();

  int requestStatusCalls = 0;
```

e, junto dos outros overrides:

```dart
  @override
  Future<PatientRequestStatus> myRequestStatus() async {
    requestStatusCalls++;
    return requestStatus;
  }
```

- [ ] **Step 3: Escrever o teste de widget que falha**

Acrescente a `apps/patient/test/patient_app_mvp_test.dart`:

```dart
  testWidgets('a tela de status mostra a solicitação real do paciente', (tester) async {
    final backend = FakePatientBackend()
      ..requestStatus = PatientRequestStatus(
        alertId: '00000000-0000-4000-8000-0000000000b1',
        status: AlertStatus.acknowledged,
        riskLevel: RiskLevel.red,
        triggeredAt: DateTime.utc(2026, 9, 16, 9, 30),
        acknowledgedAt: DateTime.utc(2026, 9, 16, 9, 34),
      );

    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await tester.tap(find.text('Entrar sem senha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();

    expect(backend.requestStatusCalls, greaterThan(0));
    expect(find.textContaining('Vermelho'), findsWidgets);
    expect(find.textContaining('Visualizado'), findsWidgets);
    // A solicitação fabricada some de vez.
    expect(find.textContaining('#4082'), findsNothing);
  });

  testWidgets('sem solicitação, a tela diz isso em vez de inventar uma', (tester) async {
    final backend = FakePatientBackend()..requestStatus = PatientRequestStatus();

    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await tester.tap(find.text('Entrar sem senha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nenhuma solicitação'), findsWidgets);
    expect(find.textContaining('#4082'), findsNothing);
  });
```

- [ ] **Step 4: Rodar e confirmar que falha**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
Expected: FAIL — a tela ainda é `const` e mostra `#4082`; `myRequestStatus` não existe no fake antes do Step 2.

- [ ] **Step 5: Reescrever a `StatusScreen`**

Em `apps/patient/lib/app/app.dart`, substitua a classe `StatusScreen` inteira (a `const` que começa por volta da linha 676) por:

```dart
/// Acompanhamento da solicitação do paciente (RF05).
///
/// Era uma árvore `const` que anunciava "Solicitação de visita #4082 · Triagem
/// Vermelha" a qualquer pessoa — e o fluxo de triagem leva direto até aqui, de
/// modo que alguém recém-saído dos sintomas via um pedido de socorro
/// "em análise" que nunca existiu. Agora tudo vem de `status.myRequest`.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  Future<PatientRequestStatus>? _pedido;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pedido ??= BackendScope.of(context).myRequestStatus();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PatientRequestStatus>(
      future: _pedido,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final mensagem = snapshot.error is BackendFailure
              ? (snapshot.error as BackendFailure).message
              : 'Não foi possível carregar o acompanhamento.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Semantics(
                liveRegion: true,
                child: Text(mensagem, textAlign: TextAlign.center),
              ),
            ),
          );
        }

        final pedido = snapshot.data!;
        if (pedido.alertId == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Nenhuma solicitação em andamento.\n'
                'Se precisar de ajuda agora, use o botão de urgência.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitação ${_curto(pedido.alertId!)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('${_rotuloRisco(pedido.riskLevel)} • ${_quando(pedido.triggeredAt)}'),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatusStep('Enviado', true),
                        _StatusStep('Visualizado', _pelomenos(pedido.status, AlertStatus.acknowledged)),
                        _StatusStep('Em atendimento', _pelomenos(pedido.status, AlertStatus.escalated)),
                        _StatusStep('Concluído', pedido.status == AlertStatus.resolved),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('Situação', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Semantics(liveRegion: true, child: Text(_situacao(pedido))),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Só os 8 primeiros hexadecimais: o UUID inteiro não ajuda o paciente e
  /// polui a tela.
  static String _curto(String alertId) => '#${alertId.replaceAll('-', '').substring(0, 8)}';

  static String _rotuloRisco(RiskLevel? risco) => switch (risco) {
        RiskLevel.red => 'Triagem Vermelha',
        RiskLevel.yellow => 'Triagem Amarela',
        RiskLevel.green => 'Triagem Verde',
        null => 'Triagem',
      };

  static String _quando(DateTime? instante) {
    if (instante == null) return 'sem data';
    final local = instante.toLocal();
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    return 'criada em $dia/$mes às $hora:$minuto';
  }

  static bool _pelomenos(AlertStatus? atual, AlertStatus alvo) {
    const ordem = [
      AlertStatus.pending,
      AlertStatus.acknowledged,
      AlertStatus.escalated,
      AlertStatus.resolved,
    ];
    if (atual == null) return false;
    return ordem.indexOf(atual) >= ordem.indexOf(alvo);
  }

  static String _situacao(PatientRequestStatus pedido) => switch (pedido.status) {
        AlertStatus.pending => 'Enviado para a equipe da sua microárea. Aguardando confirmação.',
        AlertStatus.acknowledged => 'Um agente de saúde confirmou o recebimento.',
        AlertStatus.escalated => 'Encaminhado para atendimento de urgência.',
        AlertStatus.resolved => 'Atendimento concluído.',
        null => 'Sem situação registrada.',
      };
}
```

A classe `_StatusStep` logo abaixo **permanece como está** — ela já recebe `(label, done)` e não precisa mudar.

- [ ] **Step 6: Rodar os testes do app**

```bash
cd apps/patient && flutter analyze && flutter test
```
Expected: analyze limpo; **21 testes** (19 anteriores + 2 novos).

- [ ] **Step 7: Validar contra a stack real no emulador**

```bash
docker compose up --build -d
cd apps/patient && flutter test integration_test -d emulator-5554 \
  --dart-define=SINALACS_HOST=http://10.0.2.2:8080/
```
Expected: PASS — os 7 testes de integração existentes continuam passando (eles não exercitam a tela de status, mas provam que o cliente regenerado ainda fala com o servidor).

- [ ] **Step 8: Commit**

```bash
git add apps/patient/lib/core/network/backend_client.dart \
        apps/patient/test/support/fake_patient_backend.dart \
        apps/patient/lib/app/app.dart \
        apps/patient/test/patient_app_mvp_test.dart
git commit -s -m "feat(patient): mostrar o status real da solicitação em vez de dado fabricado"
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

A lista de endpoints vive no parágrafo que começa com `**Serverpod is RPC, not REST**`. Não tente reescrever a lista inteira — ela é uma sentença longa com parênteses aninhados. Em vez disso, localize esta frase, que vem logo depois da descrição de `patients.listMicroArea` e fecha a enumeração:

```
Errors are typed exceptions declared in `.spy.yaml` and serialized to the client, replacing HTTP status codes.
```

Insira o texto abaixo IMEDIATAMENTE ANTES dessa frase, como uma sentença nova:

```
`status.myRequest` (RF05) devolve ao PACIENTE autenticado o status do próprio alerta mais recente e da própria triagem mais recente; o `patientId` vem do token, nunca de parâmetro. É o primeiro endpoint de leitura voltado ao paciente, e é onde INV-05 deixou de ser vacuamente verdadeira. O DTO é minimizado: não carrega `locationHash`, `acsId`, `microAreaId`, `deviceId`, `mqttTopic`, `retryCount` nem `version`.
```

- [ ] **Step 2: Corrigir a contagem de testes em `backend/CLAUDE.md`**

O arquivo contém este trecho, já desatualizado em DOIS graus: o plano anterior o escreveu como `96`, e depois a própria onda de correção daquele plano acrescentou 2 testes unitários sem mexer aqui. O texto literal atualmente no arquivo é:

```
96 tests: 77 unit + 19 integration
```

Substitua por:

```
112 tests: 87 unit + 25 integration
```

Confirme esse total contra o que você observou na Task 3 Step 6 antes de escrever — se divergir, escreva o número real, não este.

- [ ] **Step 3: Atualizar o relatório de validação**

Em `spec/validation_report.md`, §3, substitua a linha RF05 por:

```markdown
| RF05 | Painel de status da solicitação | **backend** | `status.myRequest` devolve o alerta e a triagem mais recentes do paciente autenticado; a tela deixou de ser `const` e consome o endpoint. |
```

e a linha INV-05 por:

```markdown
| INV-05 | Paciente não acessa dado de outro paciente | **aplicado** | `status.myRequest` deriva o `patientId` do token e nunca aceita parâmetro; `OrmPatientStatusStore` filtra por esse id em ambas as consultas. Teste de integração prova que o alerta de outro paciente não é devolvido. |
```

Em §5, substitua a linha da tela de Status do paciente por:

```markdown
| Paciente | **Status** | **real** | Consome `status.myRequest`; sem solicitação, diz que não há, em vez de inventar uma. |
```

Em §8, substitua a linha de L-03 por:

```markdown
- **L-03 · ~~Tela de Status mente para o paciente.~~** RESOLVIDO — a tela consome
  `status.myRequest` e mostra a solicitação real do próprio paciente. Ver
  `docs/superpowers/plans/2026-09-16-status-real-do-paciente.md`.
```

Em §4, acrescente uma linha à tabela de consumo, mantendo a forma de colunas das vizinhas:

```markdown
| `status.myRequest` | ✅ `backend_client.dart` | — | ❌ |
```

e atualize a linha de cobertura para:

```markdown
| **Cobertura** | **5/8** | **5/8** | **0/8** |
```

- [ ] **Step 4: Rodar a bateria completa uma última vez**

```bash
cd backend && dart analyze
cd sinalacs_server && dart test
cd ../../apps/patient && flutter analyze && flutter test
```
Expected: analyze limpo nos dois; backend com o total da Task 3; app do paciente com 21.

- [ ] **Step 5: Commit**

```bash
git add backend/CLAUDE.md spec/validation_report.md
git commit -s -m "docs: registrar status.myRequest e fechar L-03"
```

---

## Fora de escopo (planos separados)

| Subsistema | Lacunas | Por que separado |
|---|---|---|
| Endpoints do backoffice | L-01 | Outro consumidor, outra audiência; agora desbloqueado pelos dados de triagem. |
| Geolocalização no alerta | L-02 | App do paciente + permissões de GPS; não depende deste plano. |
| RBAC formal | L-09, RNF06 | Transversal; unificaria `StatusAuthorizationException` e `TriageAuthorizationException`. |
| Histórico de triagens do paciente | — | Esta tela mostra a solicitação corrente; histórico é requisito distinto. |
| Demais telas fabricadas do paciente | §5 | Perguntas, Perfil clínico e Lembretes não têm endpoint nem tabela. |
| Consentimento LGPD | `consent_logs` morta | Independente. |
| TLS no RPC | L-08, RNF04 | Infraestrutura. |
| Criptografia de coluna | RNF03, INV-04 servidor | Decisão de produto antes de código. |
