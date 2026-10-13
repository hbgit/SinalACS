# Issue #45 — Trilha de auditoria administrativa completa — Plano de Implementação

> **Para executores:** REQUIRED SUB-SKILL: usar superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans, tarefa a tarefa. Os passos usam checkbox (`- [ ]`).
> **Esta etapa produz só o plano. Nenhum código foi alterado e nenhum teste foi executado para escrevê-lo.** Tudo o que está em "Fatos" foi lido no código em 2026-10-13; "Decisões" são propostas que o dono do produto ainda confirma; "Pendências de investigação" são o que só a execução responde.

**Goal:** dar ao backoffice uma trilha de auditoria consultável (filtros, busca, paginação estável), com integridade verificada pelo servidor (nunca pelo app) e exportável para fiscalização com a menor quantidade possível de dado pessoal, a própria exportação ficando na trilha.

**Architecture:** a consulta continua sendo o keyset por `sequence` de `OrmAdminReadStore.auditLogs`, agora com um filtro tipado e validado. A integridade ganha duas camadas calculadas **no servidor** com a mesma `AuditChain` que grava: um *selo por linha* (cada página já volta com `verified`/`invalid`/`unverifiable` por linha) e uma *verificação global sob demanda* em lotes (`admin.verifyAuditChain`). A exportação é um CSV gerado no servidor, com lista fixa de colunas, que só é entregue depois de commitada a transação que grava o evento `export` em `audit_logs` e o detalhe em uma tabela nova `audit_exports`.

**Tech Stack:** Serverpod 3.4.13 (Dart), Postgres (`unsafeQuery` com parâmetros nomeados), Flutter (`apps/admin`), `dart test`, `flutter_test`, emulador Android via `scripts/qa/*`.

**Spec:** `spec/PRD_system.md` (RF17 linha 150; RBAC §4.2.2 linhas 585–593; hash chain linha 631), `spec/lgpd_design.md` (§458 adversário com acesso ao Postgres; LGPD-RT03), `spec/lgpd_data_audit.md`, `spec/ux_accessibility_assessment.md`, issue #45.

## Decisões confirmadas (2026-10-13)

- **D4** — checkpoint de cauda **aprovado**: a Task 7 é obrigatória.
- **D5** — exportação restrita ao papel `admin` **aprovada**; coordenador consulta, não exporta.
- **Entrega do CSV** pela área de transferência **aprovada** (sem pacote novo).
- **Sem filtro por `resourceId` exato na v1** **aprovado** (D10).

## Global Constraints

- Idioma de UI, comentários e docs: português. Identificadores novos seguem o idioma do arquivo vizinho (o módulo de auditoria mistura: tipos em inglês, locais em português).
- `AUDIT_CHAIN_SECRET` só existe em `AppConfig.auditChainSecret` no servidor. **Nunca** em modelo `.spy.yaml`, resposta, log, mensagem de erro ou arquivo exportado.
- Toda operação nova do backoffice usa `AdminScopeResolver.resolve`/`requireAdmin` (papel/escopo) e `AuditTrail.record` — **nunca** `recordSafely` — como as demais (`backend/CLAUDE.md`, "Auditoria fail-closed").
- Mudou `.spy.yaml` ou endpoint → `serverpod generate` e `serverpod create-migration` a partir de `backend/sinalacs_server`; o `sinalacs_client` regenerado é compartilhado com ACS e paciente: só adições, rodar as suítes deles.
- Dado sintético apenas; adulteração de cadeia **só** no banco `sinalacs_e2e`/`sinalacs_test`, nunca no de desenvolvimento.
- Nada de dependência nova sem justificativa. `apps/admin` não tem pacote de arquivo/compartilhamento; o padrão de copiar já existe (`Clipboard.setData`, `apps/admin/lib/app/admin_accounts.dart:816`).
- Commits e PRs sem atribuição de IA, sem `Co-Authored-By` e sem "Generated with Claude Code" (regra do `CLAUDE.md` do repositório).

## Review Focus

As entradas que a issue implica mas que nenhuma tarefa óbvia testaria, mais prováveis primeiro. Cada linha vira teste na tarefa dona (indicada).

1. **Linha filtrada não é linha adjacente.** Com filtro ativo, as linhas da página não têm `sequence` contíguo; o selo não pode compará-las entre si (falso "elo quebrado"). O vizinho vem do banco. → Task 5.
2. **`timestamp` não é monotônico com `sequence`.** `OrmAuditTrail.recordInTransaction` toma `DateTime.now()` *antes* do `pg_advisory_xact_lock`, então uma linha de `sequence` maior pode ter `timestamp` menor. Período é predicado; a ordem é só `sequence`. → Task 3.
3. **Segredo errado parece adulteração em massa.** Quebra já na `sequence` 1 com todas as linhas inválidas é o sintoma de segredo trocado, não de ataque; a tela precisa dizer "falha" sem afirmar "adulteração" e o painel não pode dizer "íntegra". → Task 6.
4. **Remoção das últimas linhas (truncamento de cauda) não é detectada pelo verificador atual.** → Task 7 (decisão D4).
5. **Fórmula em CSV.** Matrícula/`result` começando com `=`, `+`, `-`, `@` vira fórmula no Excel. → Task 9.
6. **Exportar a si mesmo.** O evento `export` não pode entrar no arquivo que ele descreve nem disparar outro evento em cascata. → Task 10.
7. **Coordenador não pode aprender nada de outra UBS pela verificação** (nem a `sequence` quebrada). → Task 6.
8. **Resposta perdida depois do commit.** Evento gravado, arquivo não entregue: aceito (erra para o lado de auditar a mais), mas documentado e testado. → Task 10.

---

## 1. Resumo executivo

A #45 pede quatro entregas sobre `audit_logs`: (RF1/RF2) filtros, busca e paginação; (RF3) verificação da cadeia exposta na interface; (RF4) exportação para fiscalização; (RF5) autorização e minimização de dados em tudo isso.

Situação medida no código: o servidor já escreve a cadeia HMAC corretamente e já tem um verificador, mas **a tela não vê nada disso** — `AuditLogScreen` mostra as 50 linhas mais recentes, sem filtros, sem "carregar mais" (o `nextBeforeSequence` é descartado em `BackendAdminDataSource.fetchAuditLogs`), sem sinal de integridade, e não há exportação. O verificador só roda por CLI e carrega a tabela inteira na memória.

Entrega proposta: 12 tarefas em 6 fases, uma migração (índices + `audit_exports` + `audit_chain_checkpoints`), três métodos novos em `AdminEndpoint` (`auditLogs` ganha parâmetros; `verifyAuditChain`; `exportAuditLogs`), e a tela de auditoria reescrita. Validação ponta a ponta no emulador com adulteração controlada no banco de e2e.

## 2. Diagnóstico do estado atual (fatos confirmados no código)

