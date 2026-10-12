# Issue #44 — Ações operacionais sobre alertas e atualização em tempo quase real — Plano de Implementação

> **Para executores:** REQUIRED SUB-SKILL: usar superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans, tarefa a tarefa. Os passos usam checkbox (`- [ ]`).
> **Esta etapa produz só o plano. Nenhum código de produção foi escrito.**

**Goal:** dar ao coordenador/admin a ação auditada e idempotente de *escalonar* um alerta vermelho pendente além do prazo, manter a lista de Alertas e o painel atualizados sem refresh manual e mostrar quando o dado está velho — sem abrir nenhum caminho para descartar, silenciar ou reclassificar um alerta vermelho sem registro.

**Architecture:** o escalonamento **não muda `alerts.status`**: grava colunas aditivas (`escalatedAt`, `escalatedBy`, `escalationReason`) com `UPDATE … WHERE "escalatedAt" IS NULL`, mais uma linha em `audit_logs` na mesma transação, seguindo o padrão `AdminAccountService` (papel/escopo por `AdminScopeResolver`, auditoria fail-closed). O tempo real v1 é *polling* no app do admin (ADR na Fase 2); a UI ganha um `Timer` periódico, botão "Escalonar" e um selo de dado desatualizado.

**Tech Stack:** Serverpod 3.4.13 (Dart), Postgres, Mosquitto, Flutter (`apps/admin`), `flutter_test`, `dart test`, emulador Android via `scripts/qa/*`.

**Spec:** `spec/PRD_system.md` (INV-03, §1.3 TMRAV, FSM §2.3.1, RF13), `spec/lgpd_design.md`, `spec/ux_accessibility_assessment.md`, issue #44 (sem comentários).

---

## 0. Decisões (respondidas em 2026-10-11) e riscos

| # | Decisão | Efeito no plano |
|---|---------|-----------------|
| D1 | **Aprovado:** `RED_ALERT_ESCALATION_SECONDS`, default 300 s, global, faixa 30–3600. | Task 1 como escrita. Registrar no PRD como regra nova (ID a atribuir). |
| D2 | **Aprovado:** marcar, auditar e reenfileirar no outbox (sem SAMU/outra microárea). | Task 6 como escrita. |
| D3 | **Aprovado:** `status` continua `pending`; colunas `escalatedAt/By/Reason`. | Tasks 2, 3, 7. `AlertStatus.escalated` segue sem escritor (teste de inventário). |
| D4 | **Aprovado:** motivo = enum fechado, sem texto livre. Os nomes `NO_RESPONSE`/`RESOURCES_UNAVAILABLE` citados na avaliação eram exemplos; mantenho `noAckTimeout`, `acsUnreachable`, `patientRecontact` (cobrem o caso da issue). Troque se quiser outros nomes antes da Task 2 (a migração fixa o enum). | Task 2. |
| D5 | **Aprovado com ressalva:** a tela de monitoramento é uma *sessão*. Audita-se `MONITORING_SESSION_START` (abertura) e `MONITORING_SESSION_END`; o polling **não** grava linha por requisição. Registrar a política no ADR. Substitui minha proposta de amostragem 1/20. | Tasks 8, 9, 11 (ver abaixo). |
| D6 | Fora do escopo ("anotar"). | — |
| D7 | **Aprovado:** o expurgo **pula** vermelho `pending`, e levanta um aviso técnico (contagem no resultado do expurgo + log sem identidade). "Encerramento forçado administrativo" fica como pendência nomeada no `PROGRESS.md`, não nesta issue. | Tasks 3, 4, 14. |

**Ressalva técnica sobre D5 (decidi assim, diga se discorda):** `SESSION_END` é *best effort* e não pode ser a única prova. O app fecha, perde rede ou o processo morre sem enviá-lo. Por isso: (1) `START` é fail-closed (já é o `recordAccess` da abertura); (2) `END` é enviado no `dispose` e na perda de foco, e é gravado com `recordSafely` (única exceção justificada à regra do projeto, porque não protege dado nenhum); (3) o servidor fecha por inatividade: um poll que chega depois de 3 × o intervalo sem pulso anterior inicia uma nova sessão (grava `START`), de modo que sessões órfãs ficam visíveis na trilha. (4) Recusas do poll (papel/escopo) continuam sempre auditadas, e `alertsPulse` devolve só contagens, sem identidade.

**Riscos:** (R1) migração mexe em `alerts`, tabela quente — colunas anuláveis sem default, sem reescrita. (R2) `sinalacs_client` regenerado é compartilhado com os apps ACS/paciente — só adições, rodar a suíte deles. (R3) o selo "desatualizado" depende de relógio — injetar `Clock`/`DateTime Function()` nos testes. (R4) o e2e do emulador derruba a stack de dev (`e2e_stack.sh`) — avisar antes de rodar.

