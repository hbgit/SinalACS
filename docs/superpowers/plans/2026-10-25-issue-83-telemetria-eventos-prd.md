# ISSUE #83 — Telemetria estruturada dos eventos do PRD §1.3: plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** emitir, guardar sem PII do paciente e tornar mensuráveis os cinco eventos do PRD §1.3 (`alert_triggered`, `alert_received_acs`, `sync_attempt`, `sync_result`, `visit_registered`). Os eventos gerados offline no app do ACS devem chegar ao backend sem perda e sem duplicação, e a visita deve ficar ligada ao alerta que a originou (H1).

**Arquitetura:** os dois eventos de alerta nascem no **backend**, que é o dono dos carimbos do alerta, e são gravados depois do commit, sem nunca bloquear o alerta (INV-03). Os três eventos de campo nascem no **app do ACS**: vão para uma fila local no mesmo SQLCipher das visitas, separada por dono, e sobem por um RPC novo, `telemetry.ingest`, idempotente por `eventId` (`ON CONFLICT DO NOTHING`). Tudo é gravado numa tabela única, `telemetry_events`, com envelope comum e payload JSON validado por esquema fechado. O paciente aparece só como pseudônimo HMAC calculado no servidor. Um CLI de relatório prova que a taxa de sincronização (RNF02/H4) e o intervalo alerta→visita (H1) saem dos eventos.

**Stack:** Serverpod 3.4.13 (Dart), Postgres, Flutter (ACS), `sqflite_sqlcipher`, `connectivity_plus` (já dependência do ACS), `uuid` (já dependência do servidor). Nada novo fora de `spec/stack.md`.

**Spec:** a issue #83 (texto colado na sessão de 2026-10-25), `spec/PRD_system.md` §1.3 (linhas 57–87), `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas EVT-*, RNF02, H1, H2, H4, MOD-RELATORIOS e item 9 do backlog).

