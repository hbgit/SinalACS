# ISSUE #46 — Avisos agendados (RF14) e publicação de termos com aviso de 15 dias — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans para implementar este plano tarefa a tarefa. Os passos usam `- [ ]` para acompanhamento.

**Goal:** Permitir, a partir de um app móvel do papel autorizado, criar/agendar avisos por microárea (com histórico) e publicar uma nova versão dos termos com vigência ≥ 15 dias, bloqueada até a revisão jurídica ser registrada — tudo autorizado no backend e auditado.

**Architecture:** O backend ganha duas tabelas (`scheduled_notices`, `terms_versions`), dois serviços de aplicação (`NoticeSchedulingService`, `TermsPublicationService`) no padrão serviço/store já usado em `application/` e métodos novos nos endpoints. O envio agendado reaproveita `NoticeService`/`GorushClient`; o cartão do paciente passa a ler a agenda do banco em vez da constante `upcomingTermsChange`. A UI fica no `apps/admin` (somente Android).

**Tech Stack:** Dart/Serverpod (`backend/sinalacs_server`), Postgres, Gorush/FCM, Flutter (apps móveis), `dart test`, `flutter test`, `scripts/qa/push_e2e.sh`.

**Spec:** `spec/PRD_system.md` (RF14), `spec/lgpd_design.md` (LGPD-RF18, aviso de 15 dias), `spec/stack.md`, issue #46 do GitHub.

---

## Decisões confirmadas (2026-10-14)

1. **App hospedeiro:** `apps/admin`, somente alvo Android; nada em `apps/admin/web/`.
2. **Envio de aviso:** `coordinator` para microáreas da própria UBS, `admin` para qualquer uma; o ACS mantém o envio imediato atual (`NoticesEndpoint.sendSegmented`, inalterado).
3. **Revisão jurídica:** somente `admin` marca "revisado", com registro de quem e quando (`legallyReviewedBy`/`legallyReviewedAt`).
4. **Publicar termos:** registra só o anúncio (versão, resumo, vigência) e liga o cartão do paciente. O texto integral continua em `apps/patient/lib/core/legal/legal_documents.dart` e exige release do app.

Decisão derivada (revisável): um único destino novo "Avisos" na navegação, com a sub-aba "Termos" visível só ao admin (ver Fase 3).

---

## Global Constraints

- Somente apps móveis (Flutter/Android; iOS só se o projeto já suportar — hoje **não**: ver CLAUDE.md, "iOS" está em "Still missing"). Nenhum arquivo em `apps/admin/web/`, nenhuma rota web nova.
- Backend só onde os apps precisam.
- Texto de UI, comentários e docs em português.
- Aviso de termos: `effectiveFrom - publishedAt >= 15 dias` (`termsChangeNoticePeriod`, `terms_change_schedule.dart:5`).
- Publicação bloqueada até `legallyReviewedAt != null`. **Nenhum texto jurídico real** em código, seed ou teste; use `"[TEXTO PLACEHOLDER]"`.
- O texto do aviso nunca entra na trilha de auditoria (regra existente em `notices_endpoint.dart`/`notice_service.dart`); a trilha leva ator, microárea, id do aviso, versão dos termos e resultado.
- Nunca dado real de paciente em testes/logs.
- Nenhuma atribuição de IA em commits (instrução do CLAUDE.md do projeto prevalece sobre qualquer rodapé padrão).
- Mensagens de commit em português, no estilo `feat(avisos): ... (#46)`.

## Review Focus

1. Agendamento no passado ou a < 1 min: deve recusar (não enviar na hora por engano).
2. Aviso agendado cuja microárea deixa de existir / ACS desativado antes do disparo: marcar `failed` com motivo, nunca perder em silêncio.
3. Disparo duplicado (dois processos, ou reinício do servidor no meio): o aviso sai uma única vez (reserva atômica `pending → sending`).
4. `outcomeUnknown` do Gorush no disparo agendado: não reenviar automaticamente (mesma regra de `notice_service.dart`), marcar `unknown`.
5. `effectiveFrom` exatamente 15 dias após `publishedAt`: aceita; 15 dias menos 1 s: recusa.
6. Termos publicados sem revisão jurídica, ou com revisão posterior à tentativa: recusa e audita `denied_not_reviewed`.
7. Usuário sem papel (paciente, ACS tentando agendar para outra microárea): erro tipado **e** linha de auditoria `denied_role`/`denied_territory`.
8. Duas versões de termos futuras ao mesmo tempo: só uma agenda ativa (a nova substitui a anterior apenas se ainda não vigente).

---

## File Structure

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `backend/sinalacs_server/lib/src/models/scheduled_notice.spy.yaml` | criar | tabela `scheduled_notices` |
| `backend/sinalacs_server/lib/src/models/terms_version.spy.yaml` | criar | tabela `terms_versions` |
| `backend/sinalacs_server/lib/src/models/enums/scheduled_notice_status.spy.yaml` | criar | `pending/sending/sent/unknown/failed/cancelled` |
| `backend/sinalacs_server/lib/src/models/api/notice_history_entry.spy.yaml`, `notice_history_page.spy.yaml`, `terms_version_entry.spy.yaml` | criar | DTOs do histórico e da lista de termos |
| `backend/sinalacs_server/lib/src/application/notices/notice_scheduling_service.dart` | criar | criar/cancelar/listar/disparar agendados + autorização + auditoria |
| `backend/sinalacs_server/lib/src/application/patients/terms_publication_service.dart` | criar | publicar, revisar, listar versões |
| `backend/sinalacs_server/lib/src/infrastructure/database/orm_scheduled_notice_store.dart`, `orm_terms_version_store.dart` | criar | stores ORM |
| `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart` | modificar (`termsChangeNotice`, linhas ~100-180) | ler a agenda do store |
| `backend/sinalacs_server/lib/src/endpoints/notices_endpoint.dart`, `admin_endpoint.dart` | modificar | métodos novos (token → serviço) |
| `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` | modificar | fábricas dos serviços + laço do disparador |
| `backend/sinalacs_server/test/unit/notice_scheduling_service_test.dart`, `terms_publication_service_test.dart` | criar | TDD |
| `backend/sinalacs_server/test/integration/notice_scheduling_endpoint_test.dart` | criar | autorização e auditoria ponta a ponta |
| `scripts/qa/push_e2e.sh` | modificar | caso do aviso agendado |
| `apps/admin/lib` e `apps/admin/test` | criar/modificar | **Fase 3** (ver tabela da fase) |

---

## Fase 0 — Verificação do estado atual (somente leitura; resultados já levantados em 2026-10-14)

### Task 0.1: Registrar os achados da investigação

**Files:** Create: `docs/superpowers/plans/2026-10-14-issue-46-fase0-achados.md`

- [ ] **Step 1: Escrever o arquivo com os achados abaixo (cada item confirmado no código)**

