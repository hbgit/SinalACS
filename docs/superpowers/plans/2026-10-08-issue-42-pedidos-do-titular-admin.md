# Issue #42 — admin atende pedidos do titular (LGPD) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a #42: coordenador/administrador do backoffice listam, analisam, atendem ou recusam (com motivo) os pedidos de exclusão e correção do titular, com prazo de 15 dias destacado, auditoria de cada decisão e aviso ao paciente, provado no emulador.

**Architecture:** Hoje `data_subject_requests` só recebe `open` (escrito por `DataSubjectRightsService`, lado do paciente). Entra um `DataSubjectCaseService` (lado do backoffice) em `application/admin/`, com interface de store à parte do ORM (padrão `AdminReadStore`), exposto por novos métodos em `AdminEndpoint`. A decisão (status + nota + auditoria) e a execução da exclusão (anonimização) acontecem na mesma transação do store. O `apps/admin` ganha o destino "Pedidos do titular" (quinta aba), e o app do paciente passa a mostrar a nota de resposta e o novo status.

**Tech Stack:** Serverpod 3.4.13 (Dart), Postgres, `HealthDataCipher` (AES-256-GCM), Flutter 3.44.8 (`apps/admin`, `apps/patient`), `sinalacs_client` (regenerado), `integration_test` no `emulator-5554`, bash (`scripts/qa`).

**Spec:** Issue #42 (`gh issue view 42`); `spec/lgpd_design.md` §5 (linhas 583–597, prazo de 15 dias) e `spec/lgpd_data_audit.md`; `PROGRESS.md` seções "Direitos do titular no app paciente — LGPD-RF05 e LGPD-RF08 (2026-09-28)" e "Endpoints do backoffice… (issue #40)"; `backend/CLAUDE.md`; `apps/CLAUDE.md`; `spec/ux_accessibility_assessment.md` (cor usada como texto).

## Decisões assumidas (corrija antes de executar, se discordar)

1. **Quem decide:** `coordinator` (só pedidos de pacientes da própria UBS, via `patients → micro_areas.ubsId`) e `admin` (sistema inteiro). `acs` e `patient` são recusados. Mesmo critério fail-closed de `AdminReadService`.
2. **Exclusão = anonimização, não `DELETE`:** ao atender, o store zera a identidade do titular (`users.name` → rótulo `Titular removido`, `users.cpfHash` → hash aleatório não derivável do CPF, `patients.chronicConditionsEncrypted` → `''`), apaga `push_tokens`, `otp_challenges`, `user_credentials` do titular e as `triage_sessions.answers*`. Linhas de `alerts`, `visits`, `audit_logs` e `consent_logs` ficam (são trilha e estatística pseudonimizada; `spec/lgpd_design.md` 5.7). Isso é uma decisão jurídica: marcada como "a confirmar com o encarregado" no PROGRESS.
3. **Correção:** o texto do pedido é decifrado para o analista; "atender" exige uma nota de resposta e **não** reescreve campo automaticamente (o texto é livre; reescrever por regra seria adivinhar). O analista corrige pelos canais existentes e registra a nota.
4. **Transições permitidas:** `open → inReview → completed|rejected` e `open → completed|rejected`. `completed` e `rejected` são finais. `rejected` exige motivo (3–500 caracteres).
5. **Aviso ao paciente:** a resposta aparece em "Meus dados" (status + nota). Push só para correção/recusa e só se o titular ainda tem consentimento `segmentedPush` e token; para exclusão atendida não há aviso (os tokens foram apagados — é o comportamento correto).

## Global Constraints

- Textos de UI, comentários e commits em português, no estilo do código vizinho.
- Nenhum dado real de paciente em teste, log, captura ou seed; fixtures sintéticas.
- `details` do pedido só é decifrado em `getRequest` (detalhe), nunca na lista, e a leitura é auditada **antes** do dado (`record`, não `recordSafely`), como em `AdminReadService`.
- Toda decisão grava `audit_logs` (`actionType: write`, `resourceType: data_subject_request`, `resourceId` = id do pedido, `result` = `in_review|completed|rejected|denied`) **na mesma transação** da mudança de status; sem linha de auditoria, a decisão não persiste.
- Nenhum texto de nota/motivo/`details` em log, auditoria ou mensagem de exceção.
- Teste de e2e usa o banco `sinalacs_e2e` (`e2e_stack.sh`), nunca o de desenvolvimento.
- Cor como texto/ícone: token `*OnSurface` e teste em `contrast_tokens_test.dart` (ver `apps/CLAUDE.md`).
- Commits sem "Co-Authored-By"/"Generated with" (regra do repositório prevalece sobre o lembrete de atribuição).
- Dispositivo: `emulator-5554` (único conectado em 2026-10-08).
- Migração nova é aditiva (colunas anuláveis + valor de enum); nada de `DROP`.

