# Plano de Ação LGPD — Branch develop

> **Status: implementado (2026-10-08)** — os blocos 1-4 foram aplicados e validados; ver o checklist no fim deste documento.

Este documento serve como referência para implementação das correções de conformidade LGPD identificadas na auditoria da branch `develop`. Deve ser consumido por um modelo em modo **build** para executar as modificações.

---

## Resumo Executivo

| Categoria | Total | Conforme | Não Conforme |
|-----------|-------|----------|--------------|
| Criptografia de campos sensíveis | 4 | 4 | 0 |
| Hashing seguro | 3 | 3 | 0 (a pendência de `consent_logs` era falso-positivo: marcadores, não hash) |
| Logs sanitizados | 5 | 5 | 0 (inclui o `server.dart`, omitido do relatório original) |
| Retenção/expurgo | 1 | 1 | 0 |
| Tipagem de dados | 1 | 0 | 1 (limitação do framework) |
| Dados sintéticos em dev | 1 | 1 | 0 |
| **Total** | **15** | **14** | **1** |

**Status geral:** conforme — resta 1 pendência **não acionável** (`users.birthDate`, limitação do Serverpod 3.4.13).

---

## Pendências Críticas (Prioridade Alta)

### 1. emergencyContact em texto claro (patients.emergencyContact)

**Arquivo .spy.yaml a modificar:**
- `backend/sinalacs_server/lib/src/models/patient.spy.yaml` (linha 13)

**Mudança:**
```yaml
# ANTES:
emergencyContact: String

# DEPOIS:
emergencyContactEncrypted: String, default=''
emergencyContactKeyVersion: int, default=1
```

**Arquivos .dart a modificar:**

1. `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_directory_store.dart`
   - Criptografar `emergencyContact` antes do INSERT/UPDATE (mesmo padrão de `chronicConditions` em `updateChronicConditions`)
   - Usar `HealthDataCipher.encryptJson()` / `decryptJson()`

2. `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_data_overview_store.dart`
   - Decriptografar `emergencyContact` na leitura (`loadFor`)

**Arquivos a regenerar (após `serverpod generate`):**
- `backend/sinalacs_server/lib/src/generated/patient.dart`
- `backend/sinalacs_client/lib/src/protocol/patient.dart`

**Estado (2026-10-07): aplicado.** Migração `20261007153048060` (DROP da coluna em texto claro + par `emergencyContactEncrypted`/`emergencyContactKeyVersion`, AES-256-GCM, `encryptJson`/`decryptJson` — uniformidade com `chronicConditions`).

**Correção de escopo (verificado no código):** `orm_patient_directory_store.dart` **não precisou mudar** — não existe caminho de escrita de `emergencyContact` em produção (pacientes só são criados por seeds/testes). O único arquivo de produção alterado foi o store de **leitura** (`orm_patient_data_overview_store.dart`, painel "Meus Dados"). Seeds e fixtures atualizados: `development.sql`, `bin/seed_health_data.dart`, `bin/seed_e2e_fixtures.dart`, `test/support/health_data_fixtures.dart`.

---

### 2. ipHash sem salt reversível (audit_logs.ipHash)

**Arquivo modificado:**
- `backend/sinalacs_server/lib/src/infrastructure/database/orm_audit_trail.dart`

**Arquivo criado:**
- `backend/sinalacs_server/lib/src/infrastructure/crypto/rotating_ip_hasher.dart`
- `backend/sinalacs_server/test/unit/rotating_ip_hasher_test.dart`

**Estado anterior:**
```dart
final ipHash = sha256.convert(remoteInfo.codeUnits).toString();
```

**Implementação aplicada:**
- `RotatingIpHasher`: HMAC-SHA-256 com chave rotativa **diária** (UTC), derivada de `AUDIT_CHAIN_SECRET` com separação de domínio `sinalacs:ip:v1:<YYYY-MM-DD>` (mesmo padrão de `sinalacs:cpf:v1:`/`sinalacs:otp:v1:` do `HmacCpfHasher`). Sem segredo novo de config.
- Correlação de incidentes preservada dentro do dia UTC; o rastro de rede do titular não persiste além da janela de rotação.

**Correção factual (verificado no código):** `consent_logs.ipHash` **não** passa pelo `OrmAuditTrail` — as linhas de consentimento gravam marcadores explícitos de ausência (`nao-aplicavel-onboarding` / `nao-aplicavel-painel-titular`) via `signedConsentLog()`, nunca hash de IP. Portanto a pendência de `consent_logs.ipHash` já estava mitigada por design; o único caminho que hasheava IP de verdade era o `OrmAuditTrail` (audit_logs), agora corrigido.

---

### 3. Logs de exceção vazando dados sensíveis (VAZ-01) — aplicado

**Arquivos sanitizados (5):**