| Pergunta da issue | Achado (arquivo:linha) | Lacuna |
|---|---|---|
| Gorush/FCM e segmentação | `infrastructure/push/gorush_client.dart` (`PushSender`); `application/notices/notice_service.dart` `sendSegmented`: microárea **vem do token** (`user.microAreaId!`), destinatários por `NoticeRecipientStore.consentedTargets` (último consentimento `segmentedPush == granted`), público `everyone`/`chronic`, título ≤ 60, mensagem ≤ 240; fábrica `AlertRuntime.noticeServiceFor` (`runtime/alert_runtime.dart:443`) | só **envio imediato**; só papel `acs`; não há tabela de avisos nem histórico; microárea alvo não é parâmetro |
| Cartão de termos e agenda | Cartão: `apps/patient/lib/core/legal/terms_change_notice_card.dart`, montado em `apps/patient/lib/app/app.dart:1064-1172`, lê `backend.termsChangeNotice()` → `PatientsEndpoint.termsChangeNotice` (`patients_endpoint.dart:199`) → `DataSubjectRightsService.termsChangeNotice` (`data_subject_rights_service.dart:172`) → `_termsChangeReader()` que cai em **`upcomingTermsChange = null`** (`application/patients/terms_change_schedule.dart:50`) | agenda é constante do repositório, síncrona, sem I/O; regra dos 15 dias já existe no construtor de `TermsChangeSchedule`, mas só vale para quem edita o código |
| Papéis e permissões | `UserRole {patient, acs, coordinator, admin}` (`models/enums/user_role.spy.yaml`); guarda única `Authorization.require(user, roles:, onDenied:, requireMicroArea:)` (`application/auth/authorization.dart`); `Authorization.staffRoles`; escopo de staff em `application/admin/admin_scope.dart` (admin = sistema, coordenador = UBS) | `Authorization.require` **lança sem auditar**: a negação não deixa linha na trilha |
| Auditoria reutilizável | `AuditTrail.recordSafely(AuditEvent{userId, actionType, resourceType, resourceId, result})` (`application/audit/audit_trail.dart`), tabela `audit_logs` com cadeia de hash; já existe `community_notice` com `granted/no_recipients/not_delivered/unknown` | não há `denied_*` para avisos, nem evento de termos |
| `push_e2e.sh` | cobre: token FCM real do paciente no emulador `emulator-5554`, `tool/send_notice.dart` como ACS, chegada na bandeja, auditoria `granted`, e com `--negativos` token falso/ios, Gorush parado, revogação | exige chave `infra/docker/gorush/credentials/fcm-service-account.json` (modo 600), `apps/patient/android/app/google-services.json`, emulador com Play Services, Docker, `--e2e-db` para banco efêmero; **sai com 3 sem a chave**; não cobre agendamento nem termos |
| App com UI de avisos | `apps/acs/lib/core/network/backend_client.dart:177,285,814` só tem `sendNotice`; nenhuma tela. `apps/admin/lib/app` não tem nada de avisos/termos | **não existe UI de operação em nenhum app** |

- [ ] **Step 2: Confirmar o padrão de laço em segundo plano** — Run: `grep -rn "Timer.periodic\|OutboxDispatcher" backend/sinalacs_server/lib/src/runtime backend/sinalacs_server/lib/src/ops | head`. Anotar no arquivo qual classe dispara alertas periodicamente (`alert_outbox_dispatcher`) — o disparador de avisos segue o mesmo padrão.
- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-10-14-issue-46-fase0-achados.md
git commit -m "docs(avisos): achados da fase 0 da issue 46 (#46)"
```

---

## Fase 1 — Backend: avisos agendados com histórico

> Antes de cada teste de integração: `./scripts/dev/bootstrap_env.sh` e `docker compose up -d postgres-test` (ver `backend/CLAUDE.md`). Testes de unidade não precisam de banco.

### Task 1.1: Enum de status e modelo `ScheduledNotice` + migração

**Files:** Create `models/enums/scheduled_notice_status.spy.yaml`, `models/scheduled_notice.spy.yaml`; gerar código e migração.

- [ ] **Step 1: Criar os YAML**

```yaml
# enums/scheduled_notice_status.spy.yaml
### Ciclo de um aviso agendado. `sending` é a reserva atômica anti-duplicidade.
enum: ScheduledNoticeStatus
serialized: byName
values:
  - pending
  - sending
  - sent
  - unknown
  - failed
  - cancelled
```

```yaml
# scheduled_notice.spy.yaml
### Aviso comunitário agendado por staff (RF14, #46). O texto fica aqui porque o
### staff o digitou para ser enviado; ele nunca vai para audit_logs.
class: ScheduledNotice
table: scheduled_notices
fields:
  id: UuidValue?, defaultPersist=random
  createdBy: UuidValue, relation(parent=users)
  microAreaId: UuidValue, relation(parent=micro_areas)
  audience: String
  title: String
  message: String
  scheduledFor: DateTime
  status: ScheduledNoticeStatus
  recipients: int?
  accepted: int?
  failureReason: String?
  createdAt: DateTime
  sentAt: DateTime?
indexes:
  scheduled_notices_due_idx:
    fields: status, scheduledFor
  scheduled_notices_area_idx:
    fields: microAreaId, createdAt