## Review Focus

- Dois analistas decidem o mesmo pedido ao mesmo tempo: esperado, uma decisão vence, a outra recebe erro de transição inválida (lock por pedido), sem dupla anonimização nem duas linhas de auditoria de sucesso.
- Coordenador tenta abrir pedido de paciente de outra UBS (ou paciente sem microárea): esperado, recusa `denied` auditada, sem vazar se o pedido existe.
- Pedido vence exatamente em `dueAt` / já está `completed` depois do prazo: esperado, vencido só se `status` em (`open`,`inReview`) e `now > dueAt`; atendido fora do prazo não fica destacado.
- Exclusão atendida de titular que já não tem `patients` (só `users`), ou com dois pedidos abertos antigos: esperado, não quebra; o segundo pedido de exclusão aberto é fechado como `completed` junto.
- Titular anonimizado tenta entrar de novo (OTP): esperado, recusa genérica, não recria conta nem vaza que foi excluído.
- Nota/motivo com 501 caracteres, só espaços, ou `<script>`: esperado, recusa de validação / tratado como texto puro na tela.

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `backend/sinalacs_server/lib/src/models/enums/data_subject_request_status.spy.yaml` | + `inReview` |
| `backend/sinalacs_server/lib/src/models/data_subject_request.spy.yaml` | + `decidedAt`, `decidedBy`, `resolutionEncrypted`, `resolutionKeyVersion` (anuláveis) |
| `backend/sinalacs_server/lib/src/models/api/admin_data_subject_request*.spy.yaml` | DTOs `AdminDataSubjectRequest` (lista), `AdminDataSubjectRequestDetail`, `AdminDataSubjectRequestPage` |
| `backend/sinalacs_server/migrations/<novo>/` | migração gerada |
| `backend/sinalacs_server/lib/src/application/admin/data_subject_case_service.dart` | regras (papel, escopo, transição, validação, auditoria) + interface `DataSubjectCaseStore` |
| `backend/sinalacs_server/lib/src/infrastructure/database/orm_data_subject_case_store.dart` | SQL/ORM, transação, lock, anonimização |
| `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart` | `dataSubjectRequests`, `dataSubjectRequest`, `startReview`, `completeRequest`, `rejectRequest` |
| `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` | `dataSubjectCaseServiceFor(session)` |
| `backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart` + `patient_data_subject_request_record.spy.yaml` | expõe `resolution` ao titular |
| `apps/admin/lib/core/data/*`, `apps/admin/lib/app/app.dart` (ou novo `lib/app/data_requests_screen.dart`) | fonte de dados + tela |
| `apps/patient/lib/app/app.dart` (~2013–2110) | rótulo `inReview` + nota |
| `scripts/qa/admin_titular_e2e.sh` + `apps/admin/integration_test/admin_titular_e2e.dart` | prova no emulador |

---

### Task 1: Linha de base — o que a #42 ainda exige de fato

**Files:**
- Read: `gh issue view 42`, `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart`, `orm_data_subject_rights_store.dart`, `apps/admin/lib/core/data/admin_data_source.dart`
- Create: `docs/superpowers/plans/2026-10-08-issue-42-baseline.log` (só evidência)

**Interfaces:**
- Produces: confirmação de que nada de #42 existe e de que a base está verde; ponto de partida das Tasks 2–7.

- [ ] **Step 1: Confirmar que não há atendimento hoje**

```bash
cd backend/sinalacs_server
grep -rn "DataSubjectRequestStatus\.\(completed\|rejected\)" lib/src --include=*.dart | grep -v generated   # esperado: só o rótulo/enum, nenhum escritor
grep -n "dataSubject" lib/src/endpoints/admin_endpoint.dart                                              # esperado: vazio
```

- [ ] **Step 2: Linha de base verde**