**Pré-condição de branch:** a última migração (`20261025201950984`, append-only da #82) está só em `feat/issue-82-auditoria-append-only` (PR #97). Crie `feat/issue-83-telemetria` a partir de `develop` **depois** do merge do PR #97. Se o PR ainda estiver aberto, crie a branch a partir de `feat/issue-82-auditoria-append-only` e rebaseie depois. Criar a migração desta issue antes da #82 inverte a ordem e deixa o `definition.sql` sem o bloco append-only.

---

## Global Constraints

- Nenhum evento carrega nome, CPF, contato, nota, risco clínico de visita ou UUID cru do paciente. O paciente é sempre `patientPseudonym = HMAC-SHA-256(TELEMETRY_PSEUDONYM_KEY, "patient" U+001F <uuid minúsculo>)` em hex, calculado **no servidor**.
- A telemetria nunca falha, atrasa nem desfaz o alerta vermelho, o ACK, o registro ou o envio de visita (INV-03, offline-first). Toda escrita de telemetria é *best-effort*: engole a falha e registra só o tipo do erro (VAZ-01).
- Idempotência por `eventId` (UUID): índice único em `telemetry_events."eventId"` e `INSERT … ON CONFLICT ("eventId") DO NOTHING`. Os eventos do backend usam id determinístico, `Uuid().v5(telemetryNamespace, '<nome>:<alertId>')`, com `telemetryNamespace = '6f1d3c2a-9b4e-5d7f-8a1b-2c3d4e5f6a7b'`.
- O RNF02 não regride: `scripts/qa/measure_latency.dart --samples 10 --visit-count 100` passa com 10/10 lotes sem perda, e `apps/acs/test/offline_burst_test.dart` passa, os dois com a telemetria ligada.
- Esquema de payload fechado: chave desconhecida, tipo errado ou valor fora do domínio recusa **o evento** (que volta em `rejectedEventIds`), nunca o lote.
- `telemetry.ingest` aceita só o papel `acs`, no máximo `200` eventos por chamada (checado antes de tocar o banco) e só os nomes `sync_attempt`, `sync_result` e `visit_registered`. O `actorId` vem do token, nunca do cliente.
- Gerado nunca se edita à mão: `serverpod generate`, `serverpod create-migration` e, logo depois, `./scripts/dev/append_audit_append_only.sh`.
- Textos, comentários e documentação em português, no estilo dos arquivos vizinhos. Commits sem atribuição de IA.
- Testes de integração do backend rodam com `dart test -j 1` e precisam de `docker compose --profile test up -d postgres-test`.

## Decisões que pedem aval do dono antes da execução

| # | Decisão | Recomendação | Por quê |
|---|---|---|---|
| A1 | `alert_triggered.location_hash` do §1.3 | **Não** gravar. No lugar, `location_known: bool`. | `locationHash` é SHA-256 truncado de uma coordenada com 3 casas, e uma grade de ~111 m se reverte por força bruta. Nenhuma métrica do §1.3 usa a posição, e ela continua em `alerts`. O desvio fica registrado numa nota no PRD §1.3. |
| A2 | `acs_id` | UUID cru do ACS em `actorId`. | É profissional (já aparece cru em `audit_logs`), e "visitas por ACS/dia" precisa juntar com `acs`. A restrição de pseudonimização da issue é sobre o paciente. |
| A3 | `device_id` | Pseudonimizado (`devicePseudonym`, HMAC com domínio `"device"`). | Nenhuma métrica precisa do id da instalação em claro. |
| A4 | Retenção de `telemetry_events` | 365 dias (`RETENTION_TELEMETRY_DAYS`), contados de `receivedAt`. | É o mesmo prazo de "logs de acesso" em `spec/lgpd_design.md` §5.6 e cobre um piloto. |
| A5 | Segredo novo `TELEMETRY_PSEUDONYM_KEY` | Independente dos outros quatro, pela regra `_resolveSecret`. | Os segredos do projeto são independentes de propósito. Rotacionar a chave quebra só a ligação entre períodos, nunca a cadeia de auditoria. |

---

## Escopo

**Entra nesta issue:**
- Os cinco eventos com os campos do §1.3, salvo o desvio A1.
- A fila offline do app, o envio idempotente e a correlação alerta→visita (`visit_registered.alert_id`).
- A retenção e a exclusão LGPD dos eventos do titular.
- O CLI de relatório que calcula a taxa de sincronização e o intervalo alerta→visita.
- A atualização da auditoria.

**Vira issue separada (abrir ao fechar esta, com o texto de cada justificativa):**

| Corte | Justificativa |
|---|---|
| Evento de onboarding sem assistência (H2) | Não está no §1.3. Exige instrumentar o app do **paciente**, cuja base legal de telemetria (consentimento × legítimo interesse) ainda não foi decidida pelo DPO, e definir o que é "sem assistência". |
| MOD-RELATORIOS: recorte por período no backoffice, exportação, tela de sincronização, aderência, visitas por ACS/dia e retenção de pacientes | É trabalho de UI e de leitura escopada por UBS (padrão da #40/#45, auditado). Aderência e retenção dependem de dados que nem existem (classificação médica, último login). O CLI desta issue prova a computabilidade, que é o critério de aceite. |
| Instrumentar `DeferredFlushService` (`syncLegacy`/`syncDeferred`) | É o envio de visitas de **outro** dono pela sessão atual: atribuir o evento exige decidir de quem é a tentativa. É um caminho raro (troca de turno no mesmo aparelho) e não muda a ordem de grandeza da taxa. |
| Envio da telemetria em segundo plano do SO | É o mesmo bloqueio das visitas (WorkManager está fora de `spec/stack.md`). |
| Sinal de eventos descartados pelo teto local | Ver o risco R2. Só se o piloto mostrar o teto sendo atingido. |

---

## Esquema dos eventos (extraído do §1.3 e mapeado)

Envelope (colunas de `telemetry_events`): `eventId` (UUID, único), `eventName`, `schemaVersion` (=1), `source` (`backend`|`acsApp`), `occurredAt` (relógio de quem emitiu, UTC), `receivedAt` (relógio do servidor), `clockSkewMs` (`receivedAt − sentAt`, só app), `actorId` (UUID?), `devicePseudonym` (String?), `patientPseudonym` (String?), `alertId` (UUID?), `appVersion` (String) e `payload` (JSON em texto).

| Evento (§1.3) | Campo do PRD → onde fica | Payload v1 (chaves exatas; todas obrigatórias, salvo `?`) |
|---|---|---|
| `alert_triggered` (backend) | `patient_id`→`patientPseudonym`; `risk_level`→payload; `timestamp`→`occurredAt` (= `alerts.triggeredAt`); `location_hash`→A1; `mqtt_topic`→payload | `risk_level: String`, `mqtt_topic: String`, `location_known: bool`, `published: bool` |
| `alert_received_acs` (backend) | `acs_id`→`actorId`; `alert_id`→`alertId`; `timestamp`→`occurredAt` (= `acknowledgedAt`); `latency_ms`→payload | `latency_ms: int ≥ 0`, `channel: 'rpc'|'mqtt'` |
| `sync_attempt` (app) | `device_id`→`devicePseudonym`; `records_count`, `network_type`→payload; `timestamp`→`occurredAt` | `records_count: int 1..10000`, `network_type: 'wifi'|'mobile'|'ethernet'|'vpn'|'none'|'other'|'unknown'`, `channel: 'sync'` |
| `sync_result` (app) | `device_id`→`devicePseudonym`; contagens→payload | `attempt_event_id: uuid`, `success_count`, `failure_count`, `conflict_count`, `rejected_count: int 0..10000`, `outcome: 'synced'|'conflict'|'error'|'rejected'`, `transport_error: bool`, `duration_ms: int ≥ 0` |
| `visit_registered` (app) | `acs_id`→`actorId`; `patient_id`→chega cru em `payload.patient_id` por TLS, o servidor troca por `patientPseudonym` e **remove do payload**; `visit_type`, `offline_flag`, `sync_status`→payload | `local_id: uuid`, `patient_id: uuid` (só na entrada), `visit_type: 'alert'|'routine'`, `alert_id?: uuid` (obrigatório se `visit_type == 'alert'`, proibido se `'routine'`; vai também para a coluna `alertId`), `offline_flag: bool`, `network_type` (domínio acima), `sync_status: 'queued'` |

`sync_status` no registro é sempre `queued`, porque a visita nasce na fila. O destino final da visita se mede pelo `sync_result` e pela junção `local_id` × `visits."localId"` (Task 9).

---

## Estrutura de arquivos

**Backend (`backend/sinalacs_server/`)**
- Criar `lib/src/models/telemetry_event.spy.yaml` (tabela), `lib/src/models/enums/telemetry_source.spy.yaml`, `lib/src/models/api/telemetry_event_input.spy.yaml` e `lib/src/models/api/telemetry_ingest_result.spy.yaml`.
- Criar `lib/src/application/telemetry/`:
  - `telemetry_pseudonymizer.dart`: o HMAC.
  - `telemetry_schema.dart`: nomes, domínios e o validador.
  - `telemetry_service.dart`: `TelemetryRecord`, a interface `TelemetryStore` e `TelemetryService`.
  - `telemetry_metrics.dart`: `TelemetryReport` e a interface `TelemetryMetricsStore`.
- Criar `lib/src/infrastructure/database/orm_telemetry_store.dart` e `orm_telemetry_metrics_store.dart`.
- Criar `lib/src/endpoints/telemetry_endpoint.dart` e `bin/telemetry_report.dart`.
- Modificar:
  - `lib/src/config/app_config.dart`: chave e retenção.
  - `lib/src/runtime/alert_runtime.dart`: `telemetryServiceFor`, injeção no `RedAlertService` e no store de pedidos do titular.
  - `lib/src/endpoints/alerts_endpoint.dart`: emissão de `alert_triggered`.
  - `lib/src/application/alerts/red_alert_service.dart` e `lib/src/infrastructure/database/orm_alert_store.dart`: o retorno do ACK e a emissão de `alert_received_acs`.
  - `lib/src/application/retention/expurge_service.dart` e `lib/src/infrastructure/database/orm_retention_store.dart`.
  - `lib/src/infrastructure/database/orm_data_subject_case_store.dart`.

**App do ACS (`apps/acs/`)**
- Criar `lib/core/telemetry/`:
  - `telemetry_event.dart`: o registro local.
  - `telemetry_store.dart`: a interface, a versão em memória e o teto.
  - `telemetry_recorder.dart`: a emissão.
  - `telemetry_uploader.dart`: o envio.
  - `network_probe.dart`: `connectivity_plus` → `NetworkKind`.
  - `app_version.dart`: `acsAppVersion`.
- Criar `lib/core/database/sqlcipher_telemetry_store.dart`.
- Modificar:
  - `lib/core/database/encrypted_database.dart`: schema v9, `wipeAllData` e `destroy`.
  - `lib/core/services/offline_visit_queue.dart`: `telemetry` opcional e `add(…, {alertId})`.
  - `lib/core/network/backend_client.dart`: `implements TelemetryTransport`.
  - `lib/core/services/visit_queue_factory.dart`.
  - `lib/app/app.dart`: `_save` passa o `alertId`; gatilhos do envio.
  - `lib/main.dart`.
  - `tool/live_check.dart`.
- Criar `integration_test/telemetry_e2e.dart`.

**Scripts e docs**
- Criar `scripts/qa/acs_telemetria_e2e.sh` e `scripts/qa/acs_telemetria_e2e_test.sh`.
- Modificar `scripts/dev/bootstrap_env.sh`, `.env.example`, `docker-compose.yml` e `docker-compose.e2e.yml`.
- Modificar `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart` e `bin/seed_e2e_fixtures.dart`: o consumidor `telemetry`.
- Docs: `docs/auditoria-prd/2026-10-15-lacunas-prd.md`, `spec/PRD_system.md` §1.3 (nota A1), `spec/lgpd_data_audit.md`, `spec/lgpd_design.md` §5.6, `PROGRESS.md`, `backend/CLAUDE.md`, `apps/CLAUDE.md` e `CLAUDE.md` da raiz.

---

## Review Focus

1. **Falha da telemetria derrubando o alerta (INV-03).** Com o store de telemetria lançando, `alerts.createRedAlert` e `alerts.acknowledge` têm de devolver o mesmo resultado de antes e o alerta tem de ser publicado. Testes: Task 6 (`alert_triggered nunca bloqueia o alerta`) e Task 7 (`ACK conclui com a telemetria fora`).
2. **Resposta do `ingest` perdida e reenvio.** O mesmo lote reenviado não pode duplicar linha, e o aparelho apaga o que voltou aceito. Testes: Task 4 (`reenvio do mesmo eventId não duplica`), Task 5 (`ingest repetido devolve os mesmos ids aceitos`) e Task 13 (`falha de rede mantém; aceito some`).
3. **Aparelho compartilhado (RNF06).** Eventos do dono A nunca sobem pela sessão de B. Testes: Task 10 (`oldestForOwner só vê o dono`) e Task 13 (`uploader recusa sessão de outro dono`).
4. **Contrabando de PII no payload.** Chave `notes`, `patient_id` gravado cru, nome no lugar do UUID. Testes: Task 3 (`chave desconhecida recusa o evento`) e Task 5 (`nenhuma linha guarda o UUID do paciente`).
5. **App morto entre `sync_attempt` e `sync_result`.** A tentativa órfã conta como interrompida, nunca como sucesso. Testes: Task 9 (`tentativa sem resultado conta como interrompida`) e Task 12 (`attempt persiste antes do push`).

---

### Task 0: Verificação inicial (sem código)

**Files:**
- Create: `docs/superpowers/plans/2026-10-25-issue-83-verificacao.log`

- [ ] **Step 1: Reproduzir a medição da auditoria no `develop` atual**

Run:
```bash
git fetch origin && git log -1 --format='%h %cI' origin/develop
git grep -nE "alert_triggered|alert_received_acs|sync_attempt|sync_result|visit_registered|telemetr" origin/develop -- backend apps ':!*.md'
```
Esperado (medido em 2026-10-25 sobre `00ad04d`): só `apps/acs/tool/live_check.dart:219,239,275,281` (linhas `METRIC` de stdout da ferramenta, que não são telemetria de produção) e ocorrências de `visit_sync_result` em código gerado. Grave a saída e o commit no log. Se aparecer emissão real em `lib/`, pare e reavalie o plano.

- [ ] **Step 2: Fixar o esquema esperado**

Run: `sed -n 57,87p spec/PRD_system.md >> docs/superpowers/plans/2026-10-25-issue-83-verificacao.log`
Esperado: o bloco YAML com os cinco eventos, igual à tabela "Esquema dos eventos" deste plano.

- [ ] **Step 3: Linha de base do RNF02, antes de qualquer mudança**

Run:
```bash
docker compose up -d --build && (cd apps/acs && flutter test test/offline_burst_test.dart)
dart run scripts/qa/measure_latency.dart --samples 10 --visit-count 100
```
Esperado: `offline_burst_test` passa e o relatório dá 10/10 lotes sem perda. Grave no log o p95 de sync, para comparar na Task 15.

- [ ] **Step 4: Commit**
```bash
git add docs/superpowers/plans/2026-10-25-issue-83-verificacao.log
git commit -m "docs(telemetria): verificação inicial da lacuna EVT-* (#83)"
```

---

### Task 1: Segredo `TELEMETRY_PSEUDONYM_KEY` e retenção `RETENTION_TELEMETRY_DAYS`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/config/app_config.dart`, `scripts/dev/bootstrap_env.sh`, `.env.example`, `docker-compose.yml` (serviço `serverpod`) e `docker-compose.e2e.yml`
- Test: `backend/sinalacs_server/test/unit/app_config_test.dart`

**Interfaces:**
- Produces: `AppConfig.telemetryPseudonymKey: String`, `AppConfig.developmentTelemetryPseudonymKey` (literal de dev), `AppConfig.retentionTelemetryDays: int` (padrão `365`).

- [ ] **Step 1: Testes que falham** em `app_config_test.dart`:
  - `telemetryPseudonymKey: fora de development recusa ausente, vazia e o fallback de dev`: espera `StateError` para cada caso, como os testes do `CPF_HASH_PEPPER`.
  - `telemetryPseudonymKey: development sem valor usa o fallback`.
  - `retentionTelemetryDays: padrão 365, recusa 0 e não inteiro`.
- [ ] **Step 2:** Run `cd backend/sinalacs_server && dart test test/unit/app_config_test.dart`. Esperado: FAIL (getter inexistente).
- [ ] **Step 3: Implementar.**
  - No `AppConfig`, ler pelo `_resolveSecret` (envVarName `TELEMETRY_PSEUDONYM_KEY`) e a retenção pelo mesmo leitor das outras `RETENTION_*`.
  - No `bootstrap_env.sh`, gerar `TELEMETRY_PSEUDONYM_KEY="$(secret)"` e acrescentar só essa variável a um `.env` existente que não a tenha, pelo mesmo caminho do `DEV_ADMIN_PASSWORD`.
  - No compose, `TELEMETRY_PSEUDONYM_KEY: ${TELEMETRY_PSEUDONYM_KEY:-}`.
  - No `.env.example`, um bloco comentado igual ao do `CPF_HASH_PEPPER`.
- [ ] **Step 4:** Run `dart test test/unit/app_config_test.dart && bash scripts/dev/bootstrap_env.sh --help >/dev/null`. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(telemetria): segredo de pseudônimo e prazo de retenção (#83)`.

---

### Task 2: Modelos, tabela `telemetry_events` e migração

**Files:**
- Create: os quatro `.spy.yaml` listados na estrutura
- Generated: `lib/src/generated/**`, `backend/sinalacs_client/**` e `migrations/<novo>/`
- Modify: `spec/lgpd_data_audit.md` (seção nova da tabela)
- Test: `backend/sinalacs_server/test/integration/audit_schema_test.dart` (já existe e precisa continuar verde)

**Interfaces:**
- Produces:
  - Tabela `TelemetryEvent` com os campos do envelope (tipos acima; `payload: String`) e os índices:
    - `telemetry_events_event_id_key` (`eventId`, único);
    - `telemetry_events_name_occurred_idx` (`eventName, occurredAt`);
    - `telemetry_events_alert_idx` (`alertId`);
    - `telemetry_events_patient_idx` (`patientPseudonym`);
    - `telemetry_events_received_idx` (`receivedAt`).
  - Enum `TelemetrySource { backend, acsApp }`.
  - API `TelemetryEventInput { eventId: String, eventName: String, occurredAt: DateTime, appVersion: String, payloadJson: String }`.
  - API `TelemetryIngestResult { acceptedEventIds: List<String>, rejectedEventIds: List<String> }`.
  - Sem `relation` para `alerts` nem para `users`: o expurgo de alertas não pode depender da telemetria, e vice-versa.

- [ ] **Step 1:** Escrever os quatro `.spy.yaml`, com `###` em português explicando cada campo, como em `visit.spy.yaml`.
- [ ] **Step 2:** Run `cd backend/sinalacs_server && serverpod generate && serverpod create-migration && cd ../.. && ./scripts/dev/append_audit_append_only.sh`.
- [ ] **Step 3:** Run `cd backend/sinalacs_server && dart analyze && dart test -j 1 test/integration/audit_schema_test.dart`. Esperado: PASS (o `definition.sql` novo instala o append-only).
- [ ] **Step 4:** Em `spec/lgpd_data_audit.md`, classificar `telemetry_events` campo a campo: `patientPseudonym` como dado pessoal pseudonimizado, `actorId` como dado de profissional e `payload` sem PII por esquema fechado. Atualizar a contagem de tabelas pelo `definition.sql` novo.
- [ ] **Step 5: Commit** com `feat(telemetria): tabela telemetry_events e modelos de ingestão (#83)`.

---

### Task 3: Pseudonimizador e validador de esquema (puros)

**Files:**
- Create: `lib/src/application/telemetry/telemetry_pseudonymizer.dart` e `telemetry_schema.dart`
- Test: `test/unit/telemetry_pseudonymizer_test.dart` e `test/unit/telemetry_schema_test.dart`

**Interfaces:**
- Produces:
  - `class TelemetryPseudonymizer { TelemetryPseudonymizer(String key); String patient(String uuid); String device(String deviceId); }`. Hex de 64 caracteres. A mensagem do HMAC é `'<domínio>\u001f<valor>'` e o UUID entra em minúsculas.
  - `abstract final class TelemetryEventNames { static const alertTriggered = 'alert_triggered', alertReceivedAcs = 'alert_received_acs', syncAttempt = 'sync_attempt', syncResult = 'sync_result', visitRegistered = 'visit_registered'; static const deviceEmitted = {syncAttempt, syncResult, visitRegistered}; }`.
  - `Map<String, Object?>? validateDevicePayload(String eventName, Map<String, Object?> payload)`: `null` quando o evento é inválido; quando é válido, a cópia normalizada **ainda com** `patient_id`, que quem remove é o serviço.

- [ ] **Step 1: Testes que falham**
  - Pseudonimizador:
    - `mesmo uuid em maiúsculas e minúsculas dá o mesmo pseudônimo`;
    - `domínios patient e device não colidem para o mesmo valor`;
    - `chaves diferentes dão pseudônimos diferentes`;
    - `saída não contém o uuid`.
  - Esquema:
    - um `válido: <evento>` por evento de aparelho, com o payload mínimo da tabela de esquema;
    - `chave desconhecida recusa o evento`, com `notes: 'x'` em `visit_registered`;
    - `alert_id obrigatório em visit_type alert e proibido em routine`;
    - `network_type fora do domínio recusa`;
    - `contagem negativa ou acima de 10000 recusa`;
    - `patient_id que não é UUID recusa`;
    - `nome de evento do backend vindo do aparelho recusa`: `alert_triggered` devolve `null`.
- [ ] **Step 2:** Run `dart test test/unit/telemetry_pseudonymizer_test.dart test/unit/telemetry_schema_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar com `package:crypto` (`Hmac(sha256, …)`). O validador é uma tabela `Map<String, _Field>` por evento, sem regex fora de UUID e sem `dynamic` solto. O UUID usa o mesmo formato que `isUuidFormat` já usa no backend: reaproveite a função, não copie.
- [ ] **Step 4:** Rodar o mesmo comando. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(telemetria): pseudônimo HMAC e esquema fechado dos eventos (#83)`.

---

### Task 4: `TelemetryStore` e `OrmTelemetryStore` (idempotente)

**Files:**
- Create: `lib/src/application/telemetry/telemetry_service.dart` (só `TelemetryRecord` e a interface nesta task) e `lib/src/infrastructure/database/orm_telemetry_store.dart`
- Test: `test/integration/orm_telemetry_store_test.dart`

**Interfaces:**
- Produces:
  - `class TelemetryRecord { eventId, eventName, source, occurredAt, receivedAt, clockSkewMs?, actorId?, devicePseudonym?, patientPseudonym?, alertId?, appVersion, Map<String,Object?> payload }`.
  - `abstract interface class TelemetryStore { Future<Set<String>> insertIgnoringDuplicates(List<TelemetryRecord> records); }`, que devolve os `eventId` que existem depois da escrita, novos **ou** já presentes.
  - `OrmTelemetryStore(Session session)`: um único `INSERT … SELECT FROM unnest(...)` ou `VALUES` com parâmetros nomeados e `ON CONFLICT ("eventId") DO NOTHING RETURNING "eventId"`, mais um `SELECT` dos ids já existentes. Sem transação própria.

- [ ] **Step 1: Testes que falham**
  - `grava o lote e devolve todos os ids`;
  - `reenvio do mesmo eventId não duplica`: duas chamadas iguais deixam `count(*) = n` e as duas devolvem os mesmos ids;
  - `lote misto novo+repetido grava só os novos`;
  - `payload sai como JSON válido`: `payload::jsonb` não lança.
- [ ] **Step 2:** Run `dart test -j 1 test/integration/orm_telemetry_store_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar o mesmo comando. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(telemetria): store idempotente por eventId (#83)`.

---

### Task 5: `TelemetryService.ingestFromDevice` e `TelemetryEndpoint.ingest`

**Files:**
- Modify: `lib/src/application/telemetry/telemetry_service.dart` e `lib/src/runtime/alert_runtime.dart` (`TelemetryService telemetryServiceFor(Session session)`)
- Create: `lib/src/endpoints/telemetry_endpoint.dart`
- Generated: o cliente (`serverpod generate`)
- Test: `test/unit/telemetry_service_test.dart` e `test/integration/telemetry_endpoint_test.dart`

**Interfaces:**
- Consumes: `TelemetryPseudonymizer`, `validateDevicePayload` e `TelemetryStore` (Tasks 3–4).
- Produces:
  - `class TelemetryService { TelemetryService({required TelemetryStore store, required TelemetryPseudonymizer pseudonymizer, DateTime Function()? clock}); static const maxIngestBatch = 200; Future<TelemetryIngestResult> ingestFromDevice({required AuthenticatedUser user, required String deviceId, required DateTime sentAt, required List<TelemetryEventInput> events}); }`.
  - Endpoint: `Future<TelemetryIngestResult> ingest(Session session, {required String accessToken, required String deviceId, required DateTime sentAt, required List<TelemetryEventInput> events})`, que estende `AuthenticatedEndpoint`.
  - Regras:
    - papel ≠ `acs`: `StateError`, que o endpoint traduz em `AlertPermissionException`;
    - `events.length > 200`: `ArgumentError`, traduzido em `AlertValidationException`, antes do store;
    - `deviceId` em branco: `ArgumentError`;
    - por evento, fica rejeitado o que tiver `eventId` não UUID, `payloadJson` ilegível, nome fora de `deviceEmitted`, payload inválido ou `occurredAt > sentAt + 5 min`;
    - nos aceitos, `actorId = user.id`, `devicePseudonym = pseudonymizer.device(deviceId)`, `clockSkewMs = receivedAt − sentAt`, `source = acsApp`, `schemaVersion = 1`;
    - em `visit_registered`, `patientPseudonym = pseudonymizer.patient(payload.patient_id)`, `alertId` vindo de `payload.alert_id`, e `patient_id` **removido** do payload gravado;
    - ids duplicados dentro do mesmo lote contam uma vez só.
  - Sem linha em `audit_logs`, porque é métrica e não acesso a dado de titular. A justificativa fica no doc do método, como em `openForMicroArea`.

- [ ] **Step 1: Testes que falham**
  - Unit, com um store falso:
    - `paciente e coordenador recebem StateError`;
    - `lote de 201 é recusado antes do store`;
    - `evento inválido volta em rejected e não vai ao store`;
    - `actorId vem do token, não do payload`;
    - `patient_id sai do payload e vira patientPseudonym`;
    - `occurredAt no futuro além de 5 min é recusado`;
    - `clockSkewMs = receivedAt − sentAt`.
  - Integração, com tokens reais (padrão de `admin_endpoint_test.dart`):
    - `ingest repetido devolve os mesmos ids aceitos e não duplica`;
    - `nenhuma linha guarda o UUID do paciente`: `SELECT count(*) FROM telemetry_events WHERE payload LIKE '%' || @uuid || '%'` dá 0;
    - `ACS sem token recebe a recusa padrão`.
- [ ] **Step 2:** Run `dart test test/unit/telemetry_service_test.dart && dart test -j 1 test/integration/telemetry_endpoint_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar e rodar `serverpod generate`.
- [ ] **Step 4:** Rodar o mesmo comando, mais `dart test test/unit/endpoint_auth_posture_test.dart`. Esperado: PASS. O endpoint estende a base, então a allowlist não muda.
- [ ] **Step 5: Commit** com `feat(telemetria): RPC telemetry.ingest idempotente e sem PII (#83)`.

---

### Task 6: `alert_triggered` no backend

**Files:**
- Modify: `lib/src/application/telemetry/telemetry_service.dart`, `lib/src/endpoints/alerts_endpoint.dart` e `lib/src/runtime/alert_runtime.dart`
- Test: `test/unit/telemetry_service_test.dart` e `test/integration/red_alert_cycle_test.dart` (casos novos)

**Interfaces:**
- Produces: `Future<void> TelemetryService.alertTriggered({required AlertDelivery alert, required bool published})`.
  - Nunca lança: a falha do store vai para `stderr`, só com o tipo do erro.
  - `eventId = Uuid().v5(telemetryNamespace, 'alert_triggered:<alertId>')`, `occurredAt = alert.triggeredAt` e `patientPseudonym = patient(alert.patientId)`.
  - Payload `{risk_level: alert.riskLevel, mqtt_topic: alert.topic, location_known: alert.locationHash != TelemetryService.unknownLocationHash, published}`. Crie `static const unknownLocationHash = 'sem-local-00'`, espelho de `unknownLocationHash` em `apps/patient/lib/core/privacy/location_hash.dart:33`. O teste unit `unknownLocationHash espelha o app do paciente` lê esse arquivo e compara, no mesmo padrão de `legal_documents_test.dart`.
- Chamado em `AlertsEndpoint.createRedAlert` **depois** do `publishNow` e fora da transação. Replay idempotente: o mesmo id faz o `ON CONFLICT` ignorar.

- [ ] **Step 1: Testes que falham**
  - Unit:
    - `alert_triggered tem id determinístico e não carrega locationHash`;
    - `store lançando não propaga`.
  - Integração:
    - `createRedAlert grava um alert_triggered com patientPseudonym e sem UUID do paciente`;
    - `replay com a mesma idempotencyKey não duplica o evento`;
    - `alert_triggered nunca bloqueia o alerta`: um `TelemetryStore` que lança, injetado pelo `AlertRuntime`, mantém `RedAlertResult.alertId` e a linha em `alerts`.
- [ ] **Step 2:** Run `dart test test/unit/telemetry_service_test.dart && dart test -j 1 test/integration/red_alert_cycle_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar. O `AlertRuntime` ganha um *seam* de teste para o store de telemetria, no mesmo padrão dos outros overrides que ele já tem.
- [ ] **Step 4:** Rodar o mesmo comando, mais `dart test test/unit/red_alert_discard_paths_test.dart`. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(telemetria): alert_triggered depois do commit, sem bloquear o alerta (#83)`.

---

### Task 7: `alert_received_acs` no ACK (RPC e MQTT)

**Files:**
- Modify: `lib/src/application/alerts/red_alert_service.dart` (o contrato do `AlertStore.acknowledge`, o construtor e `acknowledge`), `lib/src/infrastructure/database/orm_alert_store.dart`, os fakes em `test/unit/red_alert_service_test.dart`, `red_alert_lifecycle_test.dart` e `red_alert_discard_paths_test.dart`, e `lib/src/runtime/alert_runtime.dart`
- Test: `test/unit/red_alert_service_test.dart` e `test/integration/red_alert_cycle_test.dart`

**Interfaces:**
- Produces:
  - `class AlertAckRecord { final DateTime triggeredAt; final DateTime acknowledgedAt; final bool firstAcknowledgement; }`.
  - `AlertStore.acknowledge(...)` passa a devolver `Future<AlertAckRecord?>`, em que `null` significa não encontrado. O ORM preenche a partir da linha travada: `firstAcknowledgement = alert.acknowledgedAt == null` antes do `UPDATE`.
  - `RedAlertService` ganha o parâmetro opcional `TelemetryService? telemetry`.
  - `acknowledge` continua devolvendo `Future<bool>` para o endpoint e para `lib/server.dart`, sem mudança neles.
  - Quando `firstAcknowledgement` é verdadeiro, chama `Future<void> TelemetryService.alertReceived({required String alertId, required String acsId, required DateTime triggeredAt, required DateTime acknowledgedAt, required String channel})`, com `channel = porMqtt ? 'mqtt' : 'rpc'`, `latency_ms = acknowledgedAt − triggeredAt` (com piso 0) e id determinístico `alert_received_acs:<alertId>`.
  - A emissão acontece depois do retorno do store, isto é, depois do commit da transação própria dele. No ramo `_transaction != null` só há chamada de dentro de transação nos testes. Confira com `grep -n "serviceFor(session, transaction" lib/` e documente o resultado.

- [ ] **Step 1: Testes que falham**
  - Unit:
    - `primeiro ACK emite alert_received_acs com latency_ms`;
    - `ACK repetido não emite`;
    - `ACK por MQTT marca channel mqtt`;
    - `ACK conclui com a telemetria fora`: o serviço de telemetria lança e `acknowledge` devolve `true`.
  - Integração: `ACK pelo RPC grava um evento com actorId do ACS e latency_ms = acknowledgedAt − triggeredAt`.
- [ ] **Step 2:** Run `dart test test/unit/red_alert_service_test.dart test/unit/red_alert_lifecycle_test.dart && dart test -j 1 test/integration/red_alert_cycle_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar e ajustar os fakes ao novo retorno.
- [ ] **Step 4:** Rodar o mesmo comando e depois `dart test test/unit`. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(telemetria): alert_received_acs no primeiro ACK, RPC ou MQTT (#83)`.

---

### Task 8: Retenção e exclusão LGPD dos eventos do titular

**Files:**
- Modify:
  - `lib/src/application/retention/expurge_service.dart`: `RetentionPolicy.telemetryDays`, `RetentionCutoffs.telemetry` e `ExpurgeCounts.telemetryEvents`.
  - `lib/src/infrastructure/database/orm_retention_store.dart`: `DELETE FROM telemetry_events WHERE "receivedAt" < @corte`, contando antes, como as outras tabelas.
  - `lib/src/infrastructure/database/orm_data_subject_case_store.dart`: dentro de `_anonimizar`, `DELETE FROM telemetry_events WHERE "patientPseudonym" = @p`, com o pseudonimizador injetado pelo construtor.
  - `lib/src/runtime/alert_runtime.dart` e `spec/lgpd_design.md` §5.6 (linha da tabela de retenção).
- Test: `test/unit/expurge_service_test.dart`, `test/integration/retention_expurge_test.dart` e o teste de integração existente da exclusão (#42), localizado com `grep -ln "anonymize: true\|completeDataSubjectRequest" test/integration`.

- [ ] **Step 1: Testes que falham**
  - `expurgo remove telemetria vencida e conta`;
  - `expurgo mantém telemetria no prazo`;
  - `exclusão do titular apaga os eventos com o pseudônimo dele e mantém os de outro`.
- [ ] **Step 2:** Rodar os três arquivos. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar os três arquivos. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(telemetria): retenção de 365 dias e exclusão do titular (#83)`.

---

### Task 9: Métricas a partir dos eventos e CLI de relatório

**Files:**
- Create: `lib/src/application/telemetry/telemetry_metrics.dart`, `lib/src/infrastructure/database/orm_telemetry_metrics_store.dart` e `bin/telemetry_report.dart`
- Test: `test/integration/telemetry_metrics_store_test.dart`

**Interfaces:**
- Produces:
  - `class TelemetryReport { attempts, attemptsWithResult, interruptedAttempts, recordsAttempted, recordsSucceeded, double? perAttemptSuccessRate, registeredVisits, registeredVisitsSynced, double? eventualSyncRate, alertLinkedVisits, int? medianAlertToVisitSeconds, int? medianAckLatencyMs }` e `Map<String,Object?> toJson()`.
  - `abstract interface class TelemetryMetricsStore { Future<TelemetryReport> report({required DateTime from, required DateTime to}); }`.
  - SQL:
    - tentativas por `occurredAt` em `[from, to)`;
    - `interruptedAttempts` = `sync_attempt` sem `sync_result` cujo `attempt_event_id` aponte para ela;
    - `perAttemptSuccessRate` = Σ`success_count` / Σ`records_count` das tentativas com resultado;
    - `eventualSyncRate` = `visit_registered` com `payload::jsonb->>'local_id'` presente em `visits."localId"`, dividido pelo total de `visit_registered`;
    - `medianAlertToVisitSeconds` = mediana de `(occurredAt + clockSkewMs ms) − alerts."triggeredAt"` nos `visit_registered` com `alertId` (`percentile_cont(0.5)`);
    - `medianAckLatencyMs` = mediana de `latency_ms` de `alert_received_acs`;
    - sem amostra, o valor é `null` e nunca `0`, mesmo critério do TMRAV.
  - CLI: `dart run bin/telemetry_report.dart --from 2026-10-01 --to 2026-11-01` imprime o JSON. Usa `SERVERPOD_DATABASE_*`, no mesmo padrão de `bin/issue_staff_activation_code.dart`. `--from`/`--to` ausentes ou `from >= to` saem com código 2 e a mensagem de uso.

- [ ] **Step 1: Testes que falham** (com fixtures de eventos gravadas pelo `OrmTelemetryStore`):
  - `taxa por tentativa = sucesso/registros`;
  - `tentativa sem resultado conta como interrompida, não como sucesso`;
  - `taxa final junta visit_registered com visits.localId`;
  - `mediana alerta→visita corrige pelo clockSkewMs`;
  - `janela sem eventos devolve nulos`.
- [ ] **Step 2:** Run `dart test -j 1 test/integration/telemetry_metrics_store_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar o mesmo comando e `dart run bin/telemetry_report.dart` sem argumentos. Esperado: PASS, e o CLI sai com 2.
- [ ] **Step 5: Commit** com `feat(telemetria): relatório de sincronização e alerta→visita a partir dos eventos (#83)`.

---

### Task 10: Fila local de telemetria no app do ACS (schema v9)

**Files:**
- Create: `apps/acs/lib/core/telemetry/telemetry_event.dart`, `telemetry_store.dart` e `apps/acs/lib/core/database/sqlcipher_telemetry_store.dart`
- Modify: `apps/acs/lib/core/database/encrypted_database.dart`
  - `schemaVersion = 9`;
  - `CREATE TABLE IF NOT EXISTS telemetry_events (event_id TEXT PRIMARY KEY, owner TEXT NOT NULL, name TEXT NOT NULL, occurred_at TEXT NOT NULL, payload TEXT NOT NULL)` no `onCreate` e no `_upgrade` para `< 9` (aditivo, sem tocar em `offline_visits`);
  - `wipeAllData` apaga `telemetry_events`, **sem** bloquear a limpeza por causa dela.
- Test: `apps/acs/test/telemetry_store_test.dart` e `apps/acs/test/encrypted_database_test.dart` (caso novo)

**Interfaces:**
- Produces:
  - `class TelemetryEventRecord { final String eventId; final String owner; final String name; final DateTime occurredAt; final Map<String, Object?> payload; }`.
  - `abstract interface class TelemetryStore { Future<void> append(TelemetryEventRecord e); Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}); Future<void> deleteByIds(Iterable<String> ids); Future<int> countForOwner(String owner); }`.
  - `const maxTelemetryEventsPerOwner = 5000`: `append` acima do teto apaga os mais antigos **do mesmo dono**.
  - `class InMemoryTelemetryStore implements TelemetryStore`.
  - `SqlCipherTelemetryStore(VisitDatabase db)`: dono vazio dá `ArgumentError`, como em `VisitStorage.forOwner`.

- [ ] **Step 1: Testes que falham**
  - `oldestForOwner só vê o dono` (A e B no mesmo store);
  - `ordem por occurred_at`;
  - `teto apaga o mais antigo do mesmo dono e não toca no outro`;
  - `deleteByIds ignora id desconhecido`;
  - migração: `v8 → v9 preserva offline_visits e cria telemetry_events`;
  - `wipeAllData com só telemetria não é WipeBlocked`.
- [ ] **Step 2:** Run `cd apps/acs && flutter test test/telemetry_store_test.dart test/encrypted_database_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar o mesmo comando e `flutter test test/device_wipe_test.dart test/remote_wipe_test.dart`. Esperado: PASS. O `destroy()` apaga o arquivo inteiro, então a telemetria sai junto.
- [ ] **Step 5: Commit** com `feat(acs): fila local de telemetria por dono, schema v9 (#83)`.

---

### Task 11: `TelemetryRecorder`, sonda de rede e versão do app

**Files:**
- Create: `apps/acs/lib/core/telemetry/telemetry_recorder.dart`, `network_probe.dart` e `app_version.dart`
- Test: `apps/acs/test/telemetry_recorder_test.dart` e `apps/acs/test/app_version_test.dart`

**Interfaces:**
- Consumes: `TelemetryStore` (Task 10).
- Produces:
  - `enum NetworkKind { wifi, mobile, ethernet, vpn, none, other, unknown }` com `String get wireName`. `typedef NetworkProbe = Future<NetworkKind> Function();` e `NetworkProbe connectivityProbe()`, que mapeia `Connectivity().checkConnectivity()`: lista vazia ou só `none` dá `none`; erro dá `unknown`.
  - `const acsAppVersion = '<versão do pubspec>'`. O teste `app_version_test.dart` lê `pubspec.yaml` e compara.
  - `class TelemetryRecorder { TelemetryRecorder({required TelemetryStore store, required String owner, NetworkProbe? probe, DateTime Function()? clock}); Future<String?> syncAttempt({required int recordsCount}); Future<void> syncResult({required String? attemptEventId, required int successCount, required int failureCount, required int conflictCount, required int rejectedCount, required String outcome, required bool transportError, required Duration duration}); Future<void> visitRegistered({required OfflineVisitRecord visit, String? alertId}); }`.
  - Nenhum método lança: falha do store devolve `null` ou nada.
  - `eventId` é UUID v4, pelo mesmo gerador de `_newLocalId`. Extraia-o para uma função de topo em `offline_visit_queue.dart`, sem duplicar.
  - `syncResult` com `attemptEventId == null` não grava (não há o que ligar).
  - `visitRegistered` grava `local_id: visit.localId`, `patient_id: visit.patientId`, `visit_type` (`alertId == null ? 'routine' : 'alert'`), `alert_id` só quando houver, `offline_flag: kind == none`, `network_type` e `sync_status: 'queued'`.

- [ ] **Step 1: Testes que falham**
  - `syncAttempt grava records_count e network_type e devolve o id`;
  - `syncResult liga attempt_event_id`;
  - `visitRegistered de alerta leva alert_id; de rotina não`;
  - `offline_flag acompanha a sonda`;
  - `store lançando não propaga`;
  - `payload nunca contém notes nem outcome`;
  - `acsAppVersion igual ao pubspec`.
- [ ] **Step 2:** Run `flutter test test/telemetry_recorder_test.dart test/app_version_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar o mesmo comando. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(acs): gravador de telemetria sem conteúdo clínico (#83)`.

---

### Task 12: Emissão na fila de visitas (`sync_attempt`, `sync_result`, `visit_registered`)

**Files:**
- Modify: `apps/acs/lib/core/services/offline_visit_queue.dart`
  - construtor `OfflineVisitQueue({VisitStore? store, this.synchronizer, this.conflictResolver, this.telemetry})`, com `final TelemetryRecorder? telemetry`;
  - `Future<void> add(OfflineVisitRecord record, {String? alertId})`.
- Test: `apps/acs/test/offline_visit_queue_telemetry_test.dart` e `apps/acs/test/offline_burst_test.dart` (caso novo)

**Regras:**
- `add`: grava a visita (`_persist`) **antes** e só então chama `telemetry?.visitRegistered`, sem `await` bloqueante no caminho de erro.
- `_syncOnce`:
  - lote vazio não emite nada;
  - com sincronizador, chama `syncAttempt` **antes** de `push`, com `await` (o evento fica no disco antes do envio);
  - depois de `_applyOutcomes`, chama `syncResult` com as contagens já apuradas ali (`synced`, `errors`, `conflicts`, `rejected`);
  - se `push` lança, grava `failureCount = batch.length`, `transportError = true` e `outcome = 'error'`;
  - a duração é medida por `Stopwatch`.
- O *single-flight* fica como está: a chamada que se junta a um envio em voo não emite nada.
- `resolveKeepLocal` e `resolveKeepServer` não emitem nada (fora do §1.3).
- Com `telemetry == null`, o comportamento é idêntico ao atual, e todos os testes existentes passam sem mudança.

- [ ] **Step 1: Testes que falham**
  - `attempt persiste antes do push`: o sincronizador falso lê o store dentro de `push` e encontra 1 `sync_attempt`;
  - `resultado com contagens synced/erro/conflito/recusa`;
  - `falha de rede emite transport_error e mantém o lote`;
  - `sync em voo chamado duas vezes emite um attempt`;
  - `lote vazio não emite`;
  - `add com alertId emite visit_registered de alerta`;
  - em `offline_burst_test.dart`: `100 visitas com telemetria ligada: nenhuma se perde e 100 visit_registered + 1 attempt + 1 result`, num `InMemoryTelemetryStore` que sobrevive ao "reinício".
- [ ] **Step 2:** Run `flutter test test/offline_visit_queue_telemetry_test.dart test/offline_burst_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Run `flutter test`. Esperado: suíte inteira PASS.
- [ ] **Step 5: Commit** com `feat(acs): fila de visitas emite sync_attempt, sync_result e visit_registered (#83)`.

---

### Task 13: Envio idempotente (`TelemetryUploader`) e transporte no `BackendClient`

**Files:**
- Create: `apps/acs/lib/core/telemetry/telemetry_uploader.dart`
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`class BackendClient … implements AcsBackend, TelemetryTransport`; **não** mexer na interface `AcsBackend`)
- Test: `apps/acs/test/telemetry_uploader_test.dart` e `apps/acs/test/backend_client_test.dart` (caso novo)

**Interfaces:**
- Consumes: `TelemetryStore` e `TelemetryEventRecord`; o cliente gerado `client.telemetry.ingest` (Task 5).
- Produces:
  - `abstract interface class TelemetryTransport { Future<TelemetryIngestAck> ingestTelemetry(List<TelemetryEventRecord> events, {required String expectedUserId}); }`.
  - `class TelemetryIngestAck { final Set<String> accepted; final Set<String> rejected; }`.
  - `class TelemetryUploader { TelemetryUploader({required TelemetryStore store, required TelemetryTransport transport, required String owner, int batchSize = 100, int maxBatchesPerFlush = 10}); Future<TelemetryFlushResult> flush(); }`.
  - `TelemetryFlushResult { int sent; int rejected; bool stoppedByFailure; }`.
  - `flush` é *single-flight*, nunca lança e apaga `accepted ∪ rejected`. Qualquer exceção do transporte (rede, sessão vencida, método inexistente num servidor antigo) **mantém** o lote e para o flush.
  - `BackendClient.ingestTelemetry` recusa com `BackendFailure` quando `session.userId != expectedUserId`, a mesma checagem do `BackendVisitSynchronizer`. Usa o `deviceId` do `DeviceIdStore` e `sentAt = DateTime.now().toUtc()`, e mapeia o registro para `TelemetryEventInput` (`payloadJson = jsonEncode(payload)`, `appVersion = acsAppVersion`).

- [ ] **Step 1: Testes que falham**
  - `falha de rede mantém; aceito some`;
  - `rejeitado também sai do aparelho`;
  - `reenvio após resposta perdida não deixa resto`: o transporte grava e lança na 1ª chamada e aceita na 2ª;
  - `flush concorrente envia uma vez`;
  - `lotes de 100 até esvaziar, no máximo 10 por flush`;
  - `uploader recusa sessão de outro dono`: o `BackendClient` com sessão B e `expectedUserId` A dá `BackendFailure`, sem chamada de rede.
- [ ] **Step 2:** Run `flutter test test/telemetry_uploader_test.dart test/backend_client_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Rodar o mesmo comando, mais `flutter test test/session_store_wiring_test.dart`. Esperado: PASS. O import path de `backend_client.dart` não pode puxar `dart:ui`, porque o `live_check` roda na VM.
- [ ] **Step 5: Commit** com `feat(acs): envio idempotente da telemetria por telemetry.ingest (#83)`.

---

### Task 14: Ligação no app (fábrica da fila, registro com alerta, gatilhos do envio)

**Files:**
- Modify:
  - `apps/acs/lib/core/services/visit_queue_factory.dart`: a fila por sessão recebe `TelemetryRecorder(store: SqlCipherTelemetryStore(db), owner: session.userId, probe: connectivityProbe())`, e a fábrica expõe o `TelemetryUploader` do mesmo dono;
  - `apps/acs/lib/app/app.dart`: em `_VisitRegistrationScreenState._save`, `widget.queue.add(record, alertId: widget.alert?.alertId)`; no `AcsHomeShell`, `uploader.flush()` sem `await` depois de todo `queue.sync()` concluído e nos gatilhos que já existem do `DeferredFlushService` (painel aberto, retomada, conexão de volta);
  - `apps/acs/lib/main.dart`.
- Test: `apps/acs/test/telemetry_wiring_test.dart`

**Regras:** sem `SqlCipher` no `flutter test` (as fábricas aceitam stores injetados, padrão `visitQueue`/`visitPullService`). Os testes que injetam a fila seguem sem telemetria. Trocar de dono (RNF06) descarta o recorder e o uploader do dono anterior junto com a fila.

- [ ] **Step 1: Testes que falham** (widget, com `FakeAcsBackend` mais um `TelemetryTransport` falso):
  - `visita salva pela tela de escalonamento leva o alertId do cartão`;
  - `visita de rotina pelo seletor não leva alertId`;
  - `Sincronizar agora dispara o flush depois do sync`;
  - `conexão que volta dispara o flush`;
  - `trocar de usuário não envia eventos do anterior`.
- [ ] **Step 2:** Run `flutter test test/telemetry_wiring_test.dart`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Run `flutter analyze && flutter test`. Esperado: PASS.
- [ ] **Step 5: Commit** com `feat(acs): telemetria ligada na fila do painel e nos gatilhos de envio (#83)`.

---

### Task 15: RNF02 com telemetria ativa e e2e no emulador

**Files:**
- Modify: `apps/acs/tool/live_check.dart`
  - a fila do `live_check` ganha `TelemetryRecorder(store: InMemoryTelemetryStore(), owner: …)`;
  - depois do sync, `TelemetryUploader(...).flush()` contra o backend real;
  - `ERRO` e `exitCode = 1` se `sent != visitCount + 2`;
  - linha nova `METRIC` `telemetry_flush` com `sent`.
- Modify: `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart` e `bin/seed_e2e_fixtures.dart`: consumidor `telemetry`, um paciente na microárea do ACS, como `push`.
- Create: `apps/acs/integration_test/telemetry_e2e.dart`, `scripts/qa/acs_telemetria_e2e.sh` e `scripts/qa/acs_telemetria_e2e_test.sh` (estrutura, sem Docker, como `admin_alertas_escalonar_e2e_test.sh`)

- [ ] **Step 1: RNF02 com telemetria**

Run:
```bash
docker compose up -d --build
dart run scripts/qa/measure_latency.dart --samples 10 --visit-count 100
(cd apps/acs && flutter test test/offline_burst_test.dart)
```
Esperado: 10/10 lotes sem perda, `telemetry_flush sent=102` em cada amostra e p95 de sync dentro de +10 % da linha de base da Task 0. Acima disso, investigue antes de seguir: a telemetria acrescenta 2 linhas por sync e 1 por visita.

- [ ] **Step 2: Teste de estrutura do script (falha primeiro)**

`acs_telemetria_e2e_test.sh` confere que o script:
- tem `trap cleanup`;
- despausa o `sinalacs-traefik` no cleanup;
- recusa a porta 8765 ocupada;
- reage às linhas marcadoras `E2E_CORTAR_BACKEND`/`E2E_RESTAURAR_BACKEND`;
- roda as consultas `psql` do Step 4 e `telemetry_report.dart`.

Run: `bash scripts/qa/acs_telemetria_e2e_test.sh`. Esperado: FAIL (script inexistente) e depois PASS.

- [ ] **Step 3: `telemetry_e2e.dart`** (sufixo `_e2e`, fora da descoberta, com `@Timeout(minutes: 8)`), na anatomia do `acs_full_e2e.sh`: `e2e_stack.sh up/seed`, relé `/acs`, `adb reverse tcp:8443 tcp:443`. Roteiro do teste:
  1. O ACS entra pela tela (credencial do relé). O paciente `telemetry` dispara o alerta vermelho pelo RPC (`e2e_login.dart`). O ACS recebe pela reserva HTTP, porque o ACL do broker não libera a fixture, e confirma (`alert_triggered` e `alert_received_acs` no servidor).
  2. Imprime `E2E_CORTAR_BACKEND`. O script faz `docker pause sinalacs-traefik`. O teste registra a visita pelo botão `escalation_visit` e mais 2 de rotina, toca "Sincronizar agora" e espera o erro de rede.
  3. Confere no store local 3 `visit_registered`, 1 `sync_attempt` e 1 `sync_result` com `transport_error: true`.
  4. "Reinício": `pumpWidget` de um `SinalAcsApp` novo sobre o **mesmo** SQLCipher. O store local ainda tem os 5 eventos e as 3 visitas pendentes.
  5. Imprime `E2E_RESTAURAR_BACKEND`. O script faz `docker unpause`. O teste toca "Sincronizar agora", espera `synced` e o flush, e confere o store local vazio.
  6. Reenvio forçado: chama `BackendClient.ingestTelemetry` com os mesmos 7 registros guardados no passo 3 e confere que todos voltam em `accepted`.
- [ ] **Step 4: Asserções do script no banco** (`./scripts/qa/e2e_stack.sh psql "<sql>"`):
  - `SELECT "eventName", count(*) FROM telemetry_events GROUP BY 1` dá `alert_triggered 1`, `alert_received_acs 1`, `sync_attempt 2`, `sync_result 2` e `visit_registered 3`;
  - `SELECT count(*) = count(DISTINCT "eventId") FROM telemetry_events` dá `t`, sem duplicação depois do reenvio;
  - `SELECT count(*) FROM telemetry_events WHERE payload LIKE '%<uuid do paciente telemetry>%' OR "patientPseudonym" = '<uuid>'` dá `0`;
  - `SELECT count(*) FROM telemetry_events WHERE "eventName"='visit_registered' AND "alertId" = '<alertId>'` dá `1`;
  - `dart run bin/telemetry_report.dart --from <início> --to <fim>` (com `SERVERPOD_DATABASE_NAME=sinalacs_e2e`) dá `eventualSyncRate 1.0`, `interruptedAttempts 0`, `alertLinkedVisits 1`, `perAttemptSuccessRate 0.5` (3 de 6) e `medianAckLatencyMs` não nulo.
- [ ] **Step 5:** Run `./scripts/qa/acs_telemetria_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-25-issue-83-e2e.log`. Esperado: o teste passa e todas as asserções dão `OK`. Rode também `./scripts/qa/acs_full_e2e.sh` (regressão offline).
- [ ] **Step 6: Commit** com `test(telemetria): RNF02 com telemetria ativa e e2e offline→online no emulador (#83)`.

---

### Task 16: Documentação e auditoria

**Files:** `docs/auditoria-prd/2026-10-15-lacunas-prd.md`, `spec/PRD_system.md` §1.3, `PROGRESS.md`, `backend/CLAUDE.md`, `apps/CLAUDE.md` e `CLAUDE.md` da raiz.

- [ ] **Step 1:** Na auditoria, mude EVT-* para **implementado**, com a evidência: comando (`./scripts/qa/acs_telemetria_e2e.sh`, `measure_latency.dart --samples 10 --visit-count 100`, `dart run bin/telemetry_report.dart`), data e commit `git rev-parse --short HEAD`.
  - RNF02 e H4: "mensurável em campo; medido no piloto" (continua **externo** até o piloto).
  - H1: "correlação alerta→visita disponível".
  - H2 e MOD-RELATORIOS: apontam para as issues novas.
  - Item 9 do backlog: riscado, com o número do PR.
- [ ] **Step 2:** No PRD §1.3, uma nota curta abaixo do YAML: os eventos estão em `telemetry_events`, há o desvio A1 (`location_hash` → `location_known`) e os ids são pseudonimizados.
- [ ] **Step 3:** No `PROGRESS.md`, uma seção "Telemetria dos eventos do §1.3 (#83)" com o entregue, os cortes (com o número das issues abertas) e os riscos residuais R1–R5.
- [ ] **Step 4:** Nos `CLAUDE.md`, um parágrafo cada: no backend, o endpoint, a tabela, o segredo e o CLI; no app, a fila v9, o recorder e o uploader; na raiz, a lista "Already delivered" e o endpoint `telemetry`.
- [ ] **Step 5:** Run `graphify update .` e faça commit com `docs(telemetria): evidência da #83 na auditoria do PRD e nos guias`.

---

## Validação manual no emulador (stack de desenvolvimento)

Pré-requisitos: `./scripts/dev/bootstrap_env.sh` (acrescenta `TELEMETRY_PSEUDONYM_KEY`), `docker compose up -d --build` e `./scripts/dev/run_acs.sh --build` instalado no `emulator-5554`.

Inspeção:
```bash
psql_dev() { docker compose exec -T postgres psql -U "${POSTGRES_USER:-sinalacs_user}" -d "${POSTGRES_DB:-sinalacs_db}" -c "$1"; }
psql_dev 'SELECT "eventName", "occurredAt", "clockSkewMs", "alertId", payload FROM telemetry_events ORDER BY id DESC LIMIT 20'
```

| Cenário | Como gerar | O que conferir |
|---|---|---|
| `alert_triggered` | No app do paciente, botão de urgência (ou `tool/live_check.dart`). | 1 linha, `patientPseudonym` com 64 hex, payload sem `locationHash`. |
| `alert_received_acs` | No ACS, "Confirmar recebimento" no cartão. Repita no MQTT, deixando o ACK chegar pelo broker. | 1 linha por alerta, `latency_ms` ≈ `acknowledgedAt − triggeredAt` de `alerts`, `channel` coerente. O 2º ACK não cria linha. |
| `visit_registered` | Visita pela escalonação (`escalation_visit`) e outra pelo seletor. | `visit_type` `alert` com `alertId` e `routine` sem ele. Antes do sync, nada no servidor. |
| Offline → online | `docker pause sinalacs-traefik`, registrar 3 visitas e "Sincronizar agora" (erro), depois `docker unpause sinalacs-traefik` e "Sincronizar agora". | Depois do unpause chegam 2 `sync_attempt`, 2 `sync_result` (um com `transport_error: true`) e 3 `visit_registered`, com `count(*) = count(DISTINCT "eventId")`. |
| Reinício no meio do sync | Registrar 100 visitas offline. `docker pause sinalacs-traefik`, tocar "Sincronizar agora" e, com o envio pendurado, `adb -s emulator-5554 shell am force-stop br.com.prismrr.sinalacs.acs`. `docker unpause`, reabrir e sincronizar. | Nenhuma visita perdida (`visits` com as 100), `telemetry_report.dart` com `interruptedAttempts 1` e `eventualSyncRate 1.0`, sem `eventId` duplicado. |
| Relatório | `cd backend/sinalacs_server && SERVERPOD_DATABASE_PASSWORD=… dart run bin/telemetry_report.dart --from <hoje> --to <amanhã>` | Os campos do `TelemetryReport` coerentes com os cenários acima. |
| Troca de dono | ACS A registra offline e sai sem rede; ACS B entra e sincroniza. | Nenhum evento de A sobe com o `actorId` de B, e os de A sobem quando A entra de novo. |

---

## Riscos e mitigação

| # | Risco | Mitigação |
|---|---|---|
| R1 | **Desempenho do sync.** Duas escritas SQLCipher a mais por sync e uma por visita, mais um RPC extra. | O `attempt` é a única escrita aguardada antes do `push`. O `result` e o flush saem depois do resultado e o flush não segura a UI. A Task 15 mede contra a linha de base da Task 0, com teto de +10 % no p95. |
| R2 | **Crescimento da fila offline.** Um aparelho sem rede por semanas acumula eventos. | Teto de 5000 por dono, apagando os mais antigos (≈ semanas de uso: 8 visitas + ~10 syncs por dia). O descarte é silencioso e enviesa a taxa. Fica registrado no `PROGRESS.md`, e o "sinal de descartados" é corte explícito. |
| R3 | **Compatibilidade de versões.** Um app antigo nunca chama `ingest`, e o servidor novo só ganha adições (tabela, endpoint, modelos). Um app novo com servidor antigo recebe erro de método inexistente. | No segundo caso, o uploader trata o erro como falha recuperável e mantém os eventos até o teto. `VisitSyncEntry` e `visits` **não** mudam. Os eventos de app antigo simplesmente não existem, então o relatório precisa de janela posterior ao rollout, o que vai documentado no CLI. |
| R4 | **Privacidade.** Um pseudônimo estável ainda é dado pessoal (LGPD art. 13 §4), e a ligação alerta→visita reidentifica com acesso a `alerts`. | Chave própria fora do banco, retenção de 365 dias, exclusão no atendimento do titular (Task 8), esquema fechado contra contrabando de campo, `location_hash` fora (A1), ingestão sem log de argumento (VAZ-03), revisão do DPO registrada como pendência no `PROGRESS.md`. |
| R5 | **Relógio do aparelho.** `occurredAt` vem do relógio do aparelho. | `clockSkewMs` por lote, corrigido no relatório; evento mais de 5 min à frente do `sentAt` é recusado. Um relógio que muda entre o evento e o envio ainda distorce, e o risco fica aceito e documentado. |
| R6 | **Janela entre commit e emissão no servidor.** Um crash entre os dois perde o `alert_*`. | O TMRAV continua calculável por `alerts.triggeredAt/acknowledgedAt` (`AdminIndicators.tmravSeconds`). Os ids determinísticos permitem uma reemissão futura sem duplicar. |