```

- [ ] **Step 2: Gerar código e migração** — Run (comandos exatos em `backend/CLAUDE.md`, seção Serverpod): `cd backend/sinalacs_server && serverpod generate && serverpod create-migration`. Expected: nova pasta em `migrations/` com `CREATE TABLE "scheduled_notices"`.
- [ ] **Step 3: Conferir** — Run: `grep -c scheduled_notices migrations/*/migration.sql | tail -1` → `≥1`.
- [ ] **Step 4: Commit** — `git add backend && git commit -m "feat(avisos): tabela scheduled_notices (#46)"`

### Task 1.2: Autorização + auditoria de negação (teste primeiro)

**Files:** Create `test/unit/notice_scheduling_service_test.dart`, `lib/src/application/notices/notice_scheduling_service.dart`.

**Interfaces:**
- Produces (os `AdminInvalidRequestException` dos testes abaixo substituem `DataRightsException`): `NoticeSchedulingService.schedule(AuthenticatedUser, {required String microAreaId, required String audience, required String title, required String message, required DateTime scheduledFor}) → Future<String>` (id); `cancel(user, id)`, `history(user, {microAreaId, limit, offset})`, `dispatchDue()`. Interface `ScheduledNoticeStore` (abaixo).

- [ ] **Step 1: Escrever os testes que falham** (fakes `FakeScheduledNoticeStore`, `RecordingAuditTrail` no mesmo arquivo; reutilize o fake de auditoria de `notice_service_test.dart` se já exportado)

```dart
test('paciente e ACS não agendam: erro e linha denied_role', () async {
  for (final role in [UserRole.patient, UserRole.acs]) {
    final user = fakeUser(role: role, microAreaId: 'ma-1');
    await expectLater(
      service.schedule(user, microAreaId: 'ma-1', audience: 'everyone',
          title: 'T', message: 'M', scheduledFor: now.add(const Duration(hours: 2))),
      throwsA(isA<StateError>()),
    );
    expect(audit.events.last.result, 'denied_role');
    expect(audit.events.last.resourceType, 'community_notice');
  }
});

test('coordenador não agenda para microárea de outra UBS: denied_territory', () async {
  store.ubsOfMicroArea['ma-x'] = 'ubs-2';
  final coord = fakeUser(role: UserRole.coordinator, ubsId: 'ubs-1');
  await expectLater(
    service.schedule(coord, microAreaId: 'ma-x', audience: 'everyone',
        title: 'T', message: 'M', scheduledFor: now.add(const Duration(hours: 2))),
    throwsA(isA<StateError>()),
  );
  expect(audit.events.last.result, 'denied_territory');
});

test('agendar no passado ou a menos de 1 minuto recusa', () async { /* admin; scheduledFor = now → AdminInvalidRequestException */ });
test('admin agenda: grava pending e audita scheduled com resourceId = id do aviso, sem o texto', () async {
  final id = await service.schedule(admin, microAreaId: 'ma-1', audience: 'chronic',
      title: 'T', message: 'M', scheduledFor: now.add(const Duration(hours: 2)));
  expect(store.rows[id]!.status, ScheduledNoticeStatus.pending);
  expect(audit.events.last.result, 'scheduled');
  expect(audit.events.last.resourceId, id);
  expect(audit.events.map((e) => e.toString()).join(), isNot(contains('M')));
});
```

(Substituir as elipses acima por corpos completos ao implementar; o padrão é idêntico ao primeiro teste.)

- [ ] **Step 2: Rodar** — `cd backend/sinalacs_server && dart test test/unit/notice_scheduling_service_test.dart` → FAIL (`NoticeSchedulingService` não existe).
- [ ] **Step 3: Implementar o mínimo**

```dart
abstract interface class ScheduledNoticeStore {
  Future<String?> ubsOfMicroArea(String microAreaId);
  Future<String> insert({required String createdBy, required String microAreaId,
      required String audience, required String title, required String message,
      required DateTime scheduledFor, required DateTime createdAt});
  Future<bool> cancelIfPending(String id);
  /// pending → sending atômico: devolve só as linhas que ESTA chamada reservou.
  Future<List<ScheduledNoticeSnapshot>> claimDue(DateTime now, {int limit = 20});
  Future<void> finish(String id, {required ScheduledNoticeStatus status,
      int? recipients, int? accepted, String? failureReason, required DateTime at});
  Future<List<ScheduledNoticeSnapshot>> history({String? microAreaId, String? ubsId,
      required int limit, required int offset});
}

class NoticeSchedulingService {
  NoticeSchedulingService({required ScheduledNoticeStore store, required AuditTrail audit,
      required NoticeSender sendNow, DateTime Function()? clock});
  // schedule(): Authorization.require(staffRoles, requireMicroArea:false, onDenied: audita denied_role + StateError);
  // coordenador: compara store.ubsOfMicroArea com user.ubsId → denied_territory;
  // valida título/mensagem/público com as constantes de notice_service.dart;
  // scheduledFor >= clock()+1min senão AdminInvalidRequestException;
  // insere, audita 'scheduled' (resourceId = id) e devolve o id.
}
```

`NoticeSender` é um typedef para a função que `NoticeService` expõe (`Task 1.4` extrai `sendToMicroArea`). Como a negação precisa gravar auditoria **antes** de lançar, a guarda é um `try/catch` em volta de `Authorization.require` com `onDenied` que dispara `_audit.recordSafely(...)` de forma síncrona-aguardada (`await` no método `_deny`).

- [ ] **Step 4: Rodar** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(avisos): agendamento autorizado e auditado (#46)"`

### Task 1.3: Cancelar e listar histórico (escopado)

**Files:** modificar `notice_scheduling_service.dart` e seu teste.