```bash
cd backend/sinalacs_server && dart analyze && dart test test/unit -r compact
cd ../../apps/admin && flutter analyze && flutter test
cd ../patient && flutter analyze && flutter test
```
Expected: tudo verde. Anotar contagens no `.log`. Falha aqui é defeito pré-existente: corrigir antes de seguir.

- [ ] **Step 3: Emulador pronto**

```bash
~/Android/Sdk/platform-tools/adb devices        # esperado: emulator-5554 device
./scripts/qa/admin_login_e2e.sh                 # esperado: passa (prova que a trilha do admin no emulador funciona)
docker compose up -d                            # restaura a stack de desenvolvimento
```

- [ ] **Step 4: Commit** só se algo for corrigido.

---

### Task 2: Modelo, enum e migração

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/enums/data_subject_request_status.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/data_subject_request.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/admin_data_subject_request.spy.yaml`, `admin_data_subject_request_detail.spy.yaml`, `admin_data_subject_request_page.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/api/patient_data_subject_request_record.spy.yaml`
- Test: `backend/sinalacs_server/test/integration/staff_account_schema_test.dart` (padrão a copiar) → novo `data_subject_request_schema_test.dart`

**Interfaces:**
- Produces: enum `DataSubjectRequestStatus { open, inReview, completed, rejected }`; campos `decidedAt: DateTime?`, `decidedBy: UuidValue?` (relation `users`), `resolutionEncrypted: String?`, `resolutionKeyVersion: int?`; DTOs:
  - `AdminDataSubjectRequest { id: String, type, status, createdAt, dueAt, overdue: bool, patientLabel: String }` (rótulo `#A18F`, sem nome/CPF)
  - `AdminDataSubjectRequestDetail` = campos acima + `details: String?`, `resolution: String?`, `decidedAt: DateTime?`
  - `AdminDataSubjectRequestPage { items: List<AdminDataSubjectRequest>, nextOffset: int? }`
  - `PatientDataSubjectRequestRecord` ganha `resolution: String?`.

- [ ] **Step 1: Teste de esquema que falha**

```dart
// test/integration/data_subject_request_schema_test.dart
test('data_subject_requests tem as colunas de decisão, todas anuláveis', () async {
  final rows = await session.db.unsafeQuery(
    "select column_name, is_nullable from information_schema.columns "
    "where table_name = 'data_subject_requests'",
  );
  final byName = {for (final r in rows) r.toColumnMap()['column_name']: r.toColumnMap()['is_nullable']};
  for (final c in ['decidedAt', 'decidedBy', 'resolutionEncrypted', 'resolutionKeyVersion']) {
    expect(byName[c], 'YES', reason: c);
  }
});
```
(Reaproveitar o `withServerpod`/setup de `staff_account_schema_test.dart`.)

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/integration/data_subject_request_schema_test.dart`
Expected: FAIL (colunas ausentes).

- [ ] **Step 3: Editar os `.spy.yaml`** (enum com `- inReview` entre `open` e `completed`; campos novos; DTOs; `resolution: String?` no registro do paciente), depois:

```bash
cd backend/sinalacs_server && serverpod generate && serverpod create-migration
```
(Conferir flags em `backend/CLAUDE.md`.) Ler o `migration.sql` gerado: só `ADD COLUMN` anulável e, se o enum for `byName` em `text`, nenhuma alteração de tipo. Qualquer `DROP` → parar e rever.

- [ ] **Step 4: Rodar e ver passar** — mesmo comando do Step 2. Depois `dart analyze` e `cd ../sinalacs_client && dart analyze` (cliente regenerado).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server backend/sinalacs_client
git commit -m "feat(lgpd): estado 'em análise' e colunas de decisão em data_subject_requests (#42)"
```

---

### Task 3: Serviço de atendimento (regras puras, com store falso)

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/admin/data_subject_case_service.dart`
- Test: `backend/sinalacs_server/test/unit/data_subject_case_service_test.dart`

**Interfaces:**
- Consumes: `AuthenticatedUser`, `Authorization.staffRoles`, `AuditTrail.record`, `AdminScope` (`admin_read_service.dart`), `HealthDataCipher`.
- Produces:

```dart
abstract interface class DataSubjectCaseStore {
  Future<String?> ubsOf(String staffId);
  Future<AdminDataSubjectRequestPage> list(AdminScope scope,
      {DataSubjectRequestStatus? status, required int limit, required int offset, required DateTime now});
  /// null = não existe OU fora do escopo (indistinguíveis de propósito).
  Future<AdminDataSubjectRequestDetail?> find(AdminScope scope, String id, {required DateTime now});
  /// Transação: trava o pedido (`pg_advisory_xact_lock`), confere [from], grava status/nota/decidedBy,
  /// executa a anonimização se [anonymize], grava a auditoria via [audit]. Devolve false se o estado
  /// atual não está em [from] (corrida perdida).
  Future<bool> decide(AdminScope scope, String id,
      {required Set<DataSubjectRequestStatus> from, required DataSubjectRequestStatus to,
       required String? resolution, required String decidedBy, required bool anonymize,
       required AuditEvent audit, required DateTime now});
}

class DataSubjectCaseService {
  DataSubjectCaseService({required DataSubjectCaseStore store, required AuditTrail audit, DateTime Function()? clock});
  Future<AdminDataSubjectRequestPage> list(AuthenticatedUser u, {DataSubjectRequestStatus? status, int limit = 50, int offset = 0});
  Future<AdminDataSubjectRequestDetail> get(AuthenticatedUser u, String id);
  Future<void> startReview(AuthenticatedUser u, String id);
  Future<void> complete(AuthenticatedUser u, String id, {String? note});   // note obrigatório se correction
  Future<void> reject(AuthenticatedUser u, String id, {required String reason});
}
```
Exceções reaproveitadas: `AlertPermissionException` (papel/escopo), `AdminInvalidRequestException` (validação, transição inválida, não encontrado).

- [ ] **Step 1: Escrever os testes que falham** (store falso em memória, relógio fixo). Casos, um `test()` cada, com código completo:

```dart
test('acs e patient são recusados e a recusa é auditada', () async { ... expect(audit.events.single.result, 'denied'); });
test('coordenador sem UBS é recusado em todos os métodos', ...);
test('coordenador de outra UBS recebe "não encontrado", igual a id inexistente', ...);
test('get audita read ANTES de devolver o dado, e falha de auditoria impede a leitura', ...);
test('overdue só para open/inReview com now > dueAt', ...);       // 3 linhas: aberto vencido, atendido vencido, aberto no limite exato
test('startReview: open→inReview; repetir devolve erro de transição', ...);
test('complete de correção sem nota é recusado; com nota de 501 caracteres também', ...);
test('complete de exclusão chama decide(anonymize: true); de correção, anonymize: false', ...);
test('reject exige motivo de 3 a 500 caracteres após trim', ...);
test('decide devolvendo false vira erro de transição inválida e não audita sucesso', ...);
test('nota nunca aparece na mensagem de exceção nem no AuditEvent', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_case_service_test.dart`
Expected: FAIL (arquivo/classe inexistente).

- [ ] **Step 3: Implementar** `_escopo` (copiar a lógica de `AdminReadService._escopo`, trocando o recurso para `admin_data_subject_requests`), `_validarNota` (trim, 3–500), e as cinco operações. `complete` escolhe `from: {open, inReview}`; `startReview` escolhe `from: {open}`; `reject` escolhe `from: {open, inReview}`. A leitura de detalhe chama `audit.record` (não `recordSafely`) antes do `store.find`.

- [ ] **Step 4: Rodar e ver passar** — mesmo comando. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/admin backend/sinalacs_server/test/unit
git commit -m "feat(lgpd): serviço de atendimento de pedidos do titular (#42)"
```

---

### Task 4: Store ORM, anonimização e corrida (Postgres real)

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_data_subject_case_store.dart`
- Test: `backend/sinalacs_server/test/integration/data_subject_case_store_test.dart`
- Consulte o padrão em `orm_data_subject_rights_store.dart`, `subject_lock.dart`, `orm_admin_read_store.dart`

**Interfaces:**
- Consumes: `DataSubjectCaseStore` (Task 3), `HealthDataCipher`, `subject_lock.dart`.
- Produces: `OrmDataSubjectCaseStore(Session session, HealthDataCipher cipher)`.

- [ ] **Step 1: Testes de integração que falham** (padrão de `data_subject_rights_endpoint_test.dart`, fixtures de `test/support/`):

```dart
test('list ordena por dueAt crescente e traz vencidos primeiro', ...);
test('escopo de UBS: coordenador só vê pacientes da própria UBS', ...);
test('find decifra details só no detalhe; a lista não tem details', ...);
test('decide(exclusão) anonimiza user/patient, apaga push_tokens/otp/credential/triage answers e mantém alerts, visits, audit_logs, consent_logs', ...);
test('decide(exclusão) fecha também um segundo pedido de exclusão aberto do mesmo titular', ...);
test('decide em titular sem linha em patients não quebra', ...);
test('duas decisões simultâneas: uma true, outra false; uma só anonimização', () async {
  final r = await Future.wait([store.decide(...), store.decide(...)]);
  expect(r.where((x) => x).length, 1);
});
test('falha na auditoria desfaz a mudança de status (rollback)', ...);
test('depois da anonimização, requestOtp/verifyOtp do titular recusam com a mensagem genérica de sempre', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/integration/data_subject_case_store_test.dart`
Expected: FAIL (classe inexistente). (Precisa do Postgres de teste: `docker compose up -d postgres`.)

- [ ] **Step 3: Implementar** com `session.db.transaction`: lock por pedido → reler status → conferir `from` → `UPDATE` → se `anonymize`: `users.name`, `users.cpfHash` (`'removed:' + uuid aleatório`; **nunca** derivado do CPF), `patients.chronicConditionsEncrypted=''` + `lastLocationHash=null`, `DELETE` de `push_tokens`/`otp_challenges`/`user_credentials` do titular, `triage_answers`/`triage_sessions.answers*` do titular; fechar outros pedidos de exclusão abertos → gravar auditoria dentro da transação. Resolução cifrada com `cipher` (mesma chave/versão de `details`).

- [ ] **Step 4: Rodar e ver passar** — mesmo comando. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure backend/sinalacs_server/test/integration
git commit -m "feat(lgpd): store do atendimento e anonimização transacional (#42)"
```

---

### Task 5: Endpoint, ligação no runtime e resposta ao paciente

**Files:**
- Modify: `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (junto de `adminReadServiceFor`, ~linha 216)
- Modify: `backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart:258` (`_requestRecord` passa `resolution`), `orm_patient_data_overview_store.dart`, `patient_data_overview_service.dart:39` (`DataSubjectRequestSnapshot.resolution`)
- Modify: `backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart` (novos métodos entram na lista de endpoints autenticados)
- Test: `backend/sinalacs_server/test/integration/admin_endpoint_test.dart` (novo grupo), `test/unit/patient_data_overview_service_test.dart`

**Interfaces:**
- Consumes: `DataSubjectCaseService` (Task 3).
- Produces (assinaturas do cliente):

```dart
Future<AdminDataSubjectRequestPage> dataSubjectRequests(Session s, {required String accessToken, DataSubjectRequestStatus? status, int limit = 50, int offset = 0});
Future<AdminDataSubjectRequestDetail> dataSubjectRequest(Session s, {required String accessToken, required String id});
Future<void> startDataSubjectReview(Session s, {required String accessToken, required String id});
Future<void> completeDataSubjectRequest(Session s, {required String accessToken, required String id, String? note});
Future<void> rejectDataSubjectRequest(Session s, {required String accessToken, required String id, required String reason});
```

- [ ] **Step 1: Testes que falham** — ponta a ponta pelo endpoint: paciente cria pedido (via `PatientsEndpoint`), coordenador da UBS lista (vê rótulo, não nome), abre, inicia análise, conclui; o paciente, em `myData`, vê `completed` + `resolution`. Token de `acs`/`patient` → `AlertPermissionException`. `endpoint_auth_posture_test` exige `authenticate(accessToken)` nos cinco.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/integration/admin_endpoint_test.dart test/unit/endpoint_auth_posture_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar** os cinco métodos (delegando, no estilo dos existentes), `dataSubjectCaseServiceFor(session)` no runtime e `resolution` no registro do paciente (decifrado só para o próprio titular). `serverpod generate` de novo.

- [ ] **Step 4: Rodar e ver passar** — mesmo comando, depois a suíte do backend inteira: `dart test -r compact`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend
git commit -m "feat(lgpd): endpoints do backoffice para pedidos do titular e resposta ao paciente (#42)"
```

---

### Task 6: Aviso por push ao titular (melhor esforço)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/admin/data_subject_case_service.dart` (porta `DataSubjectNotifier`)
- Create: `backend/sinalacs_server/lib/src/infrastructure/push/data_subject_push_notifier.dart` (usa `PushSender`/`GorushClient` e `push_tokens`; consentimento `segmentedPush` mais recente `granted`)
- Test: `backend/sinalacs_server/test/unit/data_subject_case_service_test.dart` (grupo "aviso"), `test/unit/gorush_client_test.dart` (padrão)

**Interfaces:**
- Produces: `abstract interface class DataSubjectNotifier { Future<void> decided(String userId, DataSubjectRequestStatus status); }` — falha do aviso **nunca** desfaz a decisão (log em stderr, sem texto de nota).

- [ ] **Step 1: Testes que falham:** (a) correção atendida chama `decided` uma vez; (b) recusa chama; (c) exclusão atendida **não** chama; (d) `decided` lançando erro não altera o resultado de `complete`; (e) payload só leva título/tela, nunca a nota.

- [ ] **Step 2: Rodar e ver falhar:** `dart test test/unit/data_subject_case_service_test.dart` → FAIL.

- [ ] **Step 3: Implementar** a porta, chamada pós-commit no serviço (`try/catch` com `stderr.writeln`), e o notificador Gorush (sem remetente configurado → no-op).

- [ ] **Step 4: Rodar e ver passar** → PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server
git commit -m "feat(lgpd): aviso push ao titular quando o pedido é decidido (#42)"
```

---

### Task 7: Tela "Pedidos do titular" no admin (widget)

**Files:**
- Modify: `apps/admin/lib/core/data/admin_data_source.dart` (modelos `DataRequestSummary`, `DataRequestDetail`; métodos `fetchDataRequests`, `fetchDataRequest`, `startDataRequestReview`, `completeDataRequest`, `rejectDataRequest`)
- Modify: `apps/admin/lib/core/data/backend_admin_data_source.dart` (mapeia pelo `_guard` já existente, incl. `AdminSessionExpired`), `mock_admin_data_source.dart` (fixtures sintéticas), `apps/admin/test/support/failing_admin_data_source.dart`
- Create: `apps/admin/lib/app/data_requests_screen.dart`
- Modify: `apps/admin/lib/app/app.dart:39-53,133-136` (quinta `AdminDestination.dataRequests`, rótulo "Pedidos do titular", ícone `privacy_tip_outlined`)
- Test: `apps/admin/test/data_requests_screen_test.dart`, `backend_admin_data_source_test.dart`, `contrast_tokens_test.dart`, `touch_targets_test.dart`, `text_scale_test.dart`

**Interfaces:**
- Consumes: métodos do cliente (Task 5).
- Produces: `DataRequestsScreen({required AdminDataSource dataSource})`.

- [ ] **Step 1: Testes de widget que falham** (cada um com `pumpWidget` e fonte falsa):

```dart
testWidgets('fila ordenada por prazo e pedido vencido aparece destacado com texto "Vencido há N dias"', ...);   // critério de aceite 1
testWidgets('o destaque não depende só de cor: ícone + texto (WCAG 1.4.1)', ...);
testWidgets('detalhe mostra o texto da correção; a lista não mostra', ...);
testWidgets('"Atender" de correção sem nota fica desabilitado; com nota chama completeDataRequest', ...);
testWidgets('"Recusar" exige motivo e pede confirmação', ...);
testWidgets('exclusão pede confirmação explícita citando que é irreversível', ...);
testWidgets('AdminSessionExpired leva ao login; AdminDataFailure mostra texto e "Tentar novamente"', ...);
testWidgets('estado vazio: "Nenhum pedido pendente."', ...);
testWidgets('nota com <script> é exibida como texto', ...);
```
Mais: a cor de "vencido" usada como texto entra em `contrast_tokens_test.dart` (≥ 4.5:1 sobre `surfaceRaised`); alvos ≥ 48 dp em `touch_targets_test.dart`; escala de texto 2.0 sem overflow em `text_scale_test.dart`.

- [ ] **Step 2: Rodar e ver falhar:** `cd apps/admin && flutter test test/data_requests_screen_test.dart` → FAIL.

- [ ] **Step 3: Implementar** modelos, mapeamento e tela (lista → detalhe em painel/rota; reaproveitar `_AsyncError`, `_SessaoVencida`, tokens do `admin_theme.dart`; `Semantics` com `MergeSemantics` nos botões, como o resto do app).

- [ ] **Step 4: Rodar e ver passar:** `flutter analyze && flutter test` → verde.

- [ ] **Step 5: Commit**

```bash
git add apps/admin
git commit -m "feat(admin): tela de pedidos do titular com prazo e decisão (#42)"
```

---

### Task 8: App do paciente mostra "em análise" e a resposta

**Files:**
- Modify: `apps/patient/lib/app/app.dart:2013-2110` (`_requestStatusLabel` ganha `inReview => 'Em análise'`; `open => 'Recebido'`; exibe `resolution` quando houver; o teste de "pedido aberto" em 2105 passa a tratar `inReview` como aberto)
- Test: `apps/patient/test/patient_app_mvp_test.dart` (grupo de direitos do titular) e o teste de contagem de rótulos, se existir

**Interfaces:**
- Consumes: `PatientDataSubjectRequestRecord.resolution` (Task 2/5).

- [ ] **Step 1: Testes que falham:** (a) status `inReview` mostra "Em análise"; (b) `completed` com nota mostra a nota; (c) `rejected` mostra o motivo; (d) com pedido de exclusão `inReview`, o botão "Solicitar exclusão" continua indisponível (não duplica); (e) `switch` exaustivo compila.

- [ ] **Step 2: Rodar e ver falhar:** `cd apps/patient && flutter test test/patient_app_mvp_test.dart --plain-name "titular"` → FAIL.

- [ ] **Step 3: Implementar.**

- [ ] **Step 4: Rodar e ver passar:** `flutter analyze && flutter test` → verde.

- [ ] **Step 5: Commit**

```bash
git add apps/patient
git commit -m "feat(patient): mostra análise e resposta do pedido do titular (#42)"
```

---

### Task 9: Prova no emulador (ponta a ponta)

**Files:**
- Create: `scripts/qa/admin_titular_e2e.sh` (modelo: `scripts/qa/admin_login_e2e.sh`, `lib_rele.sh`, `e2e_stack.sh`; teste do script em `admin_titular_e2e_test.sh`, modelo `admin_login_e2e_test.sh`)
- Create: `apps/admin/integration_test/admin_titular_e2e.dart`
- Modify: `scripts/qa/e2e.sh` (invocar o novo script em `--full`), `scripts/qa/e2e_stack.sh` / fixtures de e2e (um paciente sintético com pedido de correção e outro de exclusão, um deles com `dueAt` no passado)
- Modify: `.github/workflows/ci.yml` **somente se** o job `android-e2e` já roda `e2e.sh --full`; não renomear jobs (`scripts/qa/ci_invariants.sh` falha)

**Interfaces:**
- Consumes: tudo acima.

- [ ] **Step 1: Escrever o teste de integração que falha** — no emulador: login do admin (MFA, como em `admin_login_e2e.dart`) → aba "Pedidos do titular" → o pedido vencido aparece primeiro e destacado → abre o de correção, vê o texto sintético → inicia análise → atende com nota; abre o de exclusão → recusa sem motivo (bloqueado) → atende. Asserções de banco feitas pelo script (Step 3).

- [ ] **Step 2: Rodar e ver falhar**

```bash
~/Android/Sdk/platform-tools/adb devices         # emulator-5554 device
./scripts/qa/admin_titular_e2e.sh                # esperado: FAIL antes de o script existir completo
```

- [ ] **Step 3: Implementar o script** (stack `sinalacs_e2e`, fixtures sintéticas, relé, `flutter test integration_test/admin_titular_e2e.dart -d emulator-5554`) e, ao final, **conferir no banco de teste**: (i) os dois pedidos `completed`, `decidedBy` do admin, `resolutionEncrypted` ≠ texto claro; (ii) `users.name` do titular excluído anonimizado e `cpfHash` com prefixo `removed:`; (iii) zero `push_tokens`/`otp_challenges` dele; (iv) `alerts`/`consent_logs` dele preservados; (v) **uma linha `audit_logs` por decisão** (`write`/`data_subject_request`, `resourceId` = id) e a cadeia de auditoria íntegra (`audit_chain_verifier`); (vi) `grep` do texto sintético da nota nos logs do contêiner do backend → vazio. Limpeza: apagar banco e manifesto; lembrar `docker compose up -d`.

- [ ] **Step 4: Rodar e ver passar**

```bash
./scripts/qa/admin_titular_e2e.sh && ./scripts/qa/admin_titular_e2e_test.sh
./scripts/qa/admin_login_e2e.sh        # regressão do login/painel
./scripts/qa/patient_full_e2e.sh       # regressão do paciente (inclui Meus dados)
```
Expected: todos verdes. Capturar logs em `docs/superpowers/plans/2026-10-08-issue-42-e2e.log`.

- [ ] **Step 5: Commit**

```bash
git add scripts apps/admin docs/superpowers/plans
git commit -m "test(admin): prova no emulador do atendimento a pedidos do titular (#42)"
```

---

### Task 10: Documentação e fechamento da issue

**Files:**
- Modify: `PROGRESS.md` (nova seção "Atendimento dos pedidos do titular (#42, 2026-10-08)"; **editar** o item "Ninguém atende os pedidos" da seção de 2026-09-28 para "resolvido, ver…"; contagens de teste reais)
- Modify: `CLAUDE.md` (parágrafo "Still missing": tirar "write endpoints … for the admin" apenas na parte de pedidos do titular; lista de endpoints do `admin`)
- Modify: `backend/CLAUDE.md` (endpoint, store, anonimização), `apps/CLAUDE.md` (aba nova), `spec/lgpd_data_audit.md` (colunas novas de `data_subject_requests`: `decidedAt`, `decidedBy`, `resolutionEncrypted`, `resolutionKeyVersion`; ajustar a contagem de tabelas só se mudar), `spec/lgpd_design.md` (execução da exclusão: o que é anonimizado e o que fica)
- Modify: comentário em `data_subject_request_status.spy.yaml` ("só `open` tem escritor" deixa de ser verdade)

- [ ] **Step 1:** Rodar tudo e anotar números reais (nada de copiar contagem antiga):

```bash
cd backend/sinalacs_server && dart analyze && dart test -r compact
cd ../../apps/admin && flutter analyze && flutter test
cd ../patient && flutter analyze && flutter test
cd ../acs && flutter analyze && flutter test        # regressão: protocolo regenerado
cd ../.. && ./scripts/qa/check_documentation_links.sh && ./scripts/qa/ci_invariants.sh
```
Expected: verde.

- [ ] **Step 2:** Escrever a seção do PROGRESS com: o que existe; as 5 decisões assumidas (marcar a anonimização como "a validar com o encarregado"); o que ficou de fora (correção não reescreve campo; sem notificação por e-mail; sem prazo de expurgo de `consent_logs`; iOS/aparelho físico; `acs` não consome o cliente novo).

- [ ] **Step 3:** Marcar os 3 critérios de aceite da issue com a evidência (teste/arquivo) no comentário de fechamento (`gh issue comment 42`, **só com autorização do usuário**).

- [ ] **Step 4: Commit**

```bash
git add PROGRESS.md CLAUDE.md backend/CLAUDE.md apps/CLAUDE.md spec
git commit -m "docs: atendimento dos pedidos do titular (#42)"
```

---

## Auto-revisão

- **Cobertura dos critérios da issue:** vencido destacado → Task 7 (widget) + Task 9 (emulador); decisão gera auditoria → Tasks 3/4 (rollback sem auditoria) + Task 9 (v); testes backend e widget → Tasks 3–5, 7–8. "Listar pedidos / transições / execução / auditoria" → Tasks 2–5. "Texto cifrado só decifrado sob papel autorizado" → Global Constraints + Task 3/4. "Notificar o paciente" → Tasks 5 (Meus dados), 6 (push), 8.
- **Placeholders:** os testes das Tasks 3, 4, 7 e 8 estão listados por caso com `...` no corpo; ao executar, cada um deve ser escrito por completo antes do Step 2 (o nome e a asserção de cada caso já estão fixados acima).
- **Consistência de tipos:** `DataSubjectCaseStore.decide`, `AdminDataSubjectRequest*` e os cinco métodos do endpoint têm os mesmos nomes nas Tasks 2–5, 7 e 9.
- **Riscos abertos:** (1) a decisão jurídica de anonimizar em vez de apagar; (2) `serverpod create-migration` pode exigir flags diferentes das citadas (conferir `backend/CLAUDE.md`); (3) adicionar a quinta aba mexe em `responsive_layout_test` e `admin_home_shell_test`, que podem exigir ajuste de contagem de destinos.
