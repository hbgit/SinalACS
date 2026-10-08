# Issue #40 — Endpoints de backend para o backoffice — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o `MockAdminDataSource` por dados reais: um endpoint `admin` somente leitura, protegido por papel de staff, com indicadores (contagens por risco e TMRAV), microáreas, alertas e auditoria paginados, com minimização de PII e leitura auditada em `audit_logs`.

**Architecture:** `AdminEndpoint extends AuthenticatedEndpoint` exige `Authorization.staffRoles` (`requireMicroArea: false`), resolve o **escopo** do chamador (administrador = sistema inteiro; coordenador = a sua UBS, vinda de `staff_accounts.ubsId`, e sem UBS é recusado) e delega a um `AdminReadService` sobre uma interface `AdminReadStore` (implementação ORM/SQL). Cada leitura grava um `AuditEvent` **antes** de devolver dado (falha de auditoria = sem dado). No app, `BackendAdminDataSource` implementa `AdminDataSource` sobre o `sinalacs_client` com o token da sessão.

**Tech Stack:** Dart/Serverpod 3.4.13 (migrações, `dart test` com `postgres-test`), Flutter (`apps/admin`), `scripts/qa/admin_login_e2e.sh` no emulador.

**Spec:** Issue #40 (`gh issue view 40`); `spec/PRD_system.md` §4.2.2 (matriz de permissões) e §1.3 (TMRAV); `spec/lgpd_design.md` (minimização, RBAC); `backend/CLAUDE.md` (bloco Staff, `Authorization.staffRoles`); `PROGRESS.md` seção "Ativação do TOTP do staff (#48)".

## Global Constraints

- **Pré-requisito:** a #40 não pode ser entregue antes da #48 (comentário da issue). Executar a partir de `develop` **depois** do merge do PR #50.
- Só leitura: nenhum endpoint do `admin` escreve em tabela de domínio; a única escrita é a linha de auditoria.
- Papéis aceitos: `coordinator` e `admin` (`Authorization.staffRoles`). `acs` e `patient` recebem `AlertPermissionException`, inclusive com token válido.
- Escopo (PRD §4.2.2): `admin` vê o sistema; `coordinator` vê só a UBS de `staff_accounts.ubsId`; coordenador **sem** UBS é recusado (fail-closed).
- Minimização de PII: nenhum nome, CPF, telefone ou endereço de paciente na resposta. `patientLabel` = `#` + últimos 4 hex do UUID, em maiúsculas (ex.: `#A18F`); é rótulo, não identificador.
- `AuditLog`: nunca devolver `ipHash`, `previousHash`, `entryHash`.
- TMRAV: média de `acknowledgedAt − triggeredAt`, em segundos inteiros, dos alertas **vermelhos** com `acknowledgedAt` não nulo e `triggeredAt` nos últimos 30 dias; sem nenhum, `null`.
- Paginação: `limit` de 1 a 100 (padrão 50). Fora disso, `AdminInvalidRequestException` com a mensagem `Parâmetro de paginação inválido.` (não é erro de permissão).
- Dados sintéticos apenas; nada de dado real em teste, log ou captura.
- Migração só aditiva. Não editar `generated/` nem `migrations/` à mão (`serverpod generate` / `serverpod create-migration`, com `PATH` incluindo `~/.pub-cache/bin`).
- Commits sem `Co-Authored-By` e sem "Generated with Claude Code". PR contra `develop`.
- `scripts/qa/e2e_stack.sh up` recria os containers de dev e o ambiente recusa que o agente o rode: o usuário roda com `!`. Testes em aparelho: emulador `emulator-5554` (AVD `Medium_Phone`); o celular `0087014315` é opcional.

## Review Focus

- Coordenador de UBS A nunca vê alerta, microárea ou indicador da UBS B (teste com duas UBS).
- Coordenador sem `ubsId` é recusado em **todos** os métodos, não só em alguns.
- Token de `acs`/`patient` (inclusive com microárea) recusado em todos os métodos; token expirado/adulterado também.
- Paginação: página além do fim devolve lista vazia e `nextOffset == null`; `limit` 0, 101 e negativo recusados; ordem estável com `triggeredAt` repetido (desempate por `id`).
- Auditoria: cada leitura grava exatamente uma linha (`read`, recurso `admin_*`, `result: success`); recusa por papel grava `denied`; se a gravação da auditoria falha, nenhuma linha de dado sai.
- Sem alerta vermelho reconhecido: `tmravSeconds` é `null` e a tela mostra "—", nunca "0s".
- A resposta de auditoria não vaza hash nem IP, e o rótulo do usuário não contém CPF/nome de paciente.

---

## File Structure