---

## 1. Levantamento (o que já existe)

Confirmado lendo o código em 2026-10-11 (issue #44 sem comentários além do resumo):

| Item | Estado | Onde |
|------|--------|------|
| Lista de alertas do admin | Só leitura, filtro microárea/status, ordem `triggeredAt desc`; sem timer, sem ação | `apps/admin/lib/app/app.dart:470-616` (`AlertsScreen`, `_AlertsList`, `_FiltrosDeAlertas`) |
| Painel | `IndicatorsScreen` carrega **uma vez** (`late Future … = _load()`), sem atualização | `apps/admin/lib/app/app.dart:267-470` |
| API de leitura | `admin.indicators/microAreas/alerts/auditLogs`, escopo UBS, auditoria fail-closed antes do dado | `endpoints/admin_endpoint.dart:22-64`, `application/admin/admin_read_service.dart` |
| Modelo do alerta | `alerts`: `status` (`pending/acknowledged/resolved/escalated`), `acknowledgedAt`, `version`, `retryCount`; **sem** colunas de escalonamento | `models/alert.spy.yaml` |
| Quem escreve `status` | **Só** `OrmAlertStore.save` (`pending`) e `acknowledge` (`acknowledged`, incondicional). `resolved`/`escalated` não têm escritor. | `infrastructure/database/orm_alert_store.dart:39,123` |
| Auditoria | `audit_logs` encadeada por HMAC; evento = `actionType/resourceType/resourceId/result` (sem motivo) | `models/audit_log.spy.yaml`, `application/audit/audit_trail.dart` |
| Padrão a copiar | Escrita admin: `AdminScopeResolver` + store + `AuditTrail.record` | `application/admin/admin_account_service.dart` |
| Broker | ACL: `backend` lê/escreve `sinalacs/v1/#`; `acs-area-12` lê `…/microareas/<uuid>/alerts` e escreve `sinalacs/v1/alerts/+/acks`. **Não há usuário admin.** mTLS + senha + ACL; certificado de cliente por aparelho em produção ainda não existe | `infra/docker/mosquitto/aclfile`, `mosquitto.conf` |
| Varredura do outbox | `Timer.periodic` de 10 s publica entregas pendentes | `backend/sinalacs_server/lib/server.dart:85-105` |
| Testes existentes | `admin_read_service_test`, `admin_scope_test`, `admin_account_service_test`, `red_alert_service_test`, `red_alert_lifecycle_test`, `alert_outbox_dispatcher_test`; integração `admin_read_store_test`, `admin_endpoint_test`, `mqtt_alert_dispatcher_test`, `red_alert_cycle_test`; app: `alerts_screen_test`, `alerts_filter_dynamic_test`, `dashboard_tmrav_test`, `backend_admin_data_source_test` | `backend/sinalacs_server/test/**`, `apps/admin/test/**` |
| Parcialmente implementado? | **Não.** Nada de escalonar, timer ou selo de stale. Só o enum `escalated` (sem escritor) e seu rótulo nas telas. |

---

## Estrutura de arquivos

**Criar**
- `backend/sinalacs_server/lib/src/models/enums/escalation_reason.spy.yaml` — códigos fechados (D4).
- `backend/sinalacs_server/lib/src/models/api/admin_escalation_result.spy.yaml` — resposta do escalonamento (`alertId`, `escalatedAt`, `alreadyEscalated`).
- `backend/sinalacs_server/lib/src/models/api/admin_alerts_pulse.spy.yaml` — resposta leve do poll.
- `backend/sinalacs_server/lib/src/application/admin/alert_escalation_service.dart` — regra de escalonamento (papel, escopo, prazo, idempotência, auditoria).
- `backend/sinalacs_server/test/unit/alert_escalation_service_test.dart`, `test/unit/red_alert_discard_paths_test.dart`, `test/integration/alert_escalation_store_test.dart`.
- `docs/superpowers/specs/2026-10-11-adr-tempo-real-alertas-admin.md` — ADR (o projeto não tem `docs/adr/`; as decisões ficam em `docs/superpowers/specs/` no formato Opções A/B → Decisão → Trade-off, como `spec/PRD_system.md` §ADR).
- `apps/admin/lib/app/stale_badge.dart`, `apps/admin/test/alerts_escalate_test.dart`, `alerts_auto_refresh_test.dart`, `indicators_stale_test.dart`.
- `scripts/qa/admin_alertas_escalonar_e2e.sh` + `apps/admin/integration_test/admin_alertas_escalonar_e2e.dart`.

**Modificar**
- `models/alert.spy.yaml` (+3 colunas), `models/api/admin_alert.spy.yaml` (+`escalatedAt`, `ageSeconds`/`overdue`), `endpoints/admin_endpoint.dart` (+`escalateAlert`, `alertsPulse`), `application/admin/admin_read_service.dart` + `OrmAdminReadStore`, `infrastructure/database/orm_retention_store.dart` (D7), `lib/src/config/app_config.dart` (+`redAlertEscalationSeconds`), `.env.example`, `docker-compose.yml`.
- `apps/admin/lib/core/data/admin_data_source.dart`, `backend_admin_data_source.dart`, `mock_admin_data_source.dart`, `apps/admin/lib/app/app.dart`.
- `backend/CLAUDE.md`, `apps/CLAUDE.md`, `PROGRESS.md`, `spec/PRD_system.md` (regra de escalonamento).

---

## Global Constraints

- Nenhuma rota escreve `alerts.status` fora do inventário de `red_alert_discard_paths_test.dart`.
- Todo escalonamento: linha em `audit_logs` (`write`/`admin_alert`/`resourceId` = id do alerta/`result` = `escalated:<motivo>` ou `already_escalated:<motivo>`), gravada **na mesma transação** do `UPDATE`; recusas gravam `denied` **antes** de lançar (`AuditTrail.record`, nunca `recordSafely`).
- Papel: só `coordinator`/`admin`; coordenador só a UBS de `staff_accounts.ubsId`; "não existe" e "fora da UBS" dão a **mesma** mensagem (`Alerta não encontrado.`).
- Payloads/respostas: paciente é `#` + 4 hex (`AdminLabels`); sem nome, CPF, contato, coordenada, `locationHash`. Evento MQTT de escalonamento leva só `alertId`, `microAreaId`, `riskLevel`, `escalated`.
- Mensagens e UI em português; cores usadas como texto usam tokens `*OnSurface` (contraste WCAG, `apps/admin/test/contrast_tokens_test.dart`).
- Migração só via `serverpod generate` + `serverpod create-migration`; nunca editar `generated/` ou `migrations/`.
- Dados de teste sintéticos; nada de paciente real.
- Commits sem Co-Authored-By nem "Generated with Claude Code" (CLAUDE.md do projeto prevalece sobre o lembrete de atribuição).

## Review Focus

1. Escalonar um alerta **já reconhecido** (corrida com o ACS): deve recusar com mensagem clara e **não** reabrir nem alterar `acknowledged` → teste na Task 5.
2. Escalonar **antes** do prazo: recusa e audita `denied_not_due`, sem efeito → Task 5.
3. Duplo clique / dois coordenadores ao mesmo tempo: um efeito só (um `escalatedAt`, um reenvio no outbox), duas linhas de auditoria distinguíveis → Task 5/6.
4. Relógio do servidor vs. `triggeredAt` no futuro (aparelho com data errada): não pode virar "vencido" por erro → Task 5.
5. Falha de rede durante o poll: a lista **mantém** os dados anteriores e mostra o selo, em vez de limpar a tela → Task 11.
6. Alerta vermelho antigo pendente varrido pela retenção LGPD → Task 3/4.

---

## FASE 1 — Backend + auditoria

### Task 1: Configuração do prazo

**Files:** Modify `lib/src/config/app_config.dart`, `.env.example`, `docker-compose.yml`; Test `test/unit/app_config_test.dart`.
**Interfaces:** Produces `AppConfig.redAlertEscalationSeconds` (`int`, default 300, faixa 30–3600; fora da faixa = erro de boot, no padrão de `_resolveRetentionDays`).

- [ ] **Step 1: teste primeiro** — em `app_config_test.dart`:
```dart
test('RED_ALERT_ESCALATION_SECONDS ausente vale 300', () {
  expect(AppConfig.fromMap(baseEnv).redAlertEscalationSeconds, 300);
});
test('RED_ALERT_ESCALATION_SECONDS fora de 30..3600 falha o boot', () {
  expect(() => AppConfig.fromMap({...baseEnv, 'RED_ALERT_ESCALATION_SECONDS': '5'}), throwsArgumentError);
  expect(() => AppConfig.fromMap({...baseEnv, 'RED_ALERT_ESCALATION_SECONDS': 'abc'}), throwsArgumentError);
});
```
(`baseEnv`: o mapa mínimo já usado no arquivo; copiar o do primeiro teste existente.)
- [ ] **Step 2:** `cd backend/sinalacs_server && dart test test/unit/app_config_test.dart` → FAIL (getter inexistente).
- [ ] **Step 3:** implementar o campo e o parser copiando `_resolveRetentionDays`; documentar a variável em `.env.example` e passar `${RED_ALERT_ESCALATION_SECONDS:-300}` no compose.
- [ ] **Step 4:** mesmo comando → PASS.
- [ ] **Step 5:** `git commit -m "feat(alertas): prazo de escalonamento configurável (#44)"`
**Pronto quando:** teste verde e `docker compose config` não reclama.

### Task 2: Modelo, enum de motivo e migração

**Files:** Create `escalation_reason.spy.yaml`, `admin_escalation_result.spy.yaml`; Modify `alert.spy.yaml`, `admin_alert.spy.yaml`; Test `test/integration/alert_escalation_store_test.dart` (esqueleto).
**Interfaces:** Produces `EscalationReason {noAckTimeout, acsUnreachable, patientRecontact}`; `Alert.escalatedAt: DateTime?`, `escalatedBy: UuidValue?`, `escalationReason: EscalationReason?`; `AdminAlert.escalatedAt: DateTime?`, `AdminAlert.overdue: bool`; `AdminEscalationResult{alertId:String, escalatedAt:DateTime, alreadyEscalated:bool}`.

- [ ] **Step 1: teste primeiro** — integração que lê a coluna: insere um `Alert` sintético com `escalatedAt: null` e confirma `Alert.db.findById(...).escalatedAt == null` (falha: campo não existe → erro de compilação).
- [ ] **Step 2:** `dart test test/integration/alert_escalation_store_test.dart` → FAIL.
- [ ] **Step 3:** editar os `.spy.yaml` (colunas anuláveis, sem default); `serverpod generate && serverpod create-migration` (de `backend/sinalacs_server`); conferir que o SQL gerado é só `ADD COLUMN … NULL`.
- [ ] **Step 4:** `docker compose --profile test up -d postgres-test && dart test test/integration/alert_escalation_store_test.dart` → PASS.
- [ ] **Step 5:** commit `feat(alertas): colunas de escalonamento em alerts (#44)`.
**Pronto quando:** migração aditiva, `dart analyze` limpo, `dart test test/unit` ainda verde.

### Task 3: Inventário de rotas de descarte (o teste que prova o invariante)

**Files:** Create `test/unit/red_alert_discard_paths_test.dart`.
**Interfaces:** Consumes o texto-fonte de `lib/src/**` (mesma técnica de `endpoint_auth_posture_test.dart`).

Rotas a provar uma a uma — cada linha vira um `test(...)`:

| Rota | Prova exigida |
|------|---------------|
| `alerts.acknowledge` (RPC) | muda para `acknowledged` **e** deixa linha de auditoria (se hoje não deixa, o teste falha e a Task 4 corrige) |
| ACK por MQTT (`alerts/+/acks`) | idem, via `MqttAlertDispatcher` com store/auditoria falsos |
| `admin.*` | nenhum método escreve em `alerts` além de `escalateAlert` (varredura do fonte) |
| `alerts.createRedAlert` repetido (idempotência) | não substitui nem apaga o alerta original |
| Outbox esgotando tentativas | `markFailed` nunca remove o alerta nem o marca como entregue; alerta segue `pending` e visível |
| Retenção LGPD | `DELETE FROM alerts` não atinge vermelho `pending` (D7) |
| Anonimização do titular | não apaga nem altera `status` de alerta |
| Qualquer `UPDATE alerts`/`DELETE FROM alerts`/`status:` novo | varredura do fonte com allowlist explícita de arquivos e justificativas |

- [ ] **Step 1:** escrever o teste de varredura:
```dart
test('só os escritores conhecidos tocam alerts.status', () {
  final writers = _grepSources(RegExp(r'status:\s*AlertStatus\.|UPDATE\s+alerts|DELETE FROM alerts'));
  expect(writers.keys, unorderedEquals({
    'infrastructure/database/orm_alert_store.dart',      // save(pending), acknowledge(acknowledged)
    'infrastructure/database/orm_retention_store.dart',  // expurgo LGPD — com guarda de status (Task 4)
    'application/admin/alert_escalation_service.dart',   // não escreve status; só escalatedAt
  }));
});
```
- [ ] **Step 2:** `dart test test/unit/red_alert_discard_paths_test.dart` → FAIL nos itens de ACK-sem-auditoria e retenção (resultado esperado e útil: documenta os buracos reais).
- [ ] **Step 3:** não corrigir aqui; anotar na saída quais falharam (alimenta a Task 4).
- [ ] **Step 4:** commit só do teste marcado `skip: 'Task 4'` nos itens que falham, com o motivo.
**Pronto quando:** o arquivo existe, cada rota tem seu teste e os que falham estão listados no commit.

### Task 4: Fechar os buracos achados na Task 3

**Files:** Modify `application/alerts/red_alert_service.dart` (auditoria do ACK, se faltar), `infrastructure/database/orm_retention_store.dart` (D7), `infrastructure/mqtt/mqtt_alert_dispatcher.dart` (se o ACK por MQTT não audita).
**Interfaces:** Consumes `AuditTrail.record`.

- [ ] **Step 1:** remover os `skip` da Task 3 (testes vermelhos de verdade).
- [ ] **Step 2:** `dart test test/unit/red_alert_discard_paths_test.dart` → FAIL.
- [ ] **Step 3:** correções mínimas: ACK grava `write`/`alert`/`acknowledged` na mesma transação; expurgo ganha `AND NOT ("riskLevel" = 'red' AND status = 'pending')` nos quatro `DELETE`s dos filhos e do pai (D7: pular), o resultado do expurgo ganha `skippedPendingRed` (contagem) e o job loga `Expurgo: N alerta(s) vermelho(s) pendente(s) retido(s)` sem identidade. Teste: vermelho pendente antigo sobrevive; vermelho `acknowledged` antigo é apagado como antes.
- [ ] **Step 4:** `dart test test/unit test/integration/red_alert_cycle_test.dart test/integration/retention*` → PASS (rodar a suíte de retenção existente: `ls test/integration | grep -i retention`).
- [ ] **Step 5:** commit `fix(alertas): ACK e expurgo não descartam vermelho sem registro (#44)`.
**Pronto quando:** inventário todo verde e nenhum teste antigo quebrou.

### Task 5: `AlertEscalationService`

**Files:** Create `application/admin/alert_escalation_service.dart`; Test `test/unit/alert_escalation_service_test.dart`.
**Interfaces:** Consumes `AdminScopeResolver`, `AuditTrail`, `AppConfig.redAlertEscalationSeconds`. Produces
```dart
abstract interface class AlertEscalationStore implements AdminScopeStore {
  /// UPDATE … WHERE id=@id AND ubs-do-escopo AND status='pending'
  /// AND riskLevel='red' AND escalatedAt IS NULL. Devolve o estado final.
  Future<EscalationOutcome> escalate(AdminScope scope, {required String alertId,
      required String actorId, required EscalationReason reason, required DateTime now,
      required Duration threshold, required AuditEvent Function(EscalationOutcome) auditFor});
}
class AlertEscalationService {
  Future<AdminEscalationResult> escalate(AuthenticatedUser user,
      {required String alertId, required EscalationReason reason});
}
enum EscalationOutcome { escalated, alreadyEscalated, notDue, notPending, notRed, notFound }
```
- [ ] **Step 1: testes (unit, store falso)**:
```dart
test('antes do prazo: recusa, audita denied_not_due, não escreve', () async { /* triggeredAt = now-299s */ });
test('depois do prazo: escalona e audita escalated:no_ack_timeout', () async { /* now-301s */ });
test('segunda chamada: alreadyEscalated=true, escalatedAt inalterado, 1 efeito', () async { });
test('alerta já reconhecido: recusa, status inalterado', () async { });
test('alerta amarelo/verde: recusa', () async { });
test('triggeredAt no futuro nunca é vencido', () async { });
test('acs e patient: AlertPermissionException + denied auditado', () async { });
test('coordenador de outra UBS: mesma mensagem de não encontrado', () async { });
test('se a auditoria falha, nada é escrito', () async { });
```
- [ ] **Step 2:** `dart test test/unit/alert_escalation_service_test.dart` → FAIL.
- [ ] **Step 3:** implementar: resolver escopo → validar `alertId` (UUID) → store decide em **uma** transação (lock de linha, releitura, predicado de prazo no SQL com `@now`/`@threshold` — o serviço não decide sobre estado velho) → auditoria dentro da transação via `OrmAuditTrail.recordInTransaction` (padrão da #42).
- [ ] **Step 4:** teste → PASS.
- [ ] **Step 5:** commit `feat(alertas): serviço de escalonamento auditado e idempotente (#44)`.
**Pronto quando:** os 9 testes verdes; nenhum `recordSafely`.

### Task 6: Store ORM + endpoint (Postgres real)

**Files:** Create/Modify `infrastructure/database/orm_alert_escalation_store.dart`, `endpoints/admin_endpoint.dart` (`escalateAlert`), `runtime/alert_runtime.dart` (`alertEscalationServiceFor`); Test `test/integration/alert_escalation_store_test.dart`, `test/integration/admin_endpoint_escalation_test.dart`; Modify `test/unit/endpoint_auth_posture_test.dart` se a allowlist exigir.
**Interfaces:** Produces `admin.escalateAlert(Session, {accessToken, alertId, reason}) → AdminEscalationResult`. Reenfileira a entrega no `AlertOutbox` (D2-b) com payload sem identidade.

- [ ] **Step 1: testes** — (a) duas chamadas concorrentes (`Future.wait`) ⇒ exatamente 1 `escalatedAt` e 1 `enqueue`; (b) coordenador da UBS B recebe a mensagem de não encontrado e **nenhuma** linha de auditoria de sucesso; (c) token de ACS recusado; (d) a linha de auditoria existe, com `resourceId` do alerta e `result` `escalated:no_ack_timeout`; (e) a cadeia de hash segue válida (`AuditChainVerifier`).
- [ ] **Step 2:** `dart test test/integration/alert_escalation_store_test.dart test/integration/admin_endpoint_escalation_test.dart` → FAIL.
- [ ] **Step 3:** implementar, usando `SELECT … FOR UPDATE` na linha (padrão `OrmDataSubjectCaseStore`).
- [ ] **Step 4:** testes → PASS; `dart test` completo do backend → PASS.
- [ ] **Step 5:** commit `feat(alertas): admin.escalateAlert (#44)`.
**Pronto quando:** `dart test` do backend verde e `serverpod generate` sem diff pendente.

### Task 7: Leitura expõe o estado de escalonamento

**Files:** Modify `OrmAdminReadStore`, `admin_read_service.dart`; Test `test/unit/admin_read_service_test.dart`, `test/integration/admin_read_store_test.dart`.
**Interfaces:** `AdminAlert.escalatedAt` e `AdminAlert.overdue` (`red && pending && now-triggeredAt > threshold && escalatedAt == null`, calculado **no servidor**, para a UI não depender do relógio do aparelho).

- [ ] **Step 1:** testes: alerta vencido ⇒ `overdue=true`; escalonado ⇒ `overdue=false`, `escalatedAt` preenchido, **continua** `status=pending` e **continua** contado em `openRedAlerts`; filtro `status=pending` o inclui.
- [ ] **Step 2:** rodar os dois arquivos → FAIL. **Step 3:** implementar. **Step 4:** PASS. **Step 5:** commit.
**Pronto quando:** `openRedAlerts` não muda após escalonar (teste explícito).

---

## FASE 2 — Tempo real

### Task 8: ADR — polling × MQTT para o backoffice

**Files:** Create `docs/superpowers/specs/2026-10-11-adr-tempo-real-alertas-admin.md`.

Conteúdo obrigatório (formato Opções → Decisão → Trade-off, como o PRD):

| Critério | A. Polling (30 s) | B. MQTT com ACL do admin |
|----------|-------------------|--------------------------|
| Latência | ≤ 30 s (+ RTT); meta de TMRAV é 90 s, aceitável para *supervisão*, não para o ACS | < 1 s |
| Custo | 1 requisição leve por coordenador a cada 30 s; negligível na escala do MVP (100 ACS) | conexão longa por coordenador |
| Complexidade | zero infraestrutura nova; reusa token JWT e escopo por UBS já provados | usuário/senha de broker **e certificado de cliente por aparelho** (mTLS está só na stack local — provisionamento de produção é pendência declarada); ACL por tópico não expressa "UBS do coordenador" sem criar tópicos por UBS que hoje não existem |
| Offline | falha ⇒ mantém último dado + selo "desatualizado"; retoma sozinho | reconexão e QoS 1 reentregam, mas a UI precisa do mesmo selo de qualquer jeito |
| Privacidade | resposta já pseudonimizada, escopo checado no servidor a cada chamada | payload MQTT teria de repetir o filtro de UBS fora do banco → segunda implementação da regra de escopo |
| Segurança | superfície já auditada | nova superfície: ACL, credenciais de broker no app do admin |

**Decisão recomendada: A (polling)** agora; B fica registrada como evolução se a latência de supervisão virar requisito, **depois** do provisionamento de certificados por aparelho. Registrar D5 (sessão de monitoramento: START fail-closed, END best-effort, reabertura por inatividade) e o intervalo (30 s, `Timer` pausado com app em segundo plano).
- [ ] Commit `docs(adr): tempo real do backoffice por polling (#44)`. **Pronto quando** o ADR estiver commitado (a decisão já foi aprovada).

### Task 9: `admin.alertsPulse`

**Files:** Create `models/api/admin_alerts_pulse.spy.yaml`; Modify `admin_endpoint.dart` (+`endMonitoringSession`), `admin_read_service.dart`, store; Test unit + integração.
**Interfaces:** `AdminAlertsPulse{ openRed:int, overdueRed:int, maxChangedAt:DateTime?, serverNow:DateTime }`. `serverNow` permite à UI medir o *skew* e é a base do selo de stale.

- [ ] **Step 1:** testes: escopo de UBS; papel; sem PII; `maxChangedAt` muda após ACK **e** após escalonar; sem linha de auditoria por poll em sessão ativa; poll sem pulso nos últimos 3 × 30 s grava `MONITORING_SESSION_START`; `MONITORING_SESSION_END` aceito por `admin.endMonitoringSession` e idempotente; recusa sempre auditada.
- [ ] **Step 2–5:** FAIL → implementar → PASS → commit `feat(admin): alertsPulse leve para o polling (#44)`.
**Pronto quando:** teste de invariante: a resposta não contém nenhuma chave de identidade (varredura do JSON).

---

## FASE 3 — UI e painel (`apps/admin`)

### Task 10: Fonte de dados do app

**Files:** Modify `admin_data_source.dart` (+`escalateAlert`, `alertsPulse`, campos `escalatedAt/overdue`), `backend_admin_data_source.dart`, `mock_admin_data_source.dart`; Test `backend_admin_data_source_test.dart`, `mock_admin_data_source_test.dart`.
- [ ] Teste primeiro: o mapeamento de `AdminAlert → AlertSummary` carrega `overdue`/`escalatedAt`; `escalateAlert` traduz `AlertPermissionException` e "já escalonado" para mensagens em português. `cd apps/admin && flutter test test/backend_admin_data_source_test.dart` → FAIL → implementar → PASS → commit.

### Task 11: Atualização automática + selo de dado desatualizado

**Files:** Create `apps/admin/lib/app/stale_badge.dart`; Modify `app.dart` (`_AlertsScreenState`, `IndicatorsScreen`); Test `alerts_auto_refresh_test.dart`, `indicators_stale_test.dart`.
**Interfaces:** `StaleBadge({required DateTime? lastUpdated, required DateTime now, Duration threshold})`; `AutoRefresh` com `Duration interval = 30s`, `Clock`/`now` injetável.

**Limiar de "stale":** `now − lastSuccess > 2 × intervalo = 60 s` (tolera uma falha de poll). Exibição: faixa `Material` acima da lista/painel, ícone + texto "Dados de HH:mm:ss — sem atualização há N min" (cor via token `*OnSurface`, `Semantics(liveRegion: true)`, nunca só cor). Ao recuperar, some sozinha. Em falha, **mantém** os dados anteriores.

- [ ] **Step 1: testes de widget (`tester.pump(Duration)` com `FakeAsync`)**:
```dart
testWidgets('lista recarrega sozinha após 30 s', ...);   // 2ª chamada ao fetchAlerts sem toque
testWidgets('falha no poll mantém linhas e mostra selo após 60 s', ...);
testWidgets('selo some quando o poll volta a funcionar', ...);
testWidgets('timer é cancelado no dispose (sem timer pendente)', ...);
testWidgets('painel atualiza TMRAV e contagens periodicamente', ...);
testWidgets('painel mostra selo com dado velho', ...);
```
- [ ] **Step 2:** `flutter test test/alerts_auto_refresh_test.dart test/indicators_stale_test.dart` → FAIL.
- [ ] **Step 3:** implementar; o `dispose` chama `endMonitoringSession` (best effort); o poll chama `alertsPulse` e só recarrega a lista quando `maxChangedAt` mudou (economia); o painel recarrega `indicators` a cada ciclo.
- [ ] **Step 4:** PASS + `flutter test` completo + `flutter analyze` + `contrast_tokens_test`/`touch_targets_test`.
- [ ] **Step 5:** commit `feat(admin): atualização automática e selo de dado desatualizado (#44)`.
**Pronto quando:** nenhum `Timer` pendente em teste, selo acessível (semantics), alvo de toque ≥ 48 dp.

### Task 12: Botão "Escalonar"

**Files:** Modify `app.dart` (`_AlertsList` linhas/cartões); Test `apps/admin/test/alerts_escalate_test.dart`.
- [ ] **Step 1: testes**:
```dart
testWidgets('botão visível só para vermelho pendente vencido e não escalonado', ...);
testWidgets('oculto para amarelo, reconhecido, já escalonado e antes do prazo', ...);
testWidgets('toque abre confirmação com seletor de motivo (conjunto fechado) e só envia após confirmar', ...);
testWidgets('após escalonar a linha continua na lista, status "Pendente" + selo "Escalonado às HH:mm"', ...);
testWidgets('toque duplo envia uma única chamada', ...);
testWidgets('erro de permissão mostra mensagem e mantém o botão', ...);
```
- [ ] **Step 2–4:** FAIL → implementar (visibilidade vem de `overdue` do servidor, não do relógio do aparelho) → PASS.
- [ ] **Step 5:** commit `feat(admin): ação de escalonar alerta vermelho (#44)`.
**Pronto quando:** não existe, na UI, nenhum botão de descartar/ocultar/silenciar (teste `find.byTooltip`/texto ausente).

---

## FASE 4 — Validação no emulador

### Task 13: Roteiro e script e2e

**Files:** Create `scripts/qa/admin_alertas_escalonar_e2e.sh` (+ `_test.sh` no padrão `admin_acs_gestao_e2e_test.sh`), `apps/admin/integration_test/admin_alertas_escalonar_e2e.dart`; Modify `bin/seed_e2e_fixtures.dart` (alerta vermelho sintético com `triggeredAt` antigo, só com `E2E_SEED_ALERT_ESCALATION=1`); documentar em `apps/CLAUDE.md`.

**Roteiro (manual ou via `integration_test`)** — ordem do cenário pedido:
1. Subir a stack: `./scripts/dev/bootstrap_env.sh && ./scripts/qa/e2e_stack.sh up` (Postgres `sinalacs_e2e`, backend, **Mosquitto** com mTLS, Traefik). *Avisa: substitui a stack de dev; ao fim `docker compose up -d` a restaura.*
2. Emulador: `emulator -avd <avd> -no-snapshot &` ; `adb wait-for-device` ; `adb devices` deve mostrar `emulator-5554`.
3. Criar o alerta vermelho (paciente sintético do manifesto, `alerts.createRedAlert`).
4. Aguardar o prazo: o script define `RED_ALERT_ESCALATION_SECONDS=30` na stack de e2e para o teste não esperar 5 min; conferir que antes disso o botão **não** aparece.
5. Entrar como coordenador (`/coordenador` do relé `otp_relay.py`), abrir Alertas; botão "Escalonar" aparece; escolher motivo; confirmar.
6. **Sem pull-to-refresh**: lista e painel mudam sozinhos (selo "Escalonado") em ≤ 35 s; `openRedAlerts` no painel inalterado.
7. Perda de conexão: `adb -s emulator-5554 shell svc wifi disable; svc data disable` (ou `docker compose pause backend`); após ~60 s o selo "desatualizado" aparece com os dados anteriores; restaurar (`svc wifi enable` / `unpause`) e o selo some sozinho.
8. Verificações no banco (como `admin_acs_gestao_e2e.sh`): 1 linha `escalated:no_ack_timeout` em `audit_logs`, cadeia íntegra (`dart run bin/audit_chain_check.dart`), `alerts.status='pending'`, `escalatedBy` = coordenador.
9. Reescalonar via RPC direto: continua 1 `escalatedAt`, nova linha `already_escalated`.
10. Regressão offline: `./scripts/qa/e2e.sh` (ACS/paciente) e o fluxo de fila offline do ACS seguem verdes (tarefa que prova "offline não regrediu").

- [ ] **Step 1:** escrever primeiro o `_test.sh` (estrutura do script) e rodá-lo → FAIL. **Step 2:** implementar o script. **Step 3:** `./scripts/qa/admin_alertas_escalonar_e2e.sh` → PASS. **Step 4:** commit `test(e2e): escalonamento e tempo real no emulador (#44)`.
**Pronto quando:** log do script anexado em `docs/superpowers/plans/2026-10-11-issue-44-e2e.log` (padrão da #42/#43).

### Task 14: Documentação e fechamento

**Files:** `backend/CLAUDE.md` (seção "Escalonamento de alertas (#44)"), `apps/CLAUDE.md`, `PROGRESS.md`, `spec/PRD_system.md` (regra de escalonamento + ID), `CLAUDE.md` raiz (lista de endpoints `admin`). Rodar `graphify update .`. Registrar no `PROGRESS.md` a pendência "encerramento forçado administrativo de vermelho órfão" (D7).
- [ ] Verificação final: `cd backend && dart analyze && cd sinalacs_server && dart test`; `cd apps/admin && flutter analyze && flutter test`; `cd apps/acs && flutter test`; `cd apps/patient && flutter test`; `./scripts/qa/ci_invariants.sh`. Só então abrir PR para `develop`.

---

## Autorrevisão

- **Cobertura da issue:** escalonar (Tasks 1–7, 12), tempo quase real (8, 9, 11), painel periódico + stale (11), "nenhum caminho descarta sem registro" (3, 4), testes de widget e backend (5–7, 9–12), emulador (13).
- **Placeholders:** os testes de widget/serviço estão listados por nome e comportamento; o corpo vem do esqueleto dos arquivos vizinhos (`admin_account_service_test.dart`, `alerts_filter_dynamic_test.dart`) que o executor deve abrir no Step 1 — é a única parte deliberadamente não transcrita, porque os fakes existentes têm assinatura que preciso conferir no momento da escrita.
- **Consistência de tipos:** `EscalationReason`, `AdminEscalationResult`, `AdminAlertsPulse`, `overdue`, `escalatedAt` usados com os mesmos nomes nas Tasks 2, 5–7, 9–12.
- **Decisões:** D1–D5 e D7 respondidas; única aberta é a ressalva técnica de D5 (END best-effort).