- [ ] **Step 1: Testes** — (a) `cancel` só cancela `pending` (status `sent` → `AdminInvalidRequestException`), audita `cancelled`; (b) `history` do coordenador só devolve linhas da própria UBS, do admin todas, ACS/paciente → `denied_role` auditado; (c) o item do histórico **não** devolve `message` (só `title`, microárea, público, status, contagens, `scheduledFor`, `sentAt`, quem criou como matrícula).
- [ ] **Step 2: Rodar** → FAIL. **Step 3: Implementar** `cancel` (`store.cancelIfPending`) e `history` (filtro por `ubsId` quando `coordinator`). **Step 4: Rodar** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(avisos): cancelar e histórico escopado (#46)"`

### Task 1.4: Disparo dos avisos vencidos (anti-duplicidade e `unknown`)

**Files:** modificar `notice_service.dart` (extrair `sendToMicroArea(microAreaId, {title, message, audience, actorId})` mantendo `sendSegmented` como chamador), `notice_scheduling_service.dart`, testes de ambos.

- [ ] **Step 1: Testes** — (a) `dispatchDue` com 2 vencidos envia 2 e grava `sent` com contagens; (b) chamar `dispatchDue` duas vezes seguidas **não** reenvia (o fake de `claimDue` só devolve `pending`); (c) `NoticeDeliveryException` simples → `failed` com `failureReason`, sem repetir; (d) falha com `outcomeUnknown` → `unknown`, sem repetir; (e) auditoria por disparo: `resourceType 'community_notice'`, `resourceId = id`, `result` = `granted/no_recipients/not_delivered/unknown/failed`, `userId = createdBy`. Rodar os testes existentes de `notice_service_test.dart` e confirmar que continuam verdes.
- [ ] **Step 2: FAIL. Step 3: Implementar. Step 4: `dart test test/unit/notice_service_test.dart test/unit/notice_scheduling_service_test.dart` → PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(avisos): disparo dos agendados sem duplicidade (#46)"`

### Task 1.5: Store ORM + laço periódico

**Files:** criar `infrastructure/database/orm_scheduled_notice_store.dart`; modificar `runtime/alert_runtime.dart` (fábrica `noticeSchedulingServiceFor(session)` e laço, seguindo o dispatcher de alertas achado na Task 0.1); teste de integração `test/integration/notice_scheduling_endpoint_test.dart`.

- [ ] **Step 1: Teste de integração** (padrão de `notices_endpoint_test.dart` com `serverpod_test_tools.dart`): agenda como admin → linha `pending`; avança o relógio injetado → `dispatchDue` com `NoticeSender` falso → linha `sent`; `claimDue` concorrente (duas chamadas com `Future.wait`) reserva cada linha uma só vez.
- [ ] **Step 2: Rodar** `dart test test/integration/notice_scheduling_endpoint_test.dart` → FAIL. **Step 3: Implementar** `claimDue` com `UPDATE scheduled_notices SET status='sending' WHERE id IN (SELECT id ... WHERE status='pending' AND "scheduledFor" <= $1 ORDER BY "scheduledFor" LIMIT $2 FOR UPDATE SKIP LOCKED) RETURNING ...`. No arranque, linhas presas em `sending` há > 10 min viram `unknown` (nunca reenvio automático). **Step 4: PASS.**
- [ ] **Step 5: Commit** — `git commit -am "feat(avisos): store ORM e laço de disparo (#46)"`

### Task 1.6: Endpoints (`staff`) e cliente gerado

**Files:** modificar `endpoints/admin_endpoint.dart` (não `notices_endpoint.dart`: o app admin só fala com `EndpointAdmin`, e `_guardEscrita` já traduz `AdminInvalidRequestException`); criar DTOs `notice_history_entry.spy.yaml`, `notice_history_page.spy.yaml`; `serverpod generate`.

- [ ] **Step 1: Teste** em `notice_scheduling_endpoint_test.dart`: sem token → `AuthenticationFailed…`; paciente → `AlertPermissionException` **e** linha `denied_role` em `audit_logs`.
- [ ] **Step 2: FAIL. Step 3: Implementar** `scheduleNotice`, `cancelScheduledNotice`, `noticeHistory`, cada um `authenticate(accessToken)` → serviço (mapeando `StateError` → `AlertPermissionException`, como os demais métodos de `AdminEndpoint`). Atualizar `endpoint_auth_posture_test.dart` se ele enumera endpoints. **Step 4:** `dart test test/integration/notice_scheduling_endpoint_test.dart test/unit/endpoint_auth_posture_test.dart` → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(avisos): endpoints de agendamento e histórico (#46)"`

---

## Fase 2 — Backend: publicação de termos com revisão jurídica e 15 dias

### Task 2.1: Modelo `TermsVersion` + migração

**Files:** criar `models/terms_version.spy.yaml`.

```yaml
### Versão dos termos anunciada ao paciente (LGPD-RF18, #46). O TEXTO jurídico
### não fica aqui: vive no app do paciente. Aqui só o anúncio e a revisão.
class: TermsVersion
table: terms_versions
fields:
  id: UuidValue?, defaultPersist=random
  version: String
  summary: String
  effectiveFrom: DateTime
  createdBy: UuidValue, relation(parent=users)
  createdAt: DateTime
  legallyReviewedAt: DateTime?
  legallyReviewedBy: UuidValue?, relation(parent=users, name=terms_reviewer)
  publishedAt: DateTime?
  publishedBy: UuidValue?, relation(parent=users, name=terms_publisher)
indexes:
  terms_versions_version_key:
    fields: version
    unique: true
```

- [ ] Gerar (`serverpod generate && serverpod create-migration`), conferir `terms_versions` na migração, commit `feat(termos): tabela terms_versions (#46)`.

### Task 2.2: Regras de publicação (TDD)

**Files:** criar `test/unit/terms_publication_service_test.dart`, `application/patients/terms_publication_service.dart`.

**Interfaces:** Produces `TermsPublicationService.draft(user,{version,summary,effectiveFrom})`, `markReviewed(user, id)`, `publish(user, id)`, `list(user)`; `TermsVersionStore` com `insertDraft/markReviewed/markPublished/list/current()`.

- [ ] **Step 1: Testes que falham**

```dart
test('publicar sem revisão jurídica: recusa e audita denied_not_reviewed', () async {
  final id = await service.draft(admin, version: '2099.1', summary: '[TEXTO PLACEHOLDER]',
      effectiveFrom: now.add(const Duration(days: 20)));
  await expectLater(service.publish(admin, id), throwsA(isA<AdminInvalidRequestException>()));
  expect(audit.events.last.result, 'denied_not_reviewed');
  expect(audit.events.last.resourceType, 'terms_version');
});
test('vigência a menos de 15 dias da publicação: recusa', () async {
  // draft ok; markReviewed; publish com clock = effectiveFrom - 15d + 1s → recusa
});
test('vigência exatamente 15 dias após a publicação: aceita e audita published', () async {
  // clock = effectiveFrom - 15d → publish ok, publishedAt == clock
});
test('somente admin revisa e publica; coordenador/ACS/paciente: denied_role', () async {});
test('versão igual à vigente (consentPolicyVersion) é recusada no rascunho', () async {});
test('nova publicação enquanto outra ainda não vigente substitui a anterior (uma só agenda)', () async {});
```

- [ ] **Step 2:** `dart test test/unit/terms_publication_service_test.dart` → FAIL.
- [ ] **Step 3: Implementar** reutilizando `TermsChangeSchedule` como validador (instanciá-lo em `publish` e converter `ArgumentError` em `AdminInvalidRequestException`); auditoria `terms_version` com `result` ∈ `drafted/reviewed/published/denied_role/denied_not_reviewed/denied_notice_period`, `resourceId` = id da versão; o `summary` não entra na trilha.
- [ ] **Step 4:** PASS. **Step 5:** `git commit -am "feat(termos): publicação com revisão jurídica e 15 dias (#46)"`

### Task 2.3: Cartão do paciente lê a agenda publicada

**Files:** modificar `data_subject_rights_service.dart` (`termsChangeReader` vira `Future<TermsChangeSchedule?> Function()`, padrão = `TermsVersionStore.currentPublished()`; `termsChangeNotice` fica `async`), `patients_endpoint.dart:199-215`, `terms_change_schedule_test.dart`, `data_subject_rights_service_test.dart`, `data_subject_rights_endpoint_test.dart`.

- [ ] **Step 1: Testes** — com versão publicada e `now` entre `publishedAt` e `effectiveFrom` → devolve o aviso; antes de `publishedAt` ou depois de `effectiveFrom` → `null`; **rascunho/revisado mas não publicado → `null`**; sem linhas → `null` (comportamento atual preservado).
- [ ] **Step 2: FAIL. Step 3: Implementar** (manter `upcomingTermsChange` como fallback somente até o teste atual migrar; remover a constante ao final e atualizar o comentário de `legal_documents.dart:73`). **Step 4:** `dart test test/unit test/integration/data_subject_rights_endpoint_test.dart` → PASS.
- [ ] **Step 5:** `git commit -am "feat(termos): cartão do paciente lê a agenda publicada (#46)"`

### Task 2.4: Endpoints de termos (staff)

**Files:** modificar `endpoints/admin_endpoint.dart`; criar `models/api/terms_version_entry.spy.yaml`.

- [ ] Métodos `termsVersions`, `draftTermsVersion`, `markTermsReviewed`, `publishTermsVersion`; teste de integração: paciente/ACS → `AlertPermissionException` + linha `denied_role`; admin completa o fluxo rascunho → revisão → publicação e `GET` do cartão pelo paciente mostra a versão. Rodar `dart test test/integration` (esperado: tudo verde). Commit `feat(termos): endpoints de rascunho, revisão e publicação (#46)`.

### Task 2.5: Regressão do backend e documentação

- [ ] `cd backend/sinalacs_server && dart analyze && dart test` → 0 erros, 0 falhas. Atualizar `backend/CLAUDE.md` (endpoints novos) e `PROGRESS.md` (#46, backend). Commit `docs(avisos): backend da #46 (#46)`.

---

## Fase 3 — UI no `apps/admin` (somente Android; nada em `apps/admin/web/`)

**Decisão de navegação:** uma única aba nova, **"Avisos"** (`AdminDestination.notices`), com duas sub-abas internas: **Avisos** (coordenador e admin) e **Termos** (somente admin; para o coordenador a sub-aba não existe). Duas abas novas deixariam sete itens na `NavigationBar` de 360 dp, abaixo do tamanho de toque. O destino passa de 5 para 6 itens, e o rótulo curto na barra é "Avisos".

**Contrato dos DTOs** (fixa os campos das Tasks 1.6 e 2.4; o cliente gerado terá estes nomes):
- `NoticeHistoryEntry { id, microAreaId, microAreaName, audience: String, title, status: ScheduledNoticeStatus, scheduledFor, sentAt?, recipients?, accepted?, failureReason?, createdByLabel }` (sem `message`) e `NoticeHistoryPage { entries: List<NoticeHistoryEntry> }`
- `TermsVersionEntry { id, version, summary, effectiveFrom, createdAt, legallyReviewedAt?, publishedAt? }`
- Métodos em `AdminEndpoint`: `scheduleNotice(accessToken, microAreaId, audience, title, message, scheduledFor) → String`, `cancelScheduledNotice(accessToken, id)`, `noticeHistory(accessToken, microAreaId?, limit, offset) → NoticeHistoryPage`, `termsVersions(accessToken) → List<TermsVersionEntry>`, `draftTermsVersion(accessToken, version, summary, effectiveFrom) → TermsVersionEntry`, `markTermsReviewed(accessToken, id) → TermsVersionEntry`, `publishTermsVersion(accessToken, id) → TermsVersionEntry`.

**Arquivos da fase:**

| Arquivo (em `apps/admin/`) | Ação |
|---|---|
| `lib/core/data/admin_data_source.dart` | modificar: modelos + 7 métodos na interface |
| `lib/core/data/mock_admin_data_source.dart` | modificar: implementação em memória com as mesmas regras do servidor |
| `lib/core/data/backend_admin_data_source.dart` | modificar: implementação sobre `_admin` |
| `test/support/failing_admin_data_source.dart` | modificar: os 7 métodos lançam como os demais |
| `lib/app/notices_screen.dart` | criar: aba "Avisos" (sub-abas, histórico, formulário) |
| `lib/app/terms_panel.dart` | criar: sub-aba "Termos" |
| `lib/app/app.dart` | modificar: destino `notices` e repasse do `role` |
| `test/notices_data_source_test.dart`, `test/notices_screen_test.dart`, `test/terms_panel_test.dart`, `test/notices_a11y_test.dart` | criar |
| `test/support/layout_harness.dart`, `test/contrast_tokens_test.dart`, `integration_test/admin_notices_e2e.dart` | modificar/criar |

### Task 3.1: Modelos e contrato do data source (com o mock)

**Files:** modificar `lib/core/data/admin_data_source.dart` (acrescentar antes da `abstract interface class AdminDataSource`, linha ~540), `lib/core/data/mock_admin_data_source.dart`, `test/support/failing_admin_data_source.dart`; Test: `test/notices_data_source_test.dart`.

**Interfaces:** Produces os tipos e métodos abaixo, usados por todas as tasks seguintes.

- [ ] **Step 1: Teste que falha** (`test/notices_data_source_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

final _agora = DateTime(2026, 10, 14, 12);

void main() {
  late MockAdminDataSource fonte;
  setUp(() => fonte = MockAdminDataSource(now: () => _agora));

  test('agendar a menos de 1 minuto recusa; a mais de 1 minuto entra como pending', () async {
    await expectLater(
      fonte.scheduleNotice(microAreaId: 'ma-1', audience: NoticeAudience.everyone,
          title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(seconds: 30))),
      throwsA(isA<AdminValidationFailure>()),
    );
    final id = await fonte.scheduleNotice(microAreaId: 'ma-1', audience: NoticeAudience.chronic,
        title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(hours: 2)));
    final h = await fonte.fetchNoticeHistory();
    expect(h.single.id, id);
    expect(h.single.status, NoticeStatus.pending);
  });

  test('cancelar só vale para pending', () async {
    final id = await fonte.scheduleNotice(microAreaId: 'ma-1', audience: NoticeAudience.everyone,
        title: 'T', message: 'M', scheduledFor: _agora.add(const Duration(hours: 2)));
    await fonte.cancelScheduledNotice(id);
    expect((await fonte.fetchNoticeHistory()).single.status, NoticeStatus.cancelled);
    await expectLater(fonte.cancelScheduledNotice(id), throwsA(isA<AdminValidationFailure>()));
  });

  test('termos: publicar sem revisão recusa; com revisão e 15 dias aceita; 14 dias recusa', () async {
    final t = await fonte.draftTermsVersion(
        version: '2099.1', summary: '[TEXTO PLACEHOLDER]', effectiveFrom: _agora.add(const Duration(days: 15)));
    await expectLater(fonte.publishTermsVersion(t.id), throwsA(isA<AdminValidationFailure>()));
    await fonte.markTermsReviewed(t.id);
    expect((await fonte.publishTermsVersion(t.id)).publishedAt, _agora);

    final curto = await fonte.draftTermsVersion(
        version: '2099.2', summary: '[TEXTO PLACEHOLDER]', effectiveFrom: _agora.add(const Duration(days: 14)));
    await fonte.markTermsReviewed(curto.id);
    await expectLater(fonte.publishTermsVersion(curto.id), throwsA(isA<AdminValidationFailure>()));
  });
}
```

- [ ] **Step 2:** `cd apps/admin && flutter test test/notices_data_source_test.dart` → FAIL (tipos inexistentes). Confirme também o construtor do mock: `grep -n "MockAdminDataSource(" lib/core/data/mock_admin_data_source.dart` e, se não aceitar `now:`, use o parâmetro de relógio que ele já tem (visto em `escalateAlert`, que usa `_now()`).
- [ ] **Step 3: Implementar.** Em `admin_data_source.dart`:

```dart
enum NoticeAudience { everyone, chronic }

enum NoticeStatus { pending, sending, sent, unknown, failed, cancelled }

class NoticeHistoryItem {
  const NoticeHistoryItem({
    required this.id, required this.microAreaId, required this.microAreaName,
    required this.audience, required this.title, required this.status,
    required this.scheduledFor, required this.createdByLabel,
    this.sentAt, this.recipients, this.accepted, this.failureReason,
  });
  final String id;
  final String microAreaId;
  final String microAreaName;
  final NoticeAudience audience;
  final String title; // nunca a mensagem: o histórico não a devolve
  final NoticeStatus status;
  final DateTime scheduledFor;
  final String createdByLabel;
  final DateTime? sentAt;
  final int? recipients;
  final int? accepted;
  final String? failureReason;
}

enum TermsVersionState { draft, reviewed, published }

class TermsVersionSummary {
  const TermsVersionSummary({
    required this.id, required this.version, required this.summary,
    required this.effectiveFrom, required this.createdAt,
    this.legallyReviewedAt, this.publishedAt,
  });
  final String id;
  final String version;
  final String summary;
  final DateTime effectiveFrom;
  final DateTime createdAt;
  final DateTime? legallyReviewedAt;
  final DateTime? publishedAt;

  TermsVersionState get state => publishedAt != null
      ? TermsVersionState.published
      : legallyReviewedAt != null
          ? TermsVersionState.reviewed
          : TermsVersionState.draft;
}
```

e na interface:

```dart
  Future<List<NoticeHistoryItem>> fetchNoticeHistory({String? microAreaId, int limit = 50, int offset = 0});
  Future<String> scheduleNotice({required String microAreaId, required NoticeAudience audience,
      required String title, required String message, required DateTime scheduledFor});
  Future<void> cancelScheduledNotice(String id);
  Future<List<TermsVersionSummary>> fetchTermsVersions();
  Future<TermsVersionSummary> draftTermsVersion({required String version, required String summary, required DateTime effectiveFrom});
  Future<TermsVersionSummary> markTermsReviewed(String id);
  Future<TermsVersionSummary> publishTermsVersion(String id);
```

No mock: listas `_avisos`/`_termos`, id sequencial (`'aviso-${n}'`), mesmos textos de erro do servidor (`'Agende para pelo menos 1 minuto à frente.'`, `'Só avisos pendentes podem ser cancelados.'`, `'A versão ainda não foi revisada juridicamente.'`, `'A vigência exige 15 dias de antecedência.'`), `microAreaName` buscado em `fetchMicroAreas()`. No `FailingAdminDataSource`, os 7 métodos lançam o mesmo erro que os outros métodos dele (siga o corpo de `escalateAlert` ali).

- [ ] **Step 4:** `flutter test test/notices_data_source_test.dart` → PASS; `flutter analyze` → sem erros (qualquer outro implementador de `AdminDataSource` aparece aqui e deve ganhar os métodos).
- [ ] **Step 5:** `git commit -am "feat(admin): contrato de avisos e termos no data source (#46)"`

### Task 3.2: Implementação sobre o backend

**Files:** modificar `lib/core/data/backend_admin_data_source.dart` (junto de `escalateAlert`, linha ~198); Test: `test/notices_backend_data_source_test.dart` (padrão `_fonte(FakeEndpointCaller)` de `test/backend_admin_data_source_test.dart:14`).

**Interfaces:** Consumes o cliente gerado da Task 1.6/2.4 (rodar `serverpod generate` no backend antes, e o app já usa `sinalacs_client` por path).

- [ ] **Step 1: Testes que falham**

```dart
test('histórico: mapeia status e público por nome e não pede a mensagem', () async {
  final caller = FakeEndpointCaller(result: api.NoticeHistoryPage(entries: [
    api.NoticeHistoryEntry(id: 'n1', microAreaId: 'ma-1', microAreaName: 'Microárea A',
        audience: 'chronic', title: 'T', status: api.ScheduledNoticeStatus.sent,
        scheduledFor: DateTime.utc(2026, 10, 14, 15), createdByLabel: 'ADM-001',
        sentAt: DateTime.utc(2026, 10, 14, 15, 1), recipients: 3, accepted: 2),
  ]));
  final r = await _fonte(caller).fetchNoticeHistory(microAreaId: 'ma-1');
  expect(r.single.status, NoticeStatus.sent);
  expect(r.single.audience, NoticeAudience.chronic);
  expect(r.single.accepted, 2);
  expect(caller.lastArgs, containsPair('accessToken', 'token-de-teste'));
});

test('recusa de validação do servidor vira AdminValidationFailure com a mensagem', () async {
  final caller = FakeEndpointCaller(error: api.AdminInvalidRequestException(message: 'A versão ainda não foi revisada juridicamente.'));
  await expectLater(_fonte(caller).publishTermsVersion('t1'),
      throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', contains('revisada'))));
});

test('recusa por papel vira AdminDataFailure, não AdminValidationFailure', () async {
  final caller = FakeEndpointCaller(error: api.AlertPermissionException(message: 'x'));
  await expectLater(_fonte(caller).fetchTermsVersions(), throwsA(isA<AdminDataFailure>()));
});
```

(Confirme no `FakeEndpointCaller` de `test/support/fake_admin_auth.dart` o nome do parâmetro de erro; os testes existentes de `escalateAlert` em `backend_admin_data_source_test.dart` mostram a forma exata.)

- [ ] **Step 2:** FAIL. **Step 3: Implementar** os 7 métodos: leituras com `_guard`, escritas com `_guardEscrita`; `api.ScheduledNoticeStatus.values.byName` ↔ `NoticeStatus.values.byName` (tradução por **nome**, como o resto do arquivo); `audience.name` na ida; `DateTime` sempre `.toUtc()` na ida. **Step 4:** PASS (`flutter test test/notices_backend_data_source_test.dart`). **Step 5:** `git commit -am "feat(admin): avisos e termos sobre o AdminEndpoint (#46)"`

### Task 3.3: Aba "Avisos" — casca, sub-abas por papel e histórico

**Files:** criar `lib/app/notices_screen.dart`; modificar `lib/app/app.dart` (enum linha 55, extensões 57-83, `_telaAtual` linha ~170); Test: `test/notices_screen_test.dart`.

**Interfaces:** Produces `NoticesScreen({required AdminDataSource dataSource, required String role, DateTime Function() now = DateTime.now})`; chaves `Key('notices_tab_history')`, `Key('notices_tab_terms')`, `Key('notice_row_<id>')`, `Key('notice_new_button')`, `Key('notice_cancel_<id>')`.

- [ ] **Step 1: Testes que falham** (padrão `_abrir` de `data_requests_screen_test.dart:104`: `MaterialApp(theme: buildAdminTheme(), home: Scaffold(body: NoticesScreen(...)))`):

```dart
testWidgets('coordenador não vê a sub-aba Termos; admin vê', (tester) async {
  await _abrir(tester, MockAdminDataSource(now: () => _agora), role: 'coordinator');
  expect(find.byKey(const Key('notices_tab_terms')), findsNothing);
  await _abrir(tester, MockAdminDataSource(now: () => _agora), role: 'admin');
  expect(find.byKey(const Key('notices_tab_terms')), findsOneWidget);
});
testWidgets('histórico: título, microárea, status e contagens; a mensagem nunca aparece', (tester) async {
  // fonte com 1 aviso sent (recipients 3, accepted 2) e mensagem 'SEGREDO-NAO-EXIBIR' no agendamento
  // expect: find.text('Enviado'), find.textContaining('2 de 3'), find.textContaining('SEGREDO'), findsNothing
});
testWidgets('aviso pendente tem Cancelar com confirmação; enviado não tem', (tester) async {});
testWidgets('histórico vazio mostra mensagem própria, falha mostra erro com retry', (tester) async {});
```

Rótulos: `Agendado`, `Enviando`, `Enviado`, `Resultado desconhecido — confira antes de reenviar`, `Falhou`, `Cancelado` (função pura `noticeStatusLabel(NoticeStatus)` testada à parte, tal como `dataRequestStatusLabel`).

- [ ] **Step 2:** FAIL. **Step 3: Implementar** `NoticesScreen` (StatefulWidget com `DefaultTabController`; `FutureBuilder` + `AdminAsyncError` de `admin_async_states.dart`; chamar `dataSource.recordAccess(actionType: 'view', resourceType: 'community_notices')` antes de listar, como `data_requests_screen.dart:78`; botões com `minimumSize: Size(48, 52)`). Em `app.dart`: `AdminDestination.notices` depois de `dataRequests`, `label 'Avisos'`, `Icons.campaign_outlined`, e `AdminDestination.notices => NoticesScreen(dataSource: widget.dataSource, role: widget.session.role, now: widget.now)`. Atualize `destinosDoBackoffice` em `test/support/layout_harness.dart:32` para incluir `'Avisos'` e os testes que contam destinos (`flutter test` indicará quais: `responsive_layout_test`, `admin_home_shell_test`, `text_scale_test`).
- [ ] **Step 4:** `flutter test` completo do app → PASS. **Step 5:** `git commit -am "feat(admin): aba Avisos com histórico por papel (#46)"`

### Task 3.4: Formulário de agendamento

**Files:** modificar `lib/app/notices_screen.dart` (diálogo `_NoticeForm`); Test: `test/notices_screen_test.dart`.

- [ ] **Step 1: Testes que falham**

```dart
testWidgets('enviar fica desabilitado com título/mensagem vazios e acima de 60/240', (tester) async {
  // abre pelo notice_new_button; campos notice_title, notice_message; botão notice_submit
  // título de 61 caracteres: maxLength do campo impede digitar o 61º (find.text('60/60'))
});
testWidgets('data no passado ou a menos de 1 minuto: mostra erro e não chama scheduleNotice', (tester) async {});
testWidgets('envio válido chama scheduleNotice uma vez com a microárea escolhida e recarrega o histórico', (tester) async {});
testWidgets('duplo toque em Agendar chama o data source uma única vez', (tester) async {
  // fonte com Completer 'portao' como _FakePedidos; dois taps; expect(fonte.agendados, hasLength(1))
});
testWidgets('erro de validação do servidor aparece no diálogo (AdminValidationFailure.message)', (tester) async {});
```

- [ ] **Step 2:** FAIL. **Step 3: Implementar**: `DropdownButtonFormField<String>` de microáreas via `fetchMicroAreas()` (o servidor já escopa pelo coordenador; não filtrar na UI); `SegmentedButton<NoticeAudience>` (Todos / Só crônicos); `TextField` com `maxLength: 60` e `240`; data e hora com `showDatePicker` + `showTimePicker`, padrão `now()+1h`; flag `_enviando` impede duplo toque; `AdminValidationFailure` mostra `e.message` no diálogo, `AdminSessionExpired` chama `AdminSessionScope.maybeOf(context)`. Texto de ajuda fixo: "A mensagem não é gravada na trilha de auditoria." **Step 4:** PASS. **Step 5:** `git commit -am "feat(admin): formulário de agendamento de aviso (#46)"`

### Task 3.5: Sub-aba "Termos" (rascunho → revisão → publicação)

**Files:** criar `lib/app/terms_panel.dart`; ligar em `notices_screen.dart`; Test: `test/terms_panel_test.dart`.

**Interfaces:** Produces `TermsPanel({required AdminDataSource dataSource, required DateTime Function() now})`; chaves `terms_new_button`, `terms_row_<id>`, `terms_review_<id>`, `terms_publish_<id>`.

- [ ] **Step 1: Testes que falham** (todos com texto `[TEXTO PLACEHOLDER]`):

```dart
testWidgets('rascunho: Publicar está desabilitado e explica "Aguardando revisão jurídica"', (tester) async {
  // expect(botão terms_publish_<id>.onPressed, isNull); expect(find.text('Aguardando revisão jurídica'), findsOneWidget)
});
testWidgets('Marcar como revisado pede confirmação e depois habilita Publicar', (tester) async {});
testWidgets('vigência < 15 dias: o formulário já mostra erro e o servidor também é respeitado', (tester) async {
  // no diálogo de rascunho, data = now+14d → "A vigência exige 15 dias de antecedência." e submit desabilitado;
  // data = now+15d → habilitado
});
testWidgets('publicada: mostra "Publicada em dd/mm/aaaa · vigora em dd/mm/aaaa" e some com os botões', (tester) async {});
testWidgets('publicar pede confirmação que cita a versão e a vigência', (tester) async {});
```

- [ ] **Step 2:** FAIL. **Step 3: Implementar**: lista ordenada por `createdAt` desc; cartão por versão com selo (`Rascunho`/`Revisada`/`Publicada`, ícone **e** texto, não só cor); formulário de rascunho com `version` (texto), `summary` (`maxLength: 280`, ajuda "Resumo público exibido no cartão do paciente. O texto integral vai no release do app."), data de vigência com piso `now()+15 dias` no `showDatePicker`; diálogo de confirmação em "Marcar como revisado" ("Confirmo que o jurídico revisou a versão X.") e em "Publicar" ("A versão X passará a valer em dd/mm/aaaa. Os pacientes verão o aviso desde hoje."). **Step 4:** PASS. **Step 5:** `git commit -am "feat(admin): painel de termos com bloqueio por revisão jurídica (#46)"`

### Task 3.6: Acessibilidade, contraste e layout em celular

**Files:** Test: `test/notices_a11y_test.dart`; modificar `test/contrast_tokens_test.dart`, `test/touch_targets_test.dart`, `test/text_scale_test.dart` (acrescentar a aba nova ao que já percorrem); `lib/app/notices_screen.dart`/`terms_panel.dart` conforme as falhas.

- [ ] **Step 1: Testes que falham**: (a) cada botão novo com altura pintada e alvo ≥ 48 dp (padrão `touch_targets_test.dart`); (b) `percorrerTelaInteira` na aba Avisos e em Termos a 360×640 com fonte 1.0 e 2.0 (sem estouro); (c) cada cor usada como texto/ícone nos selos de status tem contraste ≥ 4.5:1 sobre o `Card` (usar `test/support/contrast.dart`; selos de status usam tokens `*OnSurface` — ver `apps/CLAUDE.md`, seção de contraste WCAG); (d) `Semantics` com rótulo nos botões só-ícone.
- [ ] **Step 2:** `flutter test test/notices_a11y_test.dart test/touch_targets_test.dart test/text_scale_test.dart test/contrast_tokens_test.dart` → FAIL onde houver violação. **Step 3:** corrigir a UI. **Step 4:** PASS. **Step 5:** `git commit -am "test(admin): acessibilidade e layout de avisos e termos (#46)"`

### Task 3.7: Integração hermética no emulador Android

**Files:** criar `integration_test/admin_notices_e2e.dart` (sobre o `MockAdminDataSource`, como `admin_mobile_smoke_test.dart`).

- [ ] **Step 1:** escrever o roteiro: entrar como admin (`entrarComCredenciais`), abrir "Avisos", agendar um aviso, ver `Agendado` no histórico, cancelar; abrir "Termos", criar rascunho `[TEXTO PLACEHOLDER]`, ver o Publicar bloqueado, marcar revisado, publicar, ver `Publicada`. Segundo teste: entrar como coordenador (`FakeAdminAuth` com papel `coordinator`; confira o parâmetro em `test/support/fake_admin_auth.dart`) e provar que "Termos" não existe.
- [ ] **Step 2:** subir o emulador (comandos abaixo) e rodar `cd apps/admin && flutter test integration_test/admin_notices_e2e.dart -d emulator-5554` → PASS. **Step 3:** `flutter build apk --debug` → sucesso (CI: `admin-android-build`). **Step 4:** `git commit -am "test(admin): integração de avisos e termos no emulador (#46)"`

Comandos de emulador (Fases 3 e 4):

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/flutter/bin"
emulator -list-avds
emulator -avd <AVD_com_Google_APIs> -no-snapshot-save &     # Play Services é necessário para o FCM
adb wait-for-device && adb devices                           # esperado: emulator-5554  device
./scripts/dev/bootstrap_env.sh && ./scripts/dev/sync_dev_ca.sh
cd apps/admin   && flutter run -d emulator-5554              # backoffice (Avisos e Termos)
cd apps/patient && flutter run -d emulator-5554              # onde o cartão e a bandeja aparecem
```

iOS: o projeto não suporta (CLAUDE.md, "iOS" em "Still missing"). A validação é somente no emulador Android.


## Fase 4 — E2E com Gorush (`push_e2e.sh`)

### Task 4.1: Caso do aviso agendado em `push_e2e.sh`

**Files:** modificar `scripts/qa/push_e2e.sh` (após o "caminho feliz", antes de `--negativos`); criar `apps/acs/tool/schedule_notice.dart` (ou no `apps/admin`) que loga como staff, agenda para `now+90s` e imprime só `id=<uuid>`.

- [ ] **Step 1:** escrever o bloco do script: agenda, `na_bandeja` com o título após o vencimento (a função espera até 45 s; usar agenda de 60–90 s e `sleep` inicial de 60 s), e `psql_q "select status from scheduled_notices order by \"createdAt\" desc limit 1"` deve ser `sent`; `audit_logs` deve ter linhas `scheduled` e `granted` para `community_notice`.
- [ ] **Step 2:** cenário negativo: paciente tenta agendar → falha e `denied_role` na trilha.
- [ ] **Step 3: Rodar** `./scripts/qa/push_e2e.sh --e2e-db --negativos`. Expected: `OK — o aviso chegou ao emulador`. Sem a chave FCM o script sai com 3 — nesse caso registrar no PR que o e2e depende das credenciais (ver `scripts/qa/ci_push_e2e.sh` para o job `android-e2e`).
- [ ] **Step 4:** atualizar `scripts/qa/ci_push_e2e_test.sh` se o roteiro mudou; `./scripts/qa/ci_invariants.sh` → verde.
- [ ] **Step 5: Commit** — `git commit -am "test(avisos): e2e do aviso agendado no push_e2e (#46)"`

### Task 4.2: Validação manual no emulador (cartão de termos)

- [ ] Com a stack no ar, no `apps/admin`: rascunhar `2099.1` com resumo `[TEXTO PLACEHOLDER]`, tentar publicar (bloqueado), marcar revisado, publicar com vigência ≥ 15 dias; abrir o app do paciente (`cd apps/patient && flutter run -d emulator-5554`) e conferir o `terms_change_notice_card`. Capturar evidência em `docs/superpowers/plans/2026-10-14-issue-46-e2e.log`. Commit `docs(avisos): evidência do e2e da #46 (#46)`.

### Task 4.3: Regressão final

- [ ] `cd backend/sinalacs_server && dart test`; `cd apps/patient && flutter test`; `cd apps/acs && flutter test`; `cd apps/admin && flutter test`; `./scripts/qa/ci_invariants.sh`. Todos verdes. Rodar `graphify update .`. Commit final.

---

## Pendências fora do escopo de código

1. **Revisão jurídica do texto real dos termos/privacidade** — responsável: encarregado de dados/jurídico. O sistema só bloqueia a publicação até alguém marcar "revisado"; ele **não** valida conteúdo. Nenhum texto real foi redigido neste plano.
2. Coordenador sem UBS associada: o servidor recusa (fail-closed, como `AdminScope`); criar coordenadores continua fora da UI (CLAUDE.md).
3. `push_e2e.sh` exige credenciais reais do Firebase (`fcm-service-account.json`, `google-services.json`); sem elas só os testes de unidade/integração rodam.
4. Release do app do paciente com o texto novo e troca de `consentPolicyVersion`/`legalDocumentsVersion` na data de vigência (procedimento já descrito em `legal_documents.dart`).
5. iOS/APNs e dispositivo físico seguem fora do projeto (CLAUDE.md, "Still missing").
6. Retenção do histórico de avisos (LGPD): definir prazo de expurgo de `scheduled_notices.message` com o encarregado.

---

## Self-review

- **Cobertura:** criar/agendar por microárea ✔ (1.1–1.6), histórico ✔ (1.3), termos com 15 dias ✔ (2.2), bloqueio por revisão ✔ (2.2), cartão lendo a agenda ✔ (2.3), auditoria e papel no backend ✔ (1.2, 2.2, 2.4), negação auditada ✔, e2e Gorush ✔ (4.1). UI ✔ (Fase 3, `apps/admin` Android).
- **Placeholders:** os corpos de teste elididos (`/* ... */`) em 1.2 e 2.2 repetem o padrão do primeiro teste de cada tarefa e devem ser escritos por completo na execução; alguns testes de widget da Fase 3 trazem só o roteiro em comentário e devem ser escritos por completo seguindo o primeiro teste da task.
- **Consistência de tipos:** `ScheduledNoticeStatus`, `ScheduledNoticeStore.claimDue/finish`, `NoticeSchedulingService.schedule/cancel/history/dispatchDue`, `TermsPublicationService.draft/markReviewed/publish/list` usados com os mesmos nomes entre as tarefas.