- Modify: `backend/sinalacs_server/lib/src/models/staff_account.spy.yaml` — `ubsId: UuidValue?`.
- Create: `backend/sinalacs_server/lib/src/models/api/admin_*.spy.yaml` — 6 modelos de resposta (ver Task 1).
- Create: `backend/sinalacs_server/lib/src/models/exceptions/admin_invalid_request_exception.spy.yaml`.
- Create: `backend/sinalacs_server/lib/src/application/admin/admin_labels.dart` — rótulos minimizados (puro).
- Create: `backend/sinalacs_server/lib/src/application/admin/admin_read_service.dart` — escopo, paginação, auditoria; interface `AdminReadStore`.
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart` — SQL.
- Create: `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart`; Modify: `lib/src/runtime/alert_runtime.dart` (`adminReadServiceFor`).
- Modify: `apps/admin/lib/core/data/admin_data_source.dart`, `mock_admin_data_source.dart`, `lib/app/app.dart`, `lib/app/login_screen.dart`; Create: `apps/admin/lib/core/data/backend_admin_data_source.dart`.
- Modify: `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart`, `bin/seed_e2e_fixtures.dart`, `apps/admin/integration_test/admin_login_e2e.dart`, `scripts/qa/admin_login_e2e.sh`.
- Modify: `backend/CLAUDE.md`, `apps/CLAUDE.md`, `PROGRESS.md`, `docs/telas-admin.md`, `spec/lgpd_data_audit.md` (se citar `staff_accounts`).
- Tests: `test/unit/admin_labels_test.dart`, `test/unit/admin_read_service_test.dart`, `test/integration/admin_read_store_test.dart`, `test/integration/admin_endpoint_test.dart`, `test/unit/endpoint_auth_posture_test.dart`, `apps/admin/test/backend_admin_data_source_test.dart` e as telas.

---

### Task 0: Pré-requisitos e confirmação da lacuna

**Files:** nenhum modificado.

- [ ] **Step 1: Conferir que a #48 está em `develop`**

Run: `gh pr view 50 --json state,mergedAt -q '.state+" "+(.mergedAt//"")'; git fetch -q origin && git log origin/develop --oneline | grep -c "#48"`
Expected: `MERGED …` e contagem ≥ 1. Se o PR ainda estiver aberto, **parar**: a #40 depende dele.

- [ ] **Step 2: Branch a partir de `develop`**

Run: `git switch develop && git pull --ff-only && git switch -c feat/admin-endpoints-40`
Expected: branch nova.

- [ ] **Step 3: Provar a lacuna**

Run:
```bash
ls backend/sinalacs_server/lib/src/endpoints | grep -c admin
grep -rn "staffRoles" backend/sinalacs_server/lib/src/endpoints | wc -l
grep -n "MockAdminDataSource()" apps/admin/lib/app/app.dart
```
Expected: `0`, `0` e a linha do `app.dart`. Confirma: nenhum endpoint `admin`, nenhum uso de `staffRoles`, app ainda no mock.

- [ ] **Step 4: Linha de base**

Run: `(cd backend/sinalacs_server && dart test 2>&1 | tail -1); (cd apps/admin && flutter test 2>&1 | tail -1)`
Expected: ambas verdes. Anotar as contagens para comparar no fim.

---

### Task 1: Modelos, migração e `ubsId` do staff

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/staff_account.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/admin_indicators.spy.yaml`, `admin_micro_area.spy.yaml`, `admin_alert.spy.yaml`, `admin_alert_page.spy.yaml`, `admin_audit_entry.spy.yaml`, `admin_audit_page.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/exceptions/admin_invalid_request_exception.spy.yaml`
- Regenerate: `generated/`, `sinalacs_client`, `migrations/`

**Interfaces:**
- Produces (classes Dart geradas, usadas em todas as tarefas seguintes):
  - `AdminIndicators{ int red; int yellow; int green; int openRedAlerts; int acknowledgedRedAlerts; int? tmravSeconds; }`
  - `AdminMicroArea{ String id; String name; String acsName; String acsEnrollmentId; bool acsActive; }`
  - `AdminAlert{ String id; String patientLabel; String microAreaName; RiskLevel riskLevel; AlertStatus status; DateTime triggeredAt; }`
  - `AdminAlertPage{ List<AdminAlert> items; int? nextOffset; }`
  - `AdminAuditEntry{ String id; int sequence; String userLabel; String actionType; String resourceType; DateTime timestamp; String result; }`
  - `AdminAuditPage{ List<AdminAuditEntry> items; int? nextBeforeSequence; }`
  - `AdminInvalidRequestException{ String message; }`
  - `StaffAccount.ubsId: UuidValue?`

- [ ] **Step 1: Escrever os modelos**

`staff_account.spy.yaml`: depois de `active: bool`, acrescentar `  ubsId: UuidValue?` (comentário: `### UBS do coordenador; nulo para administrador. Coordenador sem UBS é recusado.`).

Cada `api/admin_*.spy.yaml` segue o formato dos existentes em `models/api/` (ler um deles antes). Exemplo:
```yaml
class: AdminAlert
fields:
  id: String
  patientLabel: String
  microAreaName: String
  riskLevel: RiskLevel
  status: AlertStatus
  triggeredAt: DateTime
```
e os outros com os campos da lista acima (`List<AdminAlert>` em `AdminAlertPage.items`, `int?` em `nextOffset`). A exceção segue `models/exceptions/mfa_enrollment_required_exception.spy.yaml`:
```yaml
class: AdminInvalidRequestException
serverOnly: false
fields:
  message: String
```
(copiar as chaves exatas do arquivo-modelo; se ele não tiver `serverOnly`, não acrescentar.)

- [ ] **Step 2: Gerar e conferir**

Run:
```bash
cd backend/sinalacs_server && export PATH="$PATH:$HOME/.pub-cache/bin" && serverpod generate && serverpod create-migration
git status --short | head -20; grep -c DROP migrations/$(ls migrations | grep -v registry | tail -1)/migration.sql
```
Expected: arquivos gerados do servidor e do cliente; migração com `ALTER TABLE "staff_accounts" ADD COLUMN "ubsId" uuid;` e **0** `DROP`.