| Área | Fato | Onde |
|---|---|---|
| Modelo | `audit_logs`: `id, userId, actionType, resourceType, resourceId?, timestamp, ipHash, result, sequence, previousHash, entryHash`. **Sem coluna de detalhe/metadados.** Único índice próprio: `audit_logs_sequence_idx` (único). `timestamp` é `timestamp without time zone`. | `backend/sinalacs_server/lib/src/models/audit_log.spy.yaml`; `migrations/20261012004814823/definition.sql:132-147` |
| Cadeia | `entryHash = HMAC-SHA256(AUDIT_CHAIN_SECRET, sequence ␟ previousHash ␟ userId ␟ actionType ␟ resourceType ␟ resourceId ␟ timestampUTC-ISO8601 ␟ ipHash ␟ result)`, separador U+001F, hex minúsculo; gênese = 64 zeros; comparação em tempo constante. | `lib/src/application/audit/audit_chain.dart` |
| Escrita | `OrmAuditTrail.recordInTransaction`: `pg_advisory_xact_lock(725100823)`, lê a última linha, insere a próxima na mesma transação. `ipHash` = HMAC com chave diária derivada de `AUDIT_CHAIN_SECRET`. `timestamp` é tomado **antes** do lock. | `lib/src/infrastructure/database/orm_audit_trail.dart` |
| Verificação | `AuditChainVerifier.verify()` checa, nesta ordem e parando na primeira falha: `sequence` contígua desde 1; `previousHash` = `entryHash` anterior (gênese na 1ª); HMAC recalculado. Devolve `ok/checked/brokenAtSequence/reason`. | `lib/src/application/audit/audit_chain_verifier.dart` |
| Leitura p/ verificar | `OrmAuditChainReader.readInOrder()` = `AuditLog.db.find(orderBy: sequence)` **sem limite**: a tabela inteira na memória. | `lib/src/infrastructure/database/orm_audit_chain_reader.dart` |
| Exposição | Só o script `bin/audit_chain_check.dart` (exit 0/1). Nenhum endpoint, nenhum teste de integração com Postgres da verificação. Testes unitários: edição, remoção, renumeração, segredo errado. | `backend/sinalacs_server/bin/audit_chain_check.dart`; `test/unit/audit_chain_test.dart:150-275` |
| Endpoint | `admin.auditLogs(accessToken, limit=50, beforeSequence?)` → `AdminAuditPage{items, nextBeforeSequence?}`. | `lib/src/endpoints/admin_endpoint.dart:84-95` |
| Serviço | `AdminReadService.auditLogs`: `resolve` (papel/escopo, `denied` auditado) → valida `limit` 1..100 → **audita `read`/`admin_audit_logs`/`success` com `record` antes** → consulta. | `lib/src/application/admin/admin_read_service.dart:128-145` |
| Store | `OrmAdminReadStore.auditLogs`: SQL direto, `ORDER BY l.sequence DESC`, keyset `sequence < @before`, escopo pelo **autor** (`users.microAreaId` → `micro_areas.ubsId`); `LEFT JOIN` em `users/acs/staff_accounts` para o rótulo. Não seleciona `ipHash/previousHash/entryHash`. | `lib/src/infrastructure/database/orm_admin_read_store.dart:~200-260` |
| Modelo da API | `AdminAuditEntry{id, sequence, userLabel, actionType, resourceType, timestamp, result}`; sem `resourceId`. | `lib/src/models/api/admin_audit_entry.spy.yaml`, `admin_audit_page.spy.yaml` |
| Escopo/RBAC | `AdminScopeResolver`: só `coordinator`/`admin`; admin = sistema; coordenador = UBS de `staff_accounts.ubsId`, sem UBS ⇒ recusa; recusa grava `denied` antes de lançar. PRD: logs de auditoria = Coordenador R (UBS), Administrador R/W. | `lib/src/application/admin/admin_scope.dart`; `spec/PRD_system.md:585-593` |
| Valores em uso | `actionType`: `login`, `read`, `write`. `result` (amostra): `granted`, `success`, `denied`, `denied_territory`, `denied_patient_mismatch`, `created`, `mfa_reset`, `password_reset`, `micro_area_changed`, `lost`, `visit_legacy_sync(_item)`. `resourceType` (amostra): `alert`, `session`, `triage_session`, `patient_directory`, `admin_*`, … | `grep` em `lib/src` (2026-10-13) |
| App | `AuditLogScreen` (`apps/admin/lib/app/app.dart:811-880`): `recordAccess('view','audit_logs')` (no-op no backend real, `backend_admin_data_source.dart:352`) + `fetchAuditLogs()` uma vez; lista de `Card`s; sem estado de filtro. `AdminDataSource.fetchAuditLogs({int limit}) → List<AuditLogEntry>` (sem cursor). Mock: `mock_admin_data_source.dart:310`. | `apps/admin/lib/core/data/admin_data_source.dart` |
| Testes existentes | Unit: `audit_chain_test.dart`, `admin_read_service_test.dart` (fake store/audit, ordem "auditoria antes do dado"). Integração: `admin_endpoint_test.dart` (`withServerpod`), `admin_read_store_test.dart:904-1040` (ordem, keyset, escopo). App: `audit_log_screen_test.dart`, `audit_timestamp_test.dart`, `error_handling_test.dart`, `backend_admin_data_source_test.dart`. | caminhos acima |
| E2E | `scripts/qa/e2e_stack.sh up|seed|psql|down` (banco `sinalacs_e2e`, `psql` com SQL arbitrário), `lib_rele.sh`, `otp_relay.py`, padrão `admin_*_e2e.sh` + `_e2e_test.sh` (confere o texto do script sem Docker) + `apps/admin/integration_test/*_e2e.dart` + `support/e2e_admin.dart`. | `scripts/qa/`, `apps/admin/integration_test/` |
| Limite declarado | O append-only **não** é imposto pelo banco (sem trigger/`REVOKE`): a cadeia *detecta*, não impede. | `PROGRESS.md` ~linha 400 |

**Hipóteses a confirmar na execução (não são fatos):** (H1) quantas linhas `audit_logs` o banco de e2e/dev tem — define se índice novo vale a pena (medir com `EXPLAIN`). (H2) o tempo de `verify()` em lotes para 100 mil linhas sintéticas. (H3) `Clipboard.getData` funciona no `integration_test` do emulador para ler de volta o CSV copiado (se não, o teste lê o retorno do RPC).

## 3. Matriz de lacunas e riscos

| # | Lacuna | Esperado | Arquivos | Mudança | Risco | Teste que prova |
|---|---|---|---|---|---|---|
| G1 | Sem filtros (RF1) | usuário, ação, recurso, período, resultado, combináveis, limpáveis | `admin_endpoint.dart`, `admin_read_service.dart`, `orm_admin_read_store.dart`, `AdminAuditFilter` (novo) | filtro tipado, validação, `WHERE` com `@param IS NULL OR …` | SQL por concatenação; filtro contornar o escopo | Task 3, 4 |
| G2 | Sem "carregar mais" nem total (RF2) | paginação contínua por cursor | `backend_admin_data_source.dart`, `AuditLogScreen` | cursor na interface e no data source | páginas repetidas/puladas se a ordem mudar | Task 3, 8 |
| G3 | Sem busca (RF2) | busca só em campos seguros | store + service | `search` em matrícula, `resourceType`, `result` | `LIKE` com curinga do usuário; busca em hash/IP/UUID | Task 3 |
| G4 | Sem integridade na UI (RF3) | selo por linha + estado global | `audit_chain_verifier.dart`, reader, endpoint, `AdminAuditEntry` | selo no servidor; `verifyAuditChain` | falso positivo por carga parcial; segredo no cliente | Task 5, 6 |
| G5 | Verificador carrega tudo na memória | lotes por `sequence` | `orm_audit_chain_reader.dart` | `readBatch(afterSequence, limit)` | OOM / endpoint lento vira DoS | Task 5 |
| G6 | Truncamento de cauda indetectável | detectar cadeia mais curta que a última conhecida | migração + verificador | checkpoint assinado (D4) | falso alarme se o checkpoint for restaurado de backup | Task 7 |
| G7 | Sem exportação (RF4) | CSV com colunas fixas, limite, autorização, evento auditado | `AuditExportService` (novo), endpoint, `audit_exports` (nova) | Tasks 9–10 | PII, fórmula CSV, evento sem detalhe | Task 9, 10 |
| G8 | `audit_logs` não guarda detalhe do evento | filtros/quantidade/formato do export rastreáveis | migração | tabela `audit_exports` ligada ao evento por `resourceId` | detalhe fora da cadeia (mutável) | Task 2, 10 |
| G9 | Índices | consulta filtrada sem varrer a tabela | migração | `audit_logs_timestamp_idx`, `audit_logs_user_sequence_idx` (se `EXPLAIN` pedir) | custo de escrita sob lock global de apêndice | Task 2 |
| G10 | `AdminDataSource.fetchAuditLogs` devolve lista | devolver página + selo + estado | `admin_data_source.dart`, backend/mock/falho, 5 testes | contrato novo | quebra de testes herméticos | Task 8 |

**Riscos transversais:** (R1) migração em `audit_logs` — só índices (aditivo, não toca coluna da cadeia); `CREATE INDEX` não reescreve linhas, mas toma lock de escrita na tabela durante a criação → aceitável no estágio atual (sem dado real), registrar em `backend/DEPLOY.md` se algum dia houver volume. (R2) O próprio `auditLogs` grava uma linha por chamada (inclusive cada "carregar mais"): ruído crescente, mas é política vigente fail-closed; a tela passa a pedir página nova só por ação do usuário e **não** polla. (R3) `sinalacs_client` compartilhado (ACS/paciente) — só adições. (R4) A verificação global é O(n) HMACs: single-flight por processo + orçamento de tempo + cache curto, senão o botão vira DoS.

## 4. Arquitetura e decisões

### Decisões já determinadas pelo código (não discutir)

- Ordem canônica = `sequence DESC`; paginação = keyset por `sequence` (única, monotônica, não desloca com inserções novas no topo).
- A tela nunca recebe `ipHash`, `previousHash`, `entryHash`, `userId` cru (hoje já é assim).
- Papel/escopo pelo `AdminScopeResolver`; auditoria antes do dado, fail-closed.

### Decisões propostas (confirmar antes da tarefa indicada)

| ID | Proposta | Motivo | Tarefa |
|---|---|---|---|
| D1 | `AdminAuditFilter`: `actorEnrollmentId` (matrícula, igualdade sem caixa), `actorRole` (enum fechado), `actionType` (`read\|write\|login\|export`), `resourceType` (`^[a-z_]{1,64}$`), `result` (`^[a-z_]{1,64}$`), `from`/`to` (UTC, `to` exclusivo, `from < to`, janela ≤ 366 dias), `search` (2–64 chars). Todos opcionais, AND entre eles. Paciente não é filtrável por identificador (só por `actorRole = patient`). | Matrícula é identificação profissional (já exposta na tela); UUID de paciente reidentifica. | 3 |
| D2 | `search` casa **apenas** com: início da matrícula do autor, `resourceType` e `result` (`ILIKE` com `%`/`_`/`\` escapados). Nunca casa `ipHash`, hashes, UUIDs ou nome. Não existe texto livre em `audit_logs`, então não há "busca de texto" a mais. | Minimização; lista de campos fechada e testada. | 3 |
| D3 | Estados de integridade (enum `AuditIntegrityState`): `verified`, `broken`, `unavailable` (banco/tempo/segredo ausente), `inconclusive` (cadeia vazia ou verificação parcial por orçamento de tempo). Selo por linha (enum `AuditRowSeal`): `verified`, `invalid`, `unverifiable` (vizinho anterior ausente). **Só `verified` mostra verde**; qualquer outro nunca. | Critério "falha não é sucesso; indisponível ≠ íntegra". | 5, 6 |
| D4 | **Âncora de cauda:** tabela `audit_chain_checkpoints(id, sequence, entryHash, signature, createdAt)`; cada verificação global `verified` grava `(headSequence, headEntryHash)` e `signature = HMAC(secret, "checkpoint" ␟ sequence ␟ entryHash)`; a próxima verificação falha com `reasonCode = tailTruncated` se a cadeia atual terminar antes do último checkpoint válido ou se `entryHash` naquele `sequence` divergir. **APROVADA (2026-10-13).** | O verificador atual não tem como ver cauda removida. Quem apaga cauda também pode apagar o checkpoint: reduz, não elimina (registrar). | 7 |
| D5 | Exportação: **CSV UTF-8 (RFC 4180, CRLF)**, gerado no servidor, devolvido na resposta do RPC (`AdminAuditExport`) — sem arquivo temporário em disco, sem URL. Teto `AuditExportService.maxRows = 5000`; acima disso o pedido é recusado (`AdminInvalidRequestException`, auditado `result: refused_limit`) e a tela pede para estreitar os filtros. **Só `admin`** exporta; `coordinator` consulta mas não exporta (decisão do dono). | Fiscalização é ato do sistema; PRD dá ao coordenador "R (UBS)", não exportação. Sem pacote novo. | 9 |
| D6 | Colunas exportadas (lista fixa em código, testada por igualdade): `sequence, timestamp_utc, autor, papel_autor, acao, recurso, rotulo_recurso, resultado, selo`. **Fora:** `id`, `userId`, `resourceId` (UUID), `ipHash`, `previousHash`, `entryHash`, qualquer segredo. `rotulo_recurso` = `#`+4 hex (mesmo `AdminLabels.patient`), não o UUID. `autor` = matrícula do staff/ACS ou `Paciente #A18F`. | Finalidade: provar quem/quando/o quê/resultado; o hash completo só serve a quem tem o segredo, que não sai. | 9 |
| D7 | Evento de exportação: linha em `audit_logs` (`actionType: export`, `resourceType: admin_audit_logs`, `resourceId: <exportId>`, `result: success`) **na mesma transação** que insere `audit_exports{id, requestedBy, requestedAt, filtersJson, format, rowCount, firstSequence, lastSequence, contentSha256, chainState}`. Como `audit_logs` não tem coluna de detalhe, o detalhe mora em `audit_exports`; o elo é `resourceId`, que **está** dentro do HMAC. `filtersJson` guarda só os parâmetros do filtro (D1), nunca linhas. | Critério "exportação auditada verificável sem registrar o conteúdo". | 2, 10 |
| D8 | Consistência: (1) autoriza; (2) valida; (3) lê o recorte com `sequence <= headNoInicio` (o evento `export` entra depois ⇒ não se exporta a si mesmo, sem recursão); (4) gera o CSV em memória; (5) transação única: `audit_exports` + `recordInTransaction`; (6) só então devolve o CSV. Se (5) falha, nada sai. Se a resposta se perde depois do commit, fica um evento sem entrega — aceito (erra para auditar a mais) e documentado. Falha em (3)/(4) não grava `success`; grava `result: failed` com `record` (sem conteúdo). | Sem transação distribuída com o cliente. | 10 |
| D9 | Verificação global: **admin** recebe `AdminAuditChainStatus` completo (estado, linhas checadas, `headSequence`, `firstBrokenSequence`, `reasonCode`, `verifiedAt`); **coordenador** recebe estado + `brokenInScope: bool` e **nenhuma** `sequence` fora do escopo dele. `reasonCode` é enum fechado (`hashMismatch`, `linkBroken`, `sequenceGap`, `tailTruncated`, `timeBudget`, `databaseError`, `secretUnavailable`); o texto `reason` livre do verificador atual não vai ao cliente. Single-flight por processo, orçamento 10 s, cache de resultado 60 s. | Coordenador não pode inferir volume/estado de outra UBS; evita DoS. | 6 |
| D10 | `resourceId` não é exposto; o filtro por recurso é por `resourceType`. Filtro por `resourceId` exato fica **fora da v1** (pendência P3). | UUID de recurso pode ser id de paciente. | 3 |

### Contrato (propostas de modelo; nomes finais ao gerar)

`admin.auditLogs(accessToken, AdminAuditFilter? filter, int limit = 50, int? beforeSequence)` → `AdminAuditPage{items, nextBeforeSequence?}`; `AdminAuditEntry` ganha `integrity: AuditRowSeal` e `resourceLabel: String?`.
`admin.verifyAuditChain(accessToken)` → `AdminAuditChainStatus`.
`admin.exportAuditLogs(accessToken, AdminAuditFilter filter)` → `AdminAuditExport{fileName, csv, rowCount, firstSequence, lastSequence, contentSha256, chainState, generatedAt}`.
Parâmetro novo opcional com padrão `null` em `auditLogs` ⇒ clientes antigos continuam funcionando (a resposta ganha campos; Serverpod ignora o que o cliente antigo não conhece — **confirmar na execução com o cliente ACS/paciente regenerado**, P4).

## 5. Fases e tarefas

Dependências: 1 → 2 → 3 → (4, 5) → 6 → 7 → 8 → 9 → 10 → 11 → 12. Cada tarefa termina com `dart analyze`/`flutter analyze` limpo e commit próprio.

### Fase 0 — Linha de base

#### Task 1: Baseline e decisões

**Objetivo:** provar o ponto de partida e fechar D4/D5 antes de migrar.
**Arquivos:** nenhum de código. Criar `docs/superpowers/plans/2026-10-13-issue-45-baseline.log` (padrão do `…issue-42-baseline.log`).
- [ ] Rodar `cd backend/sinalacs_server && dart analyze && dart test` e `cd apps/admin && flutter analyze && flutter test`; salvar contagens reais no log (não copiar os números de `PROGRESS.md`).
- [x] Decisões do dono já recebidas (ver "Decisões confirmadas" no topo); nada a perguntar nesta tarefa.
- [ ] Medir H1: `./scripts/qa/e2e_stack.sh up && ./scripts/qa/e2e_stack.sh psql 'select count(*) from audit_logs'` (e `down`).
**Critério:** log de baseline commitado; D4/D5 respondidas.

### Fase 1 — Esquema

#### Task 2: Migração (índices + `audit_exports` + `audit_chain_checkpoints`)

**Objetivo:** G8, G9 (e D4).
**Arquivos:** criar `backend/sinalacs_server/lib/src/models/audit_export.spy.yaml`, `audit_chain_checkpoint.spy.yaml`; modificar `models/audit_log.spy.yaml` (índices); gerar `lib/src/generated/*`, `migrations/<novo>/`, `sinalacs_client/lib/src/protocol/*`.
**Alterações:** `AuditExport{id, requestedBy: UuidValue (relation users), requestedAt, filtersJson: String, format: String, rowCount: int, firstSequence: int?, lastSequence: int?, contentSha256: String, chainState: String}`; `AuditChainCheckpoint{id, sequence: int, entryHash, signature, createdAt}` com índice único em `sequence`; em `audit_logs`: `audit_logs_timestamp_idx (timestamp)`, `audit_logs_user_sequence_idx (userId, sequence)` — **só se o `EXPLAIN` do passo 3 mostrar varredura**.
- [ ] **Passo 1:** escrever os `.spy.yaml`.
- [ ] **Passo 2:** `cd backend/sinalacs_server && serverpod generate && serverpod create-migration`.
- [ ] **Passo 3:** com 50 mil linhas sintéticas no `sinalacs_e2e` (`generate_series` via `e2e_stack.sh psql`), `EXPLAIN (ANALYZE)` da consulta filtrada por período e por `userId`; manter só os índices que mudam o plano.
- [ ] **Passo 4:** teste de integração (`withServerpod`) que lê o `definition.sql` do `audit_logs` e afirma que as colunas da cadeia não mudaram: `sequence, previousHash, entryHash` presentes e `timestamp` ainda `timestamp without time zone`.
- [ ] **Passo 5:** rodar `dart test test/integration` e a suíte do ACS e do paciente (R3). Commit.
**Critério:** migração aplica em banco vazio e em banco com linhas; nenhuma coluna da cadeia alterada.
**Risco:** `pg_data/` antigo aplica a migração no boot (aditiva; sem perda).

### Fase 2 — Backend: consulta

#### Task 3: Filtro, busca e keyset no store

**Objetivo:** G1–G3, D1, D2, D10, Review Focus 2.
**Arquivos:** criar `lib/src/models/api/admin_audit_filter.spy.yaml` (+ enum `AdminActorRole` se necessário); modificar `lib/src/application/admin/admin_read_service.dart` (`AdminReadStore.auditLogs`, `AdminReadService.auditLogs`), `lib/src/infrastructure/database/orm_admin_read_store.dart`, `lib/src/endpoints/admin_endpoint.dart`; testes `test/unit/admin_read_service_test.dart`, `test/integration/admin_read_store_test.dart`, `test/integration/admin_endpoint_test.dart`.
**Alterações:**
- `AdminReadService`: `_validarFiltro(AdminAuditFilter?)` lança `AdminInvalidRequestException` para: regex de `resourceType/result` violada; `from >= to`; janela > 366 d; `search` fora de 2–64; matrícula > 32; `limit` fora de 1..100 (regra atual). **Valida antes de auditar** (entrada inválida não é acesso).
- `OrmAdminReadStore.auditLogs(scope, filter, limit, beforeSequence)`: acrescentar ao `WHERE` existente, **sempre por parâmetro nomeado**:
```sql
AND (@action::text IS NULL OR l."actionType" = @action::text)
AND (@rtype::text  IS NULL OR l."resourceType" = @rtype::text)
AND (@result::text IS NULL OR l.result = @result::text)
AND (@from::timestamp IS NULL OR l."timestamp" >= @from::timestamp)
AND (@to::timestamp   IS NULL OR l."timestamp" <  @to::timestamp)
AND (@role::text IS NULL OR u.role = @role::text)
AND (@enroll::text IS NULL OR lower(COALESCE(acs."enrollmentId", s."enrollmentId")) = lower(@enroll::text))
AND (@q::text IS NULL OR (
      lower(COALESCE(acs."enrollmentId", s."enrollmentId", '')) LIKE lower(@q::text) || '%' ESCAPE '\'
   OR l."resourceType" LIKE '%' || @q::text || '%' ESCAPE '\'
   OR l.result        LIKE '%' || @q::text || '%' ESCAPE '\'))
```
  `@q` já chega com `\`, `%`, `_` escapados por `_escaparLike(String)` (função pura nova, testada). O `WHERE` de escopo e o `ORDER BY l.sequence DESC LIMIT @limit+1` **não mudam**.
- [ ] **Passo 1 (testes primeiro, store, Postgres real):** fixture com 3 autores (admin, ACS UBS-A, ACS UBS-B), 12 linhas, **duas com o mesmo `timestamp`** e uma com `sequence` maior e `timestamp` menor que a anterior. Casos: cada filtro isolado; todos combinados; `from==to` ⇒ recusa no serviço; fronteira de `to` exclusiva; `search='%'` casa **zero** linhas (curinga escapado); `search` não casa `ipHash`/`entryHash` (inserir linha cujo `resourceType` não contenha o texto e cujo hash contenha-o); filtro de coordenador **nunca** devolve linha de outra UBS mesmo com `actorEnrollmentId` de outra UBS; keyset: página 1 → inserir linha nova no topo → página 2 sem repetir nem pular.
- [ ] **Passo 2:** rodar e ver falhar (`dart test test/integration/admin_read_store_test.dart -n 'auditoria com filtros'`).
- [ ] **Passo 3:** implementar store + `_escaparLike` + serviço + endpoint (parâmetro `AdminAuditFilter? filter`).
- [ ] **Passo 4:** testes unitários do serviço (fake): parâmetro inválido ⇒ `AdminInvalidRequestException` **sem** linha de auditoria; válido ⇒ `audit:admin_audit_logs:success` antes de `store:auditLogs` (padrão `_ordem` já existente).
- [ ] **Passo 5:** teste do endpoint (`admin_endpoint_test.dart`): sem token ⇒ falha de autenticação; `acs` e `patient` ⇒ `AlertPermissionException` + linha `denied`; coordenador sem UBS ⇒ recusa; `serverpod generate`; commit.
**Critério:** testes verdes; `grep -n '\$' orm_admin_read_store.dart` não mostra valor do usuário interpolado no SQL (só fragmentos fixos).

#### Task 4: Regressão de escopo e privacidade da consulta

**Objetivo:** G1 × RF5.
**Arquivos:** `test/integration/admin_endpoint_test.dart`.
- [ ] Teste: resposta serializada (`jsonEncode(page.toJson())`) de uma consulta filtrada **não contém** `ipHash`, `previousHash`, `entryHash`, o nome sintético do paciente, nem nenhum UUID completo de `resourceId`/`userId` (regex `[0-9a-f]{8}-[0-9a-f]{4}-…`).
- [ ] Teste: coordenador A filtrando `actorRole=admin` ⇒ vazio (linhas de staff invisíveis, regra vigente).
- [ ] Commit.
**Critério:** verde.

### Fase 3 — Backend: integridade

#### Task 5: Selo por linha e leitura em lotes

**Objetivo:** G4, G5, Review Focus 1, D3.
**Arquivos:** modificar `lib/src/application/audit/audit_chain_verifier.dart`, `lib/src/infrastructure/database/orm_audit_chain_reader.dart`, `bin/audit_chain_check.dart` (só se a interface mudar), `lib/src/application/admin/admin_read_service.dart`, `lib/src/runtime/alert_runtime.dart:231` (injetar `AuditChain`); criar `lib/src/application/audit/audit_row_sealer.dart`; testes `test/unit/audit_chain_test.dart`, `test/unit/audit_row_sealer_test.dart`, `test/integration/audit_chain_reader_test.dart`.
**Interfaces:**
- Produz: `AuditChainReader.readBatch({required int afterSequence, required int limit}) → Future<List<AuditChainEntry>>` (ordem crescente, `sequence > afterSequence`); `AuditChainReader.entryAt(int sequence) → Future<AuditChainEntry?>`; `AuditChainVerifier.verify({Duration? budget, DateTime Function()? clock}) → Future<AuditChainVerification>` (`AuditChainVerification` ganha `AuditChainReason? reasonCode`; o enum `AuditChainReason` nasce **nesta** tarefa em `lib/src/models/enums/audit_chain_reason.spy.yaml` e a Task 6 só o reutiliza; lotes de 1000; mantém a semântica das 3 checagens; `readInOrder()` removido e o único chamador, o CLI, usa `verify()`); `AuditRowSealer(AuditChain)` com `AuditRowSeal seal(AuditChainEntry row, {required String? previousEntryHash})`.
- Regra do selo: `valid = chain.matches(row.fields, row.entryHash)`; `linkOk = (sequence == 1 ? previousHash == genesis : previousEntryHash != null && previousHash == previousEntryHash)`; `previousEntryHash == null` com `sequence > 1` ⇒ `unverifiable`; `!valid || !linkOk` ⇒ `invalid`; senão `verified`.
- Store de leitura: `auditLogs` devolve, além do que já devolve, os campos de cadeia **internos** (tipo `AuditSealInput`, nunca serializado) e o `entryHash` da linha `sequence-1` por `LEFT JOIN audit_logs p ON p.sequence = l.sequence - 1`.
- [ ] **Passo 1 (testes unitários do selo):** linha íntegra com vizinho certo ⇒ `verified`; conteúdo editado ⇒ `invalid`; `previousHash` editado ⇒ `invalid`; vizinho ausente (`previousEntryHash=null`, `sequence>1`) ⇒ `unverifiable` (**não** `verified`); segredo errado ⇒ `invalid`; `sequence=1` com gênese ⇒ `verified`.
- [ ] **Passo 2 (teste de integração, Review Focus 1):** inserir 6 linhas encadeadas via `OrmAuditTrail`; consultar com filtro que devolve só as linhas 2 e 5 (não adjacentes) ⇒ ambas `verified`. Em seguida `UPDATE audit_logs SET result='x' WHERE sequence=5` direto no banco ⇒ linha 5 `invalid`, linha 2 `verified`, e a linha 6 (cujo `previousHash` aponta para o `entryHash` original de 5, que continua gravado) **continua `verified` pelo selo** — o selo por linha não vê a quebra a jusante; quem vê é a verificação global (Task 6). Documentar esse limite no comentário da classe.
- [ ] **Passo 3 (verificador em lotes):** teste com `AuditChainReader` fake de 2500 entradas ⇒ lê em 3 lotes (contar chamadas) e dá o mesmo resultado que a versão antiga; as quatro adulterações existentes (edição, remoção, renumeração, segredo errado) continuam detectadas; remoção **dentro de um lote** e **na fronteira entre lotes** são detectadas; `budget` esgotado ⇒ resultado `ok:false, reasonCode: timeBudget` (**não** `ok:true`).
- [ ] **Passo 4:** implementar; adaptar o CLI; commit.
**Critério:** `dart test test/unit/audit_chain_test.dart test/unit/audit_row_sealer_test.dart test/integration/audit_chain_reader_test.dart` verde; nenhum `find()` sem limite sobre `audit_logs` em `lib/` (`grep -n "AuditLog.db.find(" lib/` só no insert/última linha).

#### Task 6: `admin.verifyAuditChain`

**Objetivo:** G4, D3, D9, Review Focus 3 e 7.
**Arquivos:** criar `lib/src/models/api/admin_audit_chain_status.spy.yaml` (+ enums `AuditIntegrityState`, `AuditChainReason`), `lib/src/application/admin/audit_chain_status_service.dart`; modificar `admin_endpoint.dart`, `alert_runtime.dart`; testes `test/unit/audit_chain_status_service_test.dart`, `test/integration/admin_endpoint_audit_chain_test.dart`.
**Interfaces:** `AuditChainStatusService.verify(AuthenticatedUser user) → Future<AdminAuditChainStatus>`; `AdminAuditChainStatus{state, checkedRows, headSequence?, firstBrokenSequence?, brokenInScope?, reasonCode?, verifiedAt}`.
**Alterações:** `resolve(..., recurso: 'admin_audit_chain')`; audita `read`/`admin_audit_chain`/`success` **antes** de verificar (`record`); single-flight por processo (um `Future` em andamento é compartilhado) e cache 60 s (relógio injetável); exceção do reader ⇒ `unavailable/databaseError`; `AppConfig.auditChainSecret` vazio ⇒ `unavailable/secretUnavailable` (nunca `verified`); cadeia vazia ⇒ `inconclusive` (nada a atestar). Para o coordenador: `firstBrokenSequence` só preenchido se a linha quebrada pertencer ao escopo dele (consulta de pertencimento), senão `null` e `brokenInScope=false`; **estado `broken` continua sendo mostrado** (o painel não pode dizer íntegra).
- [ ] **Passo 1 (unit, fakes):** íntegra ⇒ `verified`; cada uma das 4 adulterações ⇒ `broken` com `reasonCode` esperado e `firstBrokenSequence` correto; reader lança ⇒ `unavailable`; segredo vazio ⇒ `unavailable`; orçamento esgotado ⇒ `inconclusive/timeBudget`; **teste de propriedade negativa:** para todo resultado diferente de `verified`, `state != verified` (parametrizado sobre todos os `reasonCode`); duas chamadas concorrentes ⇒ um só `readBatch` inicial (single-flight); segunda chamada em 60 s ⇒ não relê.
- [ ] **Passo 2 (integração, Postgres real, endpoint com token real):** admin ⇒ `verified` sobre cadeia gravada por `OrmAuditTrail`; `UPDATE` direto do `result` de uma linha ⇒ `broken` com `firstBrokenSequence` igual à linha alterada; `DELETE` de uma linha do meio ⇒ `broken/sequenceGap`; coordenador com linha quebrada de outra UBS ⇒ `broken`, `brokenInScope=false`, `firstBrokenSequence=null`; `acs`/`patient` ⇒ `AlertPermissionException` + `denied`; sem token ⇒ falha. Serializar a resposta e afirmar que **não contém** a string do segredo (`AppConfig.developmentAuditChainSecret`) nem `entryHash`.
- [ ] **Passo 3:** implementar, `serverpod generate`, commit.
**Critério:** verde; resposta nunca contém segredo/hash.
**Risco:** tempo de `verify` em volume real (H2) — registrar a medição; o orçamento 10 s é parâmetro.

#### Task 7: Checkpoint de cauda (D4 — aprovada)

**Objetivo:** G6, Review Focus 4.
**Arquivos:** `audit_chain_status_service.dart`, `audit_chain_verifier.dart`, store de checkpoint (`lib/src/infrastructure/database/orm_audit_checkpoint_store.dart`, novo); testes unit + integração.
- [ ] Teste (integração): verificação `verified` grava checkpoint; apagar as 3 últimas linhas por `DELETE` ⇒ próxima verificação ⇒ `broken/tailTruncated`; sem apagar, nova linha por cima ⇒ `verified` e checkpoint avança; checkpoint com `signature` inválida é ignorado **e sinalizado** (`inconclusive`), não aceito.
- [ ] Teste: restaurar o banco inteiro de um backup mais antigo (cadeia e checkpoints antigos) ⇒ `verified` (limite conhecido, documentado em Pendências).
- [ ] Implementar; commit.
**Critério:** verde.

### Fase 4 — Cliente

#### Task 8: Contrato do `AdminDataSource` e telas de consulta

**Objetivo:** G2, G10, RF1/RF2/RF3 na tela.
**Arquivos:** `apps/admin/lib/core/data/admin_data_source.dart`, `backend_admin_data_source.dart`, `mock_admin_data_source.dart`, `apps/admin/test/support/failing_admin_data_source.dart`, `apps/admin/lib/app/app.dart` (extrair `AuditLogScreen` para `apps/admin/lib/app/audit_log_screen.dart`, que já passa de 100 linhas e ganha estado próprio), testes `audit_log_screen_test.dart`, `audit_timestamp_test.dart`, `error_handling_test.dart`, `backend_admin_data_source_test.dart`, `mock_admin_data_source_test.dart`.
**Interfaces (Produz):**
```dart
enum AuditRowSeal { verified, invalid, unverifiable }
enum AuditIntegrityState { verified, broken, unavailable, inconclusive }
class AuditLogFilter { /* campos de D1, const, copyWith, isEmpty */ }
class AuditLogPage { final List<AuditLogEntry> items; final int? nextBeforeSequence; }
class ChainStatus { final AuditIntegrityState state; final int? checkedRows; final int? firstBrokenSequence; final bool brokenInScope; final DateTime verifiedAt; }
// AuditLogEntry ganha: int sequence; AuditRowSeal seal; String? resourceLabel;
Future<AuditLogPage> fetchAuditLogs({AuditLogFilter filter = const AuditLogFilter(), int limit = 50, int? beforeSequence});
Future<ChainStatus> verifyAuditChain();
```
- [ ] **Passo 1 (testes de widget primeiro):** (a) lista com 3 selos: `verified` mostra ícone + rótulo "Íntegro", `invalid` mostra "Adulterado?" em `danger*OnSurface` com ícone distinto e `Semantics`, `unverifiable` mostra "Não verificável" — **sem depender só de cor** (WCAG; usar tokens `*OnSurface` e medir contra `Card`, `contrast_tokens_test.dart`); (b) painel de estado: um teste por `AuditIntegrityState`, afirmando que **só** `verified` renderiza "Cadeia íntegra" e que `unavailable`/`inconclusive` renderizam texto distinto e nunca o de sucesso; (c) filtros: aplicar, combinar, "Limpar", e que mudar o filtro zera o cursor; (d) "Carregar mais" usa o `nextBeforeSequence` e não duplica itens; (e) vazio, carregando, erro com "Tentar novamente"; (f) `AdminSessionExpired` leva ao login (padrão de `error_handling_test.dart`); (g) layout estreito sem overflow e escala de texto (`responsive_layout_test.dart`, `text_scale_test.dart`, `touch_targets_test.dart` — alvos ≥ 48 dp nos botões novos).
- [ ] **Passo 2:** implementar interface, backend (`_guard`), mock (gera selos/estados configuráveis para os testes), falho; migrar os testes existentes ao contrato novo.
- [ ] **Passo 3:** `flutter analyze && flutter test`; commit.
**Critério:** verde; nenhuma tela decide integridade (só mostra o que o servidor devolveu — teste: mock devolve `verified` para uma linha com conteúdo "estranho", a tela não recalcula).

### Fase 5 — Exportação

#### Task 9: Gerador do CSV (puro)

**Objetivo:** G7, D5, D6, Review Focus 5.
**Arquivos:** criar `lib/src/application/audit/audit_csv.dart`; teste `test/unit/audit_csv_test.dart`.
**Interfaces:** `abstract final class AuditCsv { static const columns = ['sequence','timestamp_utc','autor','papel_autor','acao','recurso','rotulo_recurso','resultado','selo']; static String build(List<AuditExportRow> rows); }`, `AuditExportRow` com exatamente esses campos (tipo próprio — o gerador **não recebe** `AuditLog`/`AuditChainEntry`, então não tem como vazar `ipHash`/hash).
- [ ] **Teste de lista fechada:** `expect(AuditCsv.columns, [... as nove ...])` (igualdade exata) e `expect(AuditExportRow` tem exatamente nove campos via construtor nomeado (o teste quebra se alguém adicionar campo).
- [ ] **Testes de formato:** cabeçalho + CRLF; aspas duplas escapadas; vírgula e quebra de linha dentro do campo; `timestamp_utc` em ISO-8601 com `Z`; vazio ⇒ só o cabeçalho.
- [ ] **Teste de injeção de fórmula:** `autor` = `=HYPERLINK("x")`, `+1`, `-1`, `@a` ⇒ célula prefixada com `'`.
- [ ] **Teste de PII:** gerar de uma fixture cujos campos de origem contêm um UUID, um hash de 64 hex, um "IP" e o nome sintético do paciente **fora** das colunas permitidas ⇒ o CSV não contém nenhum dos quatro (regex).
- [ ] Implementar; commit.
**Critério:** verde.

#### Task 10: `admin.exportAuditLogs`

**Objetivo:** G7/G8, D5, D7, D8, Review Focus 6 e 8.
**Arquivos:** criar `lib/src/application/admin/audit_export_service.dart`, `lib/src/models/api/admin_audit_export.spy.yaml`; modificar `admin_endpoint.dart`, `alert_runtime.dart`, store; testes `test/unit/audit_export_service_test.dart`, `test/integration/admin_endpoint_audit_export_test.dart`.
**Interfaces:** `AuditExportService.export(AuthenticatedUser user, AdminAuditFilter filter) → Future<AdminAuditExport>`; `maxRows = 5000`.
**Procedimento (ordem fixa, igual à D8):** `requireAdmin(..., recurso: 'admin_audit_export', actionType: 'export')` (recusa `denied` auditada) → `_validarFiltro` (o mesmo da Task 3; **filtro obrigatório com `from`/`to`**) → `headSequence` → `COUNT` do recorte; `> maxRows` ⇒ `record(result: 'refused_limit')` + `AdminInvalidRequestException` → ler linhas `sequence <= head` e selos (Task 5) → `AuditCsv.build` → SHA-256 do CSV → **uma transação**: `INSERT audit_exports` + `OrmAuditTrail.recordInTransaction(AuditEvent(actionType:'export', resourceType:'admin_audit_logs', resourceId: exportId, result:'success'))` → devolver. Falha de leitura/geração ⇒ `record(result:'failed')` fora de transação e relança uma exceção genérica (mensagem fixa; sem texto do banco).
- [ ] **Passo 1 (unit, fakes):** `acs`/`patient`/`coordinator` ⇒ `AlertPermissionException` + `denied`, **nenhuma** linha lida (contar chamadas ao store); filtro sem período ⇒ `AdminInvalidRequestException` sem auditoria; recorte > `maxRows` ⇒ `refused_limit` e nada gerado; ordem registrada: `audit:denied` / `store:count` / `store:read` / `tx:export+audit` / retorno; falha da gravação da auditoria dentro da transação ⇒ **nenhum CSV devolvido** e nenhuma linha em `audit_exports` (fake transacional).
- [ ] **Passo 2 (integração, Postgres real):** admin exporta recorte conhecido ⇒ `rowCount`, `firstSequence`, `lastSequence`, `contentSha256 == sha256(csv)`; **o CSV não contém a linha do próprio `export`** (a `sequence` do evento é `> lastSequence`); existe exatamente uma linha `export` nova em `audit_logs` com `resourceId == exportId` e uma em `audit_exports` com o mesmo `id`; `filtersJson` não contém linha nenhuma; a cadeia continua `verified` depois (usar o verificador da Task 5); exportar duas vezes seguidas grava exatamente +1 linha `export` por chamada (sem linha extra em cascata; o segundo CSV contém a linha `export` do primeiro, o que é esperado); log do processo capturado durante o teste não contém trecho do CSV (capturar `stderr`/`stdout`, `expect(isNot(contains(autorSintético)))`).
- [ ] **Passo 3:** teste da resposta perdida: simular exceção depois do commit (envolver a chamada) ⇒ evento existe, nada a desfazer; assert documentado.
- [ ] Implementar, `serverpod generate`, commit.
**Critério:** verde; `grep -rn "entryHash\|ipHash" lib/src/application/admin/audit_export_service.dart` vazio.

#### Task 11: UI de exportação

**Objetivo:** RF4 na tela.
**Arquivos:** `audit_log_screen.dart`, `admin_data_source.dart` (`Future<AuditExportResult> exportAuditLogs(AuditLogFilter)`), backend/mock/falho, `admin_accounts.dart` (reaproveitar o padrão do botão copiar), testes.
- [ ] Testes de widget: botão "Exportar" visível **só para admin** (`StaffSummary.role`/sessão; o servidor continua sendo a autoridade); exige período preenchido; confirmação antes de exportar ("Será registrado na trilha"); sucesso mostra `rowCount`, intervalo de `sequence`, SHA-256 e botão "Copiar CSV" (`Clipboard.setData`); `AdminInvalidRequestException` do teto ⇒ texto fixo "Há registros demais; estreite o período."; recusa de permissão ⇒ texto fixo sem motivo; erro de rede ⇒ "Tentar novamente"; toque duplo não gera duas exportações (botão desabilita enquanto em curso — teste conta chamadas no fake).
- [ ] Implementar; `flutter test`; commit.
**Critério:** verde; o CSV nunca é gravado em `localStorage`/disco (revisão de código + `grep -n "File(\|localStorage" lib/app/audit_log_screen.dart` vazio).
**Observação:** entrega por área de transferência é decisão de escopo (sem pacote novo). Download de arquivo real fica como pendência P5.

### Fase 6 — Validação final

#### Task 12: E2E no emulador, regressão e documentação

**Objetivo:** critério "Validação E2E" e fechamento.
**Arquivos:** criar `scripts/qa/admin_auditoria_e2e.sh`, `scripts/qa/admin_auditoria_e2e_test.sh`, `apps/admin/integration_test/admin_auditoria_e2e.dart`; modificar `backend/sinalacs_server/bin/seed_e2e_fixtures.dart` (opt-in `E2E_SEED_AUDIT_TRAIL=1`, como `E2E_SEED_ALERT_ESCALATION`), `backend/CLAUDE.md`, `apps/CLAUDE.md`, `PROGRESS.md`, `CLAUDE.md` (parágrafo "Still missing"), `spec/PRD_system.md` (RF17), `spec/lgpd_design.md`.
- [ ] Seed: 40 linhas de auditoria via `OrmAuditTrail` (autores: admin, coordenador, ACS; ações e resultados variados; **duas com mesmo `timestamp`**) para forçar 2 páginas e filtros.
- [ ] `admin_auditoria_e2e.dart`, linhas marcadoras para o script (padrão `E2E_*` da #44): (1) login admin (`e2e_admin.dart`); (2) Auditoria: painel mostra "Cadeia íntegra" após "Verificar"; filtros por ação, período e busca; "Carregar mais" sem repetição; (3) imprime `E2E_ADULTERAR sequence=<n>`; o **script** aplica `./scripts/qa/e2e_stack.sh psql "update audit_logs set result='x' where sequence=<n>"` e responde; (4) o teste verifica de novo: estado "Falha de integridade", linha `<n>` marcada, nenhuma outra `invalid`; (5) exportação: com período, mostra contagem, copia e **lê de volta** `Clipboard.getData` (H3; senão compara com o retorno do RPC chamado direto) e afirma as nove colunas, ausência de hash/UUID/IP; (6) imprime `E2E_EXPORT_FEITO`; (7) login do coordenador (fixture como no `admin_acs_gestao_e2e.sh`): vê a lista escopada, **não vê** "Exportar", e um `exportAuditLogs` via RPC direto é recusado com `denied`; (8) `E2E_FIM`.
- [ ] O script, depois do teste, confere **no banco**: exatamente uma linha `export`/`success` com `resourceId` presente em `audit_exports`; uma linha `denied` do coordenador; `audit_exports.filtersJson` sem linhas; o verificador CLI contra o banco de e2e **falha** (cadeia adulterada de propósito) e, após `update` de volta, passa (`dart run bin/audit_chain_check.dart`, exit code conferido); o banco e o manifesto são apagados ao final (`cleanup` igual aos `admin_*_e2e.sh`).
- [ ] `admin_auditoria_e2e_test.sh`: confere o texto do script (DEVICE/`emulator-5554`, `adb reverse`, `e2e_stack.sh down`, `rm -f .e2e/fixtures.json`, linhas marcadoras casadas teste↔script, adulteração só no banco de e2e — `! grep -q 'docker compose.*sinalacs-postgres[^-]'`).
- [ ] Rodar a regressão: `cd backend/sinalacs_server && dart analyze && dart test`; `cd apps/admin && flutter analyze && flutter test`; `cd apps/acs && flutter test`; `cd apps/patient && flutter test`; `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh`; o `_e2e_test.sh` novo. Salvar saídas e a contagem real em `docs/superpowers/plans/2026-10-13-issue-45-e2e.log`.
- [ ] Documentar: `backend/CLAUDE.md` (contratos, D1–D10, limites), `apps/CLAUDE.md` (tela), `PROGRESS.md` (seção #45 com **o que foi provado e o que não**), corrigir o RF17 da `spec/validation_report.md` só no que for verificado.
**Critério:** log de e2e commitado com as linhas marcadoras e o resultado do CLI; nada marcado como feito sem saída anexada.

## 6. Estratégia de testes (resumo)

| Camada | O que | Onde |
|---|---|---|
| Unit (sem banco) | selo por linha; verificador em lotes e orçamento; serviço de status (estados, single-flight, cache); gerador de CSV (lista fechada, fórmula, PII); serviço de export com fakes transacionais; validação de filtro; `_escaparLike` | `backend/sinalacs_server/test/unit/` |
| Integração (Postgres real, `withServerpod`) | filtros/keyset/escopo; adulteração real por `UPDATE`/`DELETE` no banco de teste; export + evento na mesma transação; cadeia íntegra depois do export; resposta sem segredo/hash/UUID | `test/integration/` |
| Segurança | `acs`/`patient`/coordenador sem UBS/coordenador em export ⇒ `denied` + nenhuma leitura; sem token; filtro de coordenador não vaza UBS alheia; SQL sem interpolação | idem |
| App (widget) | um teste por estado de integridade; só `verified` é verde; filtros/limpar/cursor; erros; a11y (contraste `*OnSurface`, alvos 48 dp, escala de texto, largura estreita) | `apps/admin/test/` |
| E2E emulador | Task 12 | `scripts/qa/admin_auditoria_e2e.sh` |
| Regressão | suítes completas de backend, admin, ACS, paciente; `ci_invariants*` | Task 12 |

Casos-limite obrigatórios: período invertido/vazio/fronteira (`to` exclusivo); página 1/intermediária/última; mesmo `timestamp`; `timestamp` fora de ordem em relação a `sequence`; banco vazio; parâmetro inválido; linha nova entre páginas; segredo ausente/errado; vizinho ausente; falha de banco; recorte acima do teto; exportação vazia; falha ao gravar a auditoria; fórmula em CSV.

## 7. Procedimento de execução no emulador (comandos reais do repositório)

Pré-requisitos: `./scripts/dev/bootstrap_env.sh` (já feito se `.env` existe); emulador em `emulator-5554` (`adb devices`); `~/flutter/bin` e `~/Android/Sdk/platform-tools` no PATH (os scripts já exportam).

```bash
# 1. Stack de e2e (banco sinalacs_e2e, sem login de desenvolvimento) — substitui a stack de dev
./scripts/qa/e2e_stack.sh up
E2E_SEED_AUDIT_TRAIL=1 ./scripts/qa/e2e_stack.sh seed        # fixtures sintéticas + 40 linhas de auditoria (Task 12)
./scripts/dev/sync_dev_ca.sh                                  # CA do RPC para o app
adb -s emulator-5554 reverse tcp:8443 tcp:443
adb -s emulator-5554 reverse tcp:8765 tcp:8765

# 2. Tudo junto (preferido) — sobe, semeia, roda o teste no emulador, adultera/restaura no banco de e2e e confere:
./scripts/qa/admin_auditoria_e2e.sh                           # DEVICE=<serial> para outro aparelho

# 3. Conferências manuais no banco de teste
./scripts/qa/e2e_stack.sh psql "select sequence, \"actionType\", \"resourceType\", result from audit_logs order by sequence desc limit 5"
( cd backend/sinalacs_server && SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 \
  SERVERPOD_DATABASE_NAME=sinalacs_e2e SERVERPOD_DATABASE_USER=postgres \
  SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" dart run bin/audit_chain_check.dart ; echo "exit=$?" )

# 4. Encerrar e voltar à stack de desenvolvimento
./scripts/qa/e2e_stack.sh down && docker compose up -d
```
`TEST_DATABASE_PASSWORD` vem do `.env` (`set -a; source .env; set +a`). O passo 2 já faz `cleanup` (apaga `.e2e/fixtures.json` e o banco). **O script novo ainda não existe**; os demais comandos são os existentes. Se algum parâmetro de conexão do passo 3 divergir do `e2e_stack.sh seed`, copiar de lá (linhas 48–53).

## 8. Matriz de rastreabilidade

| Requisito / critério | Componentes | Teste de validação | Evidência esperada (a produzir; nada passou ainda) |
|---|---|---|---|
| RF1 filtros combináveis | `AdminAuditFilter`, `OrmAdminReadStore.auditLogs`, `AuditLogScreen` | Task 3 (store), Task 8 (widget), Task 12 (emulador) | saída de `dart test … 'auditoria com filtros'`; linha `E2E_FILTROS_OK` |
| RF2 paginação/busca/ordem estável | keyset por `sequence`, `_escaparLike`, "Carregar mais" | Task 3 (empate de `timestamp`, inserção entre páginas, `search='%'`), Task 8 | idem |
| **Consulta funcional** | tudo acima | Task 3 + 8 + 12 | log do e2e |
| RF3 / **Adulteração detectável** | `AuditRowSealer`, `AuditChainVerifier` em lotes, `AuditChainStatusService`, UI de selos | Task 5 (unit+integração), Task 6 (UPDATE/DELETE reais), Task 12 passo 3–4 | `E2E_ADULTERAR` seguido de "Falha de integridade" na tela e `audit_chain_check` com `exit=1` |
| **Verificação confiável** | enum de estados, teste negativo parametrizado, widget por estado | Task 6 passo 1, Task 8 (b) | testes verdes; nenhum estado ≠ `verified` com texto de sucesso |
| Truncamento de cauda | `audit_chain_checkpoints` | Task 7 | teste `tailTruncated` verde (ou risco registrado se D4 rejeitada) |
| RF4 / **Exportação com minimização de PII** | `AuditCsv`, `AuditExportService` | Task 9 (lista fechada + PII + fórmula), Task 10 | `AuditCsv.columns` igual às nove; CSV do e2e inspecionado |
| **Exportação auditada** | `audit_exports` + evento `export` na mesma transação | Task 10 passos 2–3, Task 12 (confere no banco) | 1 linha `export`, 1 `audit_exports`, cadeia `verified` depois |
| RF5 / **Segurança** | `AdminScopeResolver`, `requireAdmin`, validação | Task 3 passo 5, Task 4, 6, 10, Task 12 passo 7 | `denied` na trilha; coordenador sem "Exportar" e RPC direto recusado |
| Segredo nunca sai | serialização das respostas | Task 4, 6, 10 (regex/contém) | testes verdes |
| **Validação E2E** | `admin_auditoria_e2e.sh/.dart` | Task 12 | `docs/superpowers/plans/2026-10-13-issue-45-e2e.log` |

## 9. Checklist final de segurança, LGPD e regressão

- [ ] `AUDIT_CHAIN_SECRET`: ausente de `.spy.yaml`, respostas, CSV, logs e mensagens (`grep -rn "auditChainSecret" lib/src/models lib/src/endpoints` vazio; testes de serialização verdes).
- [ ] Nenhuma coluna da cadeia alterada; `OrmAuditTrail` intocado salvo `recordInTransaction` sendo reutilizado.
- [ ] Toda operação nova: papel → escopo → validação → auditoria (`record`) → dado.
- [ ] SQL só com parâmetros nomeados; curingas de `LIKE` escapados.
- [ ] CSV: lista fechada de nove colunas por teste de igualdade; sem `userId`/`resourceId`/IP/hash; proteção contra fórmula; teto de linhas; período obrigatório.
- [ ] Evento de export não contém conteúdo; `audit_exports` guarda filtros e `contentSha256`, nunca linhas; logs do processo sem conteúdo.
- [ ] Coordenador não aprende `sequence`/volume de outra UBS pela verificação; não exporta.
- [ ] Tela: só mostra o que o servidor diz; cor nunca é o único sinal; tokens `*OnSurface`; alvos 48 dp.
- [ ] Dado sintético; adulteração só em `sinalacs_e2e`/`sinalacs_test`; banco e manifesto apagados no fim.
- [ ] Suítes completas verdes (backend, admin, ACS, paciente) e `ci_invariants*`, com saídas anexadas.
- [ ] `sinalacs_client` regenerado só com adições; ACS e paciente compilam e testam.

## 10. Pendências, riscos residuais e definição de conclusão

**Pendências de decisão/investigação**
- P1–P3 e a entrega por área de transferência: decididos em 2026-10-13 (ver topo). Resta apenas validar D5 e o filtro por `resourceId` com o encarregado de dados (DPO), sem bloquear a implementação.
- P4 Compatibilidade de cliente antigo: comprovar com ACS/paciente regenerados (campos novos na resposta).
- P5 Download de arquivo real: fora da v1 por decisão; reavaliar só com pacote aprovado em `spec/stack.md`.
- H1–H3 da seção 2 (volume, tempo de verificação, `Clipboard` no teste).

**Riscos residuais a documentar, mesmo com tudo pronto**
1. Quem tem escrita no Postgres **e** o segredo reescreve a cadeia inteira; a cadeia detecta, não impede (`REVOKE`/trigger append-only continua fora de escopo, já registrado em `PROGRESS.md`).
2. Sem versão de chave na linha, **rotacionar `AUDIT_CHAIN_SECRET` invalida toda a história** (parece adulteração em massa); a tela diz "falha", não "ataque". Rotação exigiria `keyVersion` (migração futura).
3. `audit_exports` (detalhe) fica fora da cadeia; só o `resourceId` do evento a liga. Edição direta dela não é detectada pelo verificador.
4. Restaurar backup antigo inteiro (cadeia + checkpoints) passa como íntegro.
5. Entrega do CSV por área de transferência; resposta perdida pós-commit deixa evento sem entrega.
6. Verificação global é O(n); acima de algumas centenas de milhares de linhas precisa de verificação incremental por checkpoint.

**Definição objetiva de conclusão da #45** — todas verdadeiras, com saída anexada:
1. Tasks 1–12 concluídas (incluindo a Task 7).
2. Os testes da seção 6 existem, falharam antes e passam agora (log de baseline vs. final).
3. `admin_auditoria_e2e.sh` termina com sucesso no emulador: adulteração detectada na tela e pelo CLI, export inspecionado, evento de export no banco, coordenador recusado.
4. Checklist da seção 9 inteiro marcado, e `PROGRESS.md`/`CLAUDE.md`/`backend/CLAUDE.md`/`apps/CLAUDE.md` atualizados com o que foi provado **e** o que não foi.
5. Nenhum item de "Fatos" contradito pela execução (se for, corrigir este plano antes de seguir).