| Arquivo | Pontos | Mudança |
|---------|--------|---------|
| `lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart` | 43, 111, 140 | `$error`/`$stackTrace` brutos removidos; log só `alertId` + `error.runtimeType` |
| `lib/src/application/alerts/alert_outbox_dispatcher.dart` | 69 | Idem; log só `alertId` + tentativa + `error.runtimeType` |
| `lib/src/application/triage/triage_session_service.dart` | 162 | Idem; log só `patientId` (UUID) + `error.runtimeType` |
| `lib/src/application/audit/audit_trail.dart` | 58 | Idem; log só `actionType`/`resourceType` + `error.runtimeType` |
| `lib/server.dart` | 96 | Varredura do outbox: idem (esta ocorrência constava da auditoria §3.1 e faltava no plano original) |

**Padrão aplicado:**
```dart
// ANTES:
stderr.writeln('Falha ao processar ACK do alerta ${ack.alertId}: $error\n$stackTrace');

// DEPOIS:
stderr.writeln('Falha ao processar ACK do alerta ${ack.alertId} (${error.runtimeType}).');
```

**Regra:** nunca serializar objetos de domínio (`AlertDelivery`, `AlertOutboxEntry`, `TriageSessionRecord`, etc.) em logs de erro.

**Decisão registrada:** o `lastError` do outbox (`OrmAlertOutbox.markFailed`) continua gravando `error.toString()` no banco — é metadado operacional protegido (não aggregator de log) e os erros do caminho `publish` são mensagens fixas limitadas (`MqttUnavailableException`). Se um dia um publisher lançar exceções com payload embutido, sanitizar esse ponto também.

---

### 4. Ausência de rotina de expurgo (LGPD-RF07) — aplicado

**Decisões em vigor (2026-10-07):**

- **B1 — DELETE físico.** O requisito aceita "anonimizados **ou eliminados** de forma segura" (`lgpd_design.md` §143 e LGPD-RT09). O schema não permite anonimização in-place sem migração (`patientId` é FK NOT NULL) e a anonimização parcial gera falsa conformidade (`lgpd_data_audit.md` §2.2). Dependentes de `alerts` (`alert_deliveries`, `alert_idempotency_keys`, `alert_outbox`) saem **primeiro**, na MESMA transação (`pg_advisory_xact_lock`, chave própria).
- **B3 — contadores antes do delete:** contagens por tabela + `alerts` por `riskLevel`, apuradas antes do DELETE e levadas ao log — único resíduo operacional.
- **C1 — registro operacional:** stdout + `session.log` (`serverpod_log`), fora da cadeia `audit_logs`.
- **Prazos:** alertas **2 anos** (730), visitas **5 anos** (1825), triagens **5 anos** (1825) — tabela de `lgpd_design.md` §5.6. Corte de `visits` por `COALESCE("completedAt","scheduledAt")` (nenhuma linha escapa por NULL).
- **Agendamento:** `FutureCall` `retentionExpurge`, diário às **03:00 UTC**; primeira janela agendada no boot; identifier fixo + `deleteWhere` = idempotente entre restarts; cada execução agenda a próxima **antes** de purgar.
- **Config:** `RETENTION_ALERT_DAYS`, `RETENTION_VISIT_DAYS`, `RETENTION_TRIAGE_DAYS` — opcionais, defaults acima, inteiro positivo com teto sanitário de 36500 (falha no boot em vez de apagar demais).

**Arquivos criados:**
- `lib/src/application/retention/expurge_service.dart` — `RetentionPolicy`, `RetentionStore`, `ExpurgeService`, `ExpurgeCounts`/`ExpurgeResult`, `nextDailyRun` (puro)
- `lib/src/application/retention/expurge_future_call.dart` — `ExpurgeFutureCall` + `ensureRetentionExpurgeScheduled`
- `lib/src/infrastructure/database/orm_retention_store.dart` — DELETEs + advisory lock
- `test/unit/expurge_service_test.dart`
- `test/integration/retention_expurge_test.dart`

**Arquivos modificados:**
- `lib/server.dart` — registro + agendamento no boot
- `lib/src/config/app_config.dart` — prazos + validação
- `.env.example` — variáveis documentadas (opcionais)

**Evolução planejada (curto/médio prazo):**
- **C2/C3** — gravar o expurgo na cadeia `audit_logs` (usuário-sentinela de sistema, ou ator de sistema no schema).
- **B2** — anonimização in-place (exige migração; risco de anonimização parcial documentado em `lgpd_data_audit.md` §4.4).
- **Tabela de agregados durável** — para séries epidemiológicas consultáveis (hoje os contadores B3 só são logados).

---

## Pendência Documentada (Limitação do Framework)

### 5. users.birthDate com timestamp em vez de date

**Arquivo:** `backend/sinalacs_server/lib/src/models/user.spy.yaml` (linha 16)