- [ ] **Step 3: Compilar e rodar a suíte**

Run: `dart analyze lib | tail -2; dart test 2>&1 | tail -1`
Expected: sem erros novos; suíte verde (nada usa os modelos ainda).

- [ ] **Step 4: Commit**

```bash
git add backend && git commit -m "feat(db): modelos de resposta do admin e ubsId do staff (#40)"
```

---

### Task 2: Rótulos minimizados (função pura)

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/admin/admin_labels.dart`
- Test: `backend/sinalacs_server/test/unit/admin_labels_test.dart`

**Interfaces:**
- Produces: `abstract final class AdminLabels { static String patient(String patientId); static String user({required String role, required String id, String? enrollmentId}); }`
  - `patient('5b6f…a18f')` → `#A18F`; id com menos de 4 caracteres → `#????`.
  - `user(role: 'patient', id: …)` → `Paciente #A18F`; `user(role: 'acs'|'coordinator'|'admin', enrollmentId: 'ADM-001')` → `ADM-001 (Administrador)` / `(ACS)` / `(Coordenador)`; sem matrícula → `<Papel> #A18F`.

- [ ] **Step 1: Teste que falha**

```dart
import 'package:sinalacs_server/src/application/admin/admin_labels.dart';
import 'package:test/test.dart';

void main() {
  const id = '5b6f2c1e-0000-4000-8000-00000000a18f';
  test('rótulo do paciente = # + últimos 4 hex em maiúsculas', () {
    expect(AdminLabels.patient(id), '#A18F');
    expect(AdminLabels.patient('abc'), '#????');
  });
  test('rótulo do usuário nunca contém nome; paciente vira Paciente #XXXX', () {
    expect(AdminLabels.user(role: 'patient', id: id), 'Paciente #A18F');
    expect(AdminLabels.user(role: 'admin', id: id, enrollmentId: 'ADM-001'), 'ADM-001 (Administrador)');
    expect(AdminLabels.user(role: 'acs', id: id, enrollmentId: 'ACS-001'), 'ACS-001 (ACS)');
    expect(AdminLabels.user(role: 'coordinator', id: id), 'Coordenador #A18F');
  });
  test('paciente ignora matrícula (não há matrícula de paciente a mostrar)', () {
    expect(AdminLabels.user(role: 'patient', id: id, enrollmentId: 'X'), 'Paciente #A18F');
  });
}
```

- [ ] **Step 2: Rodar e ver falhar** — `dart test test/unit/admin_labels_test.dart` → FAIL (arquivo inexistente).

- [ ] **Step 3: Implementar**

```dart
/// Rótulos minimizados do backoffice (spec/lgpd_design.md): o admin identifica,
/// não qualifica. Nunca recebe nem devolve nome, CPF ou contato.
abstract final class AdminLabels {
  static String _sufixo(String id) {
    final limpo = id.replaceAll('-', '');
    return limpo.length < 4 ? '????' : limpo.substring(limpo.length - 4).toUpperCase();
  }

  static String patient(String patientId) => '#${_sufixo(patientId)}';

  static const _papeis = {
    'admin': 'Administrador',
    'coordinator': 'Coordenador',
    'acs': 'ACS',
    'patient': 'Paciente',
  };

  static String user({required String role, required String id, String? enrollmentId}) {
    final papel = _papeis[role] ?? role;
    if (role == 'patient') return 'Paciente ${patient(id)}';
    if (enrollmentId != null && enrollmentId.isNotEmpty) return '$enrollmentId ($papel)';
    return '$papel ${patient(id)}';
  }
}
```

- [ ] **Step 4: Rodar e ver passar** — `dart test test/unit/admin_labels_test.dart` → 3 testes.

- [ ] **Step 5: Commit** — `git add backend && git commit -m "feat(admin): rótulos minimizados de paciente e usuário (#40)"`

---

### Task 3: Store de leitura (SQL) contra Postgres

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/admin/admin_read_service.dart` (só a interface e o tipo de escopo, nesta tarefa)
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart`
- Test: `backend/sinalacs_server/test/integration/admin_read_store_test.dart`

**Interfaces:**
- Produces (em `admin_read_service.dart`):
```dart
/// Até onde o chamador enxerga. `ubsId == null` = sistema inteiro (administrador).
class AdminScope {
  const AdminScope.system() : ubsId = null;
  const AdminScope.ubs(String this.ubsId);
  final String? ubsId;
}

abstract interface class AdminReadStore {
  Future<AdminIndicators> indicators(AdminScope scope, {required DateTime now});
  Future<List<AdminMicroArea>> microAreas(AdminScope scope);
  Future<AdminAlertPage> alerts(AdminScope scope, {String? microAreaId, AlertStatus? status, required int limit, required int offset});
  Future<AdminAuditPage> auditLogs({required int limit, int? beforeSequence});
  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOf(String staffId);
}
```
- `OrmAdminReadStore({required Session Function() session})` implementa `AdminReadStore`.

Os SQLs usam `session.db.unsafeQuery(sql, parameters: QueryParameters.named({...}))` (padrão de `orm_alert_outbox.dart`); enums `byName` são texto (`'red'`, `'pending'`…); colunas camelCase entre aspas.

- [ ] **Step 1: Teste que falha**

Seguir o harness de `staff_activation_store_test.dart` (`withServerpod`, UUIDs próprios `…0000d1..`). `_seed` cria: 2 UBS (`ubsA`, `ubsB`), 1 microárea em cada, 1 ACS (`users`+`acs`) na área A com nome sintético, 1 paciente por área (`users`+`patients`; ler `patient.spy.yaml` para os campos obrigatórios) e alertas **determinísticos** na área A: vermelho `pending` (triggeredAt T), vermelho `acknowledged` (triggeredAt T−2h, acknowledgedAt T−2h+60s), vermelho `acknowledged` (T−1h, +120s), amarelo e verde `pending`; e 1 vermelho `pending` na área B. Casos:

```dart
test('indicadores do sistema contam por risco e calculam o TMRAV', () async {
  final r = await store.indicators(const AdminScope.system(), now: t);
  expect(r.red, 4); expect(r.yellow, 1); expect(r.green, 1);
  expect(r.openRedAlerts, 2);            // A pending + B pending
  expect(r.acknowledgedRedAlerts, 2);
  expect(r.tmravSeconds, 90);            // média de 60 s e 120 s
});
test('indicadores da UBS A não enxergam a UBS B', () async {
  final r = await store.indicators(AdminScope.ubs(_ubsA), now: t);
  expect(r.red, 3); expect(r.openRedAlerts, 1);
});
test('TMRAV é null sem vermelho reconhecido e ignora alerta fora de 30 dias', ...);
test('microáreas trazem o ACS vinculado e respeitam a UBS', ...);   // A: 1 item; sistema: 2
test('alertas: ordem triggeredAt desc, id desc; rótulo do paciente, sem PII', () async {
  final p = await store.alerts(const AdminScope.system(), limit: 3, offset: 0);
  expect(p.items, hasLength(3)); expect(p.nextOffset, 3);
  expect(p.items.first.patientLabel, matches(RegExp(r'^#[0-9A-F]{4}$')));
  final fim = await store.alerts(const AdminScope.system(), limit: 3, offset: 3);
  expect(fim.items, hasLength(3)); expect(fim.nextOffset, isNull);
});
test('alertas filtram por microárea e status e respeitam a UBS', ...);
test('auditoria: sequence desc, keyset por beforeSequence, sem hash nem IP', () async {
  final p = await store.auditLogs(limit: 2);
  expect(p.items, hasLength(2)); expect(p.nextBeforeSequence, p.items.last.sequence);
  final proxima = await store.auditLogs(limit: 2, beforeSequence: p.nextBeforeSequence);
  expect(proxima.items.first.sequence, lessThan(p.items.last.sequence));
});
test('ubsOf devolve a UBS do coordenador e null para administrador', ...);
```
O `_seed` das linhas de `audit_logs` usa `AuditTrail` real (`AlertRuntime.instance.auditTrailFor(session)`) para respeitar a cadeia de hash.

- [ ] **Step 2: Rodar e ver falhar** — `dart test test/integration/admin_read_store_test.dart` → erro de compilação (tipos inexistentes).

- [ ] **Step 3: Implementar o store**

Pontos que o implementador precisa respeitar:
```dart
// Filtro de escopo, comum às consultas: alerta -> micro_areas.ubsId.
// Sistema: sem filtro. UBS: "AND m.\"ubsId\" = @ubs".
const _escopoAlerta = '(@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)';

// Indicadores — uma única instrução:
//   SELECT
//     count(*) FILTER (WHERE a."riskLevel"='red'),
//     count(*) FILTER (WHERE a."riskLevel"='yellow'),
//     count(*) FILTER (WHERE a."riskLevel"='green'),
//     count(*) FILTER (WHERE a."riskLevel"='red' AND a."status"='pending'),
//     count(*) FILTER (WHERE a."riskLevel"='red' AND a."status"='acknowledged'),
//     round(avg(extract(epoch FROM (a."acknowledgedAt" - a."triggeredAt")))
//       FILTER (WHERE a."riskLevel"='red' AND a."acknowledgedAt" IS NOT NULL
//               AND a."triggeredAt" >= @since))::int
//   FROM alerts a LEFT JOIN micro_areas m ON m.id = a."microAreaId"
//   WHERE (@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)
// `@since` = now - 30 dias (parâmetro, não `now()` do banco: o teste fixa o relógio).
```
- `microAreas`: `micro_areas m LEFT JOIN users u ON u."microAreaId" = m.id AND u.role='acs' LEFT JOIN acs ON acs.id = u.id`; nome do ACS vem de `users.name` (nome do **profissional**, não de paciente; permitido), `acsEnrollmentId` de `acs.enrollmentId`, `acsActive` de `acs.active`; sem ACS → `acsName='Sem ACS vinculado'`, `acsEnrollmentId='—'`, `acsActive=false` (igual ao mock).
- `alerts`: `ORDER BY a."triggeredAt" DESC, a.id DESC LIMIT @limit+1 OFFSET @offset`; se vierem `limit+1` linhas, descartar a última e `nextOffset = offset + limit`.
- `auditLogs`: `ORDER BY l.sequence DESC LIMIT @limit+1`, `WHERE (@before::bigint IS NULL OR l.sequence < @before)`; `userLabel` via `AdminLabels.user(role, id, enrollmentId)` com `LEFT JOIN users u` e `LEFT JOIN acs`/`staff_accounts` para a matrícula. **Selecionar só** `id, sequence, userId, actionType, resourceType, timestamp, result`.
- `ubsOf`: `StaffAccount.db.findById` → `ubsId?.toString()`.
- Montar `AdminAlert`/`AdminAuditEntry` a partir das linhas (índices por posição, como em `orm_alert_outbox.dart`); `riskLevel`/`status` com `RiskLevel.fromJson`/`AlertStatus.fromJson` (conferir o nome do construtor gerado em `generated/risk_level.dart`).

- [ ] **Step 4: Rodar e ver passar** — `dart test test/integration/admin_read_store_test.dart && dart analyze lib/src/infrastructure/database/orm_admin_read_store.dart | tail -2` → verde, sem avisos novos.

- [ ] **Step 5: Commit** — `git add backend && git commit -m "feat(admin): store de leitura com escopo, paginação e TMRAV (#40)"`

---

### Task 4: Serviço, endpoint, papéis e auditoria da leitura

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/admin/admin_read_service.dart` (acrescentar `AdminReadService`)
- Create: `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (`adminReadServiceFor`), `test/unit/endpoint_auth_posture_test.dart` se a allowlist exigir
- Test: `backend/sinalacs_server/test/unit/admin_read_service_test.dart`, `test/integration/admin_endpoint_test.dart`

**Interfaces:**
- Consumes: `AdminReadStore`, `AdminScope` (Task 3); `AuditEvent`/`AuditTrail.record`.
- Produces:
```dart
class AdminReadService {
  AdminReadService({required AdminReadStore store, required AuditTrail audit, DateTime Function()? clock});
  Future<AdminIndicators> indicators(AuthenticatedUser user);
  Future<List<AdminMicroArea>> microAreas(AuthenticatedUser user);
  Future<AdminAlertPage> alerts(AuthenticatedUser user, {String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0});
  Future<AdminAuditPage> auditLogs(AuthenticatedUser user, {int limit = 50, int? beforeSequence});
}
```
e o endpoint `AdminEndpoint` com `indicators`, `microAreas`, `alerts`, `auditLogs`, todos `(Session, {required String accessToken, …})`.
Regras do serviço: (a) papel fora de `staffRoles` → `AlertPermissionException` + auditoria `denied` (`resourceType` do método); (b) `admin` → `AdminScope.system()`; (c) `coordinator` → `ubsOf(user.id)`; `null` → `AlertPermissionException` + `denied`; (d) `auditLogs` só para `admin` (coordenador recebe `AlertPermissionException`: a visão por UBS dos logs fica para a #43) — **decisão a confirmar**; (e) `limit` fora de 1..100 → `AdminInvalidRequestException`; (f) `await audit.record(AuditEvent(userId: user.id, actionType: 'read', resourceType: 'admin_<método>', result: 'success'))` **antes** de chamar o store; se `record` lançar, a exceção propaga e o store não é chamado.

- [ ] **Step 1: Testes de unidade que falham** (`admin_read_service_test.dart`, com `FakeAdminReadStore` e `RecordingAudit` de `test/support/institutional_auth_fixtures.dart`)

```dart
test('admin lê com escopo de sistema e a leitura é auditada ANTES do dado', ...);   // ordem: audit.events.length==1 antes de store.chamadas
test('coordenador lê só a sua UBS', ...);                                            // store.ultimoEscopo.ubsId == 'ubs-a'
test('coordenador sem UBS é recusado em indicators, microAreas, alerts', ...);       // 3 expects
test('coordenador não lê auditoria (só admin)', ...);
test('acs e patient são recusados em todos os métodos e a recusa é auditada', ...);  // result 'denied'
test('se a auditoria falha, o store não é chamado', () async {
  audit.falhar = true;
  await expectLater(servico.alerts(admin), throwsA(anything));
  expect(store.chamadas, 0);
});
test('limit 0, 101 e -1 são recusados com a mensagem de paginação', ...);
```

- [ ] **Step 2: Rodar e ver falhar** → erro de compilação.

- [ ] **Step 3: Implementar o serviço**

```dart
class AdminReadService {
  AdminReadService({required this.store, required this.audit, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final AdminReadStore store;
  final AuditTrail audit;
  final DateTime Function() _clock;

  static const _negado = 'acesso restrito ao backoffice';

  Future<AdminScope> _escopo(AuthenticatedUser user, String recurso) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      await _auditar(user, recurso, 'denied');
      throw AlertPermissionException(message: _negado);
    }
    if (user.role == UserRole.admin) return const AdminScope.system();
    final ubs = await store.ubsOf(user.id);
    if (ubs == null) {
      await _auditar(user, recurso, 'denied');
      throw AlertPermissionException(message: _negado);
    }
    return AdminScope.ubs(ubs);
  }

  Future<void> _auditar(AuthenticatedUser user, String recurso, String result) =>
      audit.record(AuditEvent(userId: user.id, actionType: 'read', resourceType: recurso, result: result));
  // …cada método: escopo -> validação de limit -> _auditar(...,'success') -> store.
}
```
`Authorization.require(user, roles: Authorization.staffRoles, requireMicroArea: false, onDenied: …)` pode substituir a checagem manual **se** a auditoria da recusa for mantida (a regra (a) exige gravar `denied` antes de lançar).

- [ ] **Step 4: Endpoint e fiação**

```dart
class AdminEndpoint extends AuthenticatedEndpoint {
  Future<AdminIndicators> indicators(Session session, {required String accessToken}) =>
      AlertRuntime.instance.adminReadServiceFor(session).indicators(authenticate(accessToken));
  Future<List<AdminMicroArea>> microAreas(Session session, {required String accessToken}) =>
      AlertRuntime.instance.adminReadServiceFor(session).microAreas(authenticate(accessToken));
  Future<AdminAlertPage> alerts(Session session,
          {required String accessToken, String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0}) =>
      AlertRuntime.instance.adminReadServiceFor(session).alerts(authenticate(accessToken),
          microAreaId: microAreaId, status: status, limit: limit, offset: offset);
  Future<AdminAuditPage> auditLogs(Session session,
          {required String accessToken, int limit = 50, int? beforeSequence}) =>
      AlertRuntime.instance.adminReadServiceFor(session).auditLogs(authenticate(accessToken),
          limit: limit, beforeSequence: beforeSequence);
}
```
`adminReadServiceFor(Session session)` no `AlertRuntime`: `AdminReadService(store: OrmAdminReadStore(session: () => session), audit: auditTrailFor(session))`. Depois `serverpod generate`.

- [ ] **Step 5: Teste de integração do endpoint (falha → passa)**

`admin_endpoint_test.dart` com tokens reais (`AlertRuntime.instance.auth.issueToken(...)`, como em `staff_login_test.dart`), 2 UBS, 1 admin, 1 coordenador por UBS, 1 coordenador sem UBS, 1 ACS com microárea, 1 paciente. Casos:
```dart
test('admin lê os quatro endpoints e cada leitura vira uma linha read/success em audit_logs', ...);
test('coordenador da UBS A não vê a UBS B (alerts, microAreas, indicators)', ...);
test('coordenador sem UBS recebe AlertPermissionException nos quatro', ...);
test('acs e patient com token válido recebem AlertPermissionException nos quatro', ...);
test('token adulterado e token expirado são recusados', ...);
test('auditoria não devolve hash nem IP: o JSON da resposta não contém entryHash/ipHash/previousHash', () async {
  final j = jsonEncode((await endpoints.admin.auditLogs(sb, accessToken: t)).toJson());
  expect(j, isNot(contains('Hash'))); expect(j, isNot(contains('ip')));
});
test('a resposta de alertas não contém nome nem CPF do paciente semeado', ...);   // nome sintético distintivo
test('página além do fim: items vazio e nextOffset null', ...);
```
Atualizar `endpoint_auth_posture_test.dart` só se ele exigir inscrição do endpoint novo (ele já classifica `AuthenticatedEndpoint` como autenticado).

- [ ] **Step 6: Rodar tudo** — `dart test 2>&1 | tail -2; dart analyze lib | tail -1` → verde.

- [ ] **Step 7: Commit** — `git add backend && git commit -m "feat(admin): endpoint admin somente leitura com papel, escopo e auditoria (#40)"`

---

### Task 5: App admin sobre o backend real

**Files:**
- Modify: `apps/admin/lib/core/data/admin_data_source.dart`, `mock_admin_data_source.dart`, `apps/admin/lib/app/app.dart`, `login_screen.dart`
- Create: `apps/admin/lib/core/data/backend_admin_data_source.dart`
- Test: `apps/admin/test/backend_admin_data_source_test.dart` e ajustes em `alerts_screen_test.dart`, `alerts_filter_dynamic_test.dart`, `mock_admin_data_source_test.dart`, `audit_log_screen_test.dart`, `micro_areas_screen_test.dart`, `error_handling_test.dart`

**Interfaces:**
- Consumes: cliente gerado `client.admin.indicators/microAreas/alerts/auditLogs` (Task 4) e `AdminSession.accessToken`.
- Produces — mudanças na interface `AdminDataSource` (o mock acompanha):
  - `DashboardIndicators.tmravSeconds` passa a `int?` (a tela mostra `—` quando nulo).
  - `Future<List<AlertSummary>> fetchAlerts({String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0})` e `Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50})`; `MicroAreaSummary.id` (já existe) é o filtro.
  - `recordAccess` **permanece** na interface; `BackendAdminDataSource.recordAccess` é no-op **documentado**: o servidor já audita cada leitura (a chamada não vira escrita duplicada).
  - `typedef AdminDataSourceFactory = AdminDataSource Function(AdminSession session);`; `SinalAdminApp({AdminDataSourceFactory? dataSourceFor, required auth})` — default `(_) => MockAdminDataSource()` **somente** para testes de widget; `main.dart` passa `BackendAdminDataSource.forSession`.
  - `class BackendAdminDataSource implements AdminDataSource { BackendAdminDataSource({required AdminEndpointCaller caller, required String accessToken}); }` onde `AdminEndpointCaller` é a costura de teste (como `BackendAdminAuth`/`FakeEndpointCaller`): `Future<T> call<T>(Future<T> Function(EndpointAdmin admin) f)`.

- [ ] **Step 1: Testes que falham**

`backend_admin_data_source_test.dart` com um caller falso: (a) `fetchDashboardIndicators` mapeia `red/yellow/green` para `countsByRisk` e `tmravSeconds: null` permanece nulo; (b) `fetchAlerts(microAreaId: 'x')` passa o filtro e o token; (c) `AlertPermissionException` vira `AdminAuthFailure('Acesso restrito ao backoffice.')` (sem texto do servidor); (d) `SocketException` vira `AdminAuthFailure('Não foi possível conectar ao servidor.')`; (e) `recordAccess` não chama o servidor. Teste de widget: indicadores com `tmravSeconds: null` mostram `—` e **não** `0s`.

- [ ] **Step 2: Rodar e ver falhar** — `cd apps/admin && flutter test test/backend_admin_data_source_test.dart` → FAIL.

- [ ] **Step 3: Implementar**

Mapear `AdminIndicators` → `DashboardIndicators` (`{RiskLevel.red: r.red, …}`), `AdminAlert` → `AlertSummary` (enum do cliente → enum local por nome), `AdminAuditEntry` → `AuditLogEntry`. `LoginScreen` passa a receber `dataSourceFor` e cria `dataSourceFor(session)` ao abrir o `AdminHomeShell`. Na tela de alertas trocar `microAreaName` por `microAreaId` no filtro (o dropdown já usa `fetchMicroAreas`). Indicadores: `tmravSeconds == null ? '—' : '${s}s'`, com `Semantics` equivalente ("sem alertas vermelhos reconhecidos"). `main.dart`: `dataSourceFor: (s) => BackendAdminDataSource.forSession(s, auth)`; reaproveitar o `Client` já criado em `buildAdminAuth` (mesma CA) — expor `Client` pelo `BackendAdminAuth` se necessário, em vez de criar um segundo.

- [ ] **Step 4: Suíte do app** — `flutter test && flutter analyze` → verde (contagem ≥ a da linha de base); `contrast_tokens_test`, `touch_targets_test`, `text_scale_test` passam.

- [ ] **Step 5: Commit** — `git add apps/admin && git commit -m "feat(admin): painel lê do backend real; TMRAV nulo vira traço (#40)"`

---

### Task 6: E2E no emulador com dados reais

**Files:**
- Modify: `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart`, `bin/seed_e2e_fixtures.dart`, `test/unit/e2e_fixtures_test.dart`
- Modify: `apps/admin/integration_test/admin_login_e2e.dart`, `scripts/qa/admin_login_e2e.sh`

**Interfaces:**
- Produces: o seed de e2e semeia, na microárea das fixtures, 3 alertas determinísticos: vermelho `pending`, vermelho `acknowledged` (`acknowledgedAt − triggeredAt` = 60 s, `triggeredAt` = agora − 1 h) e verde `pending`. Esperado no painel: Vermelho **2**, Verde **1**, Amarelo **0**, Abertos **1**, Reconhecidos **1**, TMRAV **60s**.

- [ ] **Step 1: Teste das fixtures (falha)** — em `e2e_fixtures_test.dart`: `generateE2eFixtures(...)` expõe `f.adminAlerts` com 3 itens, UUIDs v4 distintos dos fixos do seed de dev; e o `toJson` não os perde.

- [ ] **Step 2: Implementar** — fixtures + `INSERT INTO "alerts"` no seed (campos obrigatórios conforme `alert.spy.yaml`: `patientId` do paciente `main`, `acsId` do ACS das fixtures, `microAreaId`, `riskLevel`, `status`, `mqttTopic`, `deviceId`, `retryCount 0`, `version 1`, `locationHash`).

- [ ] **Step 3: Estender o roteiro** — no teste final de `admin_login_e2e.dart`, depois de "Painel de Indicadores": esperar `find.text('60s')` e a contagem `2` ao lado de `Vermelho`; abrir **Alertas** e conferir 3 cartões, nenhum com nome de paciente (`#` + 4 hex); abrir **Auditoria** e conferir uma entrada `read • admin_indicators` do administrador da fixture. No `.sh`, conferir no banco: `select count(*) from audit_logs where "resourceType" like 'admin_%' and result='success'` ≥ 3.

- [ ] **Step 4: Rodar no emulador (o usuário executa; recria containers de dev)**

Preflight: `adb -s emulator-5554 get-state`, porta 8765 livre (`ss -ltn | grep :8765 || echo livre`). Rodar:
```
! DEVICE=emulator-5554 ./scripts/qa/admin_login_e2e.sh 2>&1 | tee .superpowers/admin40_emulador.log
```
Expected: todos os testes passam (os 5 da #48 + os novos de dados) e `OK — login real do backoffice`. Em falha: `superpowers:systematic-debugging` **antes** de editar; guardar sempre o log.

- [ ] **Step 5 (opcional, celular):** mesma execução com `DEVICE=0087014315` e `tee .superpowers/admin40_celular.log`.

- [ ] **Step 6: Commit** — `git add backend apps/admin scripts/qa && git commit -m "test(e2e): painel do admin com dados reais no emulador (#40)"`

---

### Task 7: Documentação, capturas e PR

**Files:**
- Modify: `backend/CLAUDE.md`, `apps/CLAUDE.md`, `PROGRESS.md`, `docs/telas-admin.md`, `docs/screenshots/admin/02..05`, `spec/lgpd_data_audit.md` (coluna `staff_accounts.ubsId`)

- [ ] **Step 1: Capturar as telas com dados reais no emulador**

Com a stack de e2e no ar (`! ./scripts/qa/e2e_stack.sh up && ./scripts/qa/e2e_stack.sh seed`), `flutter run -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/`, relé em `/admin`, ativar a MFA com o código do manifesto e gerar o TOTP com um script Python (RFC 6238, como na #39). Para a barra de status limpa: `adb shell settings put global sysui_demo_allowed 1` **antes** dos `am broadcast … com.android.systemui.demo` (`notifications -e visible false`, `clock -e hhmm 1000`); digitar a senha em blocos de 3 caracteres conferindo o tamanho por `uiautomator dump` antes de enviar. Capturar 02–05 com `adb exec-out screencap -p`, abrir cada PNG com `Read` e rejeitar qualquer dado que não seja sintético. Ao fim: `am broadcast … -e command exit`, `settings put global sysui_demo_allowed 0`, `am force-stop`.

- [ ] **Step 2: Documentar**

`backend/CLAUDE.md`: seção do `AdminEndpoint` (métodos, escopo por papel, `staff_accounts.ubsId`, TMRAV, paginação, auditoria fail-closed, rótulos). `apps/CLAUDE.md`: `BackendAdminDataSource`, `dataSourceFor`, TMRAV nulo. `docs/telas-admin.md`: trocar "dados mockados atrás de `AdminDataSource`" pela descrição real e dizer que as capturas 02–05 são de dados sintéticos de e2e. `PROGRESS.md`: seção da #40 com o que foi provado **nesta** execução (contagens de testes, log do emulador) e o que segue aberto: visão de auditoria por UBS para coordenador, gestão de `ubsId` pela UI (#43), `ADM-001`/coordenador no seed de desenvolvimento, paginação por offset nos alertas.

- [ ] **Step 3: Conferências finais**

Run: `./scripts/qa/check_documentation_links.sh && ./scripts/qa/ci_invariants.sh && (cd backend/sinalacs_server && dart test 2>&1 | tail -1) && (cd apps/admin && flutter test 2>&1 | tail -1 && flutter analyze | tail -1)`
Expected: tudo verde.

- [ ] **Step 4: Commit, push e PR (push e PR só com confirmação do usuário)**

```bash
git add -A docs backend/CLAUDE.md apps/CLAUDE.md PROGRESS.md spec
git commit -m "docs: endpoints do backoffice e capturas com dados reais (#40)"
```
PR contra `develop`, corpo com `Closes #40`, evidências (contagens, log do emulador resumido, sem segredos) e as decisões abertas abaixo.

- [ ] **Step 5: Devolver a stack de dev (o usuário executa)** — `! ./scripts/qa/e2e_stack.sh down && docker compose up -d`.

---

## Decisões que o plano toma pelo usuário (confirmar antes de executar)

1. **Escopo do coordenador por `staff_accounts.ubsId`** (coluna nova, nula para admin); coordenador sem UBS é recusado. Alternativa: coordenador igual a administrador — mais simples, mas contraria a matriz do PRD §4.2.2.
2. **Auditoria só para `admin`.** O PRD dá ao coordenador "Logs de auditoria (UBS)"; filtrar logs por UBS exige juntar `users`→`micro_areas`. Fica para a #43.
3. **Auditoria fail-closed** (`record`, não `recordSafely`): se a linha não grava, o dado não sai.
4. **TMRAV:** janela de 30 dias, só alertas vermelhos com `acknowledgedAt`, `null` quando não há amostra (PRD §1.3 não fixa janela).
5. **Paginação:** `limit` 1–100 (padrão 50); alertas por `offset`, auditoria por `beforeSequence` (log só cresce; `offset` repetiria linhas).
6. **`recordAccess` do app vira no-op:** o servidor audita cada leitura.
7. **Sem coordenador no seed de desenvolvimento** (exigiria nova senha em `.env`/`bootstrap_env.sh`); coordenador só nos testes.

## Self-Review

- **Cobertura da issue:** endpoint(s) somente leitura por papel (Tasks 3–4); TMRAV e contagens reais (Task 3); paginação (Tasks 3–4); minimização de PII (`AdminLabels`, Task 2, e os testes de "sem nome/CPF/hash"); testes por endpoint com recusa para `acs`/`patient` (Task 4); leitura auditada em `audit_logs` (Task 4, conferida no e2e da Task 6); trocar o mock (Task 5); prova no emulador (Task 6).
- **Placeholders:** os casos com `...` na Task 3/4 são enunciados completos do que cada teste deve afirmar, com o primeiro de cada grupo escrito por extenso; o implementador deve escrevê-los inteiros. O nome do construtor `fromJson` dos enums gerados e as chaves do modelo de exceção dependem de arquivos que a Task indica ler antes.
- **Tipos:** `AdminScope`, `AdminReadStore.{indicators,microAreas,alerts,auditLogs,ubsOf}`, `AdminReadService.*` e as classes geradas têm os mesmos nomes nas Tasks 1, 3, 4, 5 e 6; `tmravSeconds` é `int?` no servidor e no app.
- **Riscos:** `serverpod generate` altera muitos arquivos gerados (revisar só o que é da #40). `alerts.microAreaId` é anulável: as consultas de indicadores e alertas usam `LEFT JOIN micro_areas`, para que o administrador conte também o alerta sem microárea; o coordenador, filtrado por `m."ubsId" = @ubs`, não o enxerga. Acrescentar à Task 3 o caso "alerta sem microárea: conta no sistema, não aparece na UBS" (escrito junto dos outros, antes do SQL).