**Status:** Não acionável no momento. Serverpod 3.4.13 não expõe tipo `date` no DSL (`ColumnType` não tem variante `date`, gerador recusa o modelo).

**Mitigação atual:**
- Coluna carrega meia-noite UTC (app envia data pura)
- `PasswordlessAuthService` compara por dia (ano/mês/dia em UTC)
- Documentado no próprio `.spy.yaml` (linhas 8-15)

**Ação futura:** Reavaliar quando Serverpod suportar tipo `date` nativo.

---

## Checklist de Validação Pós-Implementação

- [x] `serverpod generate` executado sem erros
- [x] `serverpod create-migration` — migração `20261007153048060` (DROP `emergencyContact` + 2 ADDs, conferida no SQL)
- [x] Migração aplicada no banco de desenvolvimento (`docker compose up --build`) — `emergencyContact` removida, par cifrado populado (6 pacientes, 0 vazios, sem texto claro), FutureCall `retentionExpurge` agendado para 03:00 UTC
- [x] `dart analyze` — 0 erros / 0 warnings
- [x] `dart test test/unit` — 468 passando
- [x] `dart test test/integration` — 171 passando (Postgres real, `postgres-test`)
- [x] `flutter analyze` nos 3 apps — sem issues
- [ ] `flutter test` nos apps — **pendente (ambiental)**: no ACS 447/536 passam; as 89 falhas são por `libsqlite3.so` ausente na máquina (o CI instala `libsqlite3-0`; planos antigos registram a mesma falha como pré-existente). `sudo apt-get install -y libsqlite3-0` fecha.
- [x] Logs de erro sem objetos de domínio — grep de `$error`/`$stackTrace` em `stderr.writeln` no `lib/` = 0
- [x] `ipHash` de `audit_logs` usa HMAC (`RotatingIpHasher`); `consent_logs.ipHash` é marcador, não hash (falso-positivo corrigido)
- [x] `emergencyContact` cifrado — texto claro fora do SQL (cifragem pré-query, mesmo vetor de `chronicConditions`)
- [x] FutureCall de expurgo registrado e com agendamento idempotente (`lib/server.dart` + `expurge_future_call.dart`)
- [x] Seeds atualizados (`development.sql`, `seed_health_data.dart`, `seed_e2e_fixtures.dart`) e exercitados nos testes e na stack real

---

## Ordem de Execução (estado)

1. **emergencyContact** (criptografia) — ✅ aplicado (migração `20261007153048060`)
2. **ipHash HMAC** — ✅ aplicado (`RotatingIpHasher`)
3. **Sanitização de logs** — ✅ aplicado (5 arquivos, incluindo `server.dart`)
4. **Rotina de expurgo** — ✅ aplicado (B1 + B3 + C1)
5. **Validação final** — ✅ backend (`analyze` + 468 unit + 171 integração); ✅ stack real (`docker compose up --build`, migração `20261007153048060` aplicada, seeds OK, FutureCall `retentionExpurge` agendado); ✅ `flutter analyze` nos 3 apps; ⏳ `flutter test` dos apps (ambiental — ver checklist)

---

## Referências Cruzadas

- `spec/lgpd_data_audit.md` — Auditoria completa (fonte)
- `spec/lgpd_design.md` — Requisitos LGPD-RF07, RF09, RT02, RT03 (política de retenção: §5.6)
- `spec/PRD_system.md` — LGPD-RF07 (linha 642), INV-04
- `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §6 — Decisão de criptografia em aplicação
- `backend/sinalacs_server/lib/src/infrastructure/crypto/health_data_cipher.dart` — `HealthDataCipher` (padrão de cifragem)
- `backend/sinalacs_server/lib/src/infrastructure/crypto/rotating_ip_hasher.dart` — `RotatingIpHasher` (HMAC do IP)
- `backend/sinalacs_server/lib/src/application/audit/audit_chain.dart` — `AuditChain` (padrão HMAC para cadeia)
- `backend/sinalacs_server/lib/src/application/retention/expurge_service.dart` — política, service e `nextDailyRun`
- `backend/sinalacs_server/lib/src/application/retention/expurge_future_call.dart` — `ExpurgeFutureCall` + agendamento
- `backend/sinalacs_server/lib/src/infrastructure/database/orm_retention_store.dart` — DELETEs + advisory lock

---

## Notas para o Modelo Build

- **Não edite arquivos gerados** em `lib/src/generated/` — sempre modifique `.spy.yaml` e rode `serverpod generate`
- **Mantenha separação** `application/` (regras de negócio) vs `infrastructure/` (ORM, crypto)
- **Testes de integração** herméticos (`flutter test`) não substituem validação com stack Docker real
- **CI roda 9 jobs** (ver `.github/workflows/ci.yml`); `android-e2e` sobe emulador contra stack real
- **Variáveis de ambiente** via `scripts/dev/bootstrap_env.sh` — não há `.env` versionado