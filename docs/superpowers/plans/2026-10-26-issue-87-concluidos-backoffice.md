# ISSUE #87: contador "Concluídos" no backoffice. Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** um alerta vermelho que chega a `resolved` continua visível para a coordenação: `admin.indicators` devolve `resolvedRedAlerts`, a tela Indicadores mostra "Concluídos", a tela Alertas mostra "Concluído" e a hora da conclusão, e a soma dos contadores por estado fecha com o total de vermelhos do escopo (INV-03).

**Architecture:** a partição dos vermelhos por estado passa a ter uma fonte única no servidor (`RedAlertBucket`, `switch` exaustivo sobre `AlertStatus`), de onde o SQL de `OrmAdminReadStore.indicators` deriva as listas de cada `FILTER`. O escopo por papel e UBS não muda: é o mesmo `WHERE $_escopo` e o mesmo `AdminScopeResolver` dos demais indicadores. O cliente gerado ganha `AdminIndicators.resolvedRedAlerts` e `AdminAlert.resolvedAt`; o app admin espelha os dois campos em `DashboardIndicators` e `AlertSummary`, e o pulso de 30 s (#44) carrega o contador novo sem mudança no servidor. Nada muda em como o status é gravado nem nas transições (`alerts.resolve` continua o único escritor de `resolved`).

**Tech Stack:** Serverpod 3.4.13 (`.spy.yaml` + `serverpod generate`, `unsafeQuery` com parâmetros nomeados), Dart `test` com `withServerpod` (Postgres de teste em `localhost:9090`), Flutter `flutter_test` (admin, `MockAdminDataSource`, `ScriptedPulseDataSource`), `integration_test` no emulador (`sinalacs_ci36`, API 36) com os scripts `scripts/qa/*_e2e.sh` e o relé `otp_relay.py`.

**Spec:** issue #87 (`gh issue view 87`), item adiado da #76 (PR #85, `PROGRESS.md` seção "Estado \"Atendido\" do alerta (#76)"); invariante INV-03 de `spec/PRD_system.md`; escopo por papel/UBS da #40 (`backend/CLAUDE.md`, "Leitura do backoffice"); pulso da #44 (`docs/superpowers/specs/2026-10-11-adr-tempo-real-alertas-admin.md`, D5).

## Base do branch

`develop` está limpo em `91adaed` (merge do PR #107). Nenhum PR aberto toca `admin_indicators.spy.yaml`, `orm_admin_read_store.dart` ou as telas do admin.

- [ ] `git switch develop && git pull && git switch -c feat/issue-87-concluidos`
- [ ] A reprodução (Task 1) roda nesse ponto, antes de qualquer correção.

## Restrições globais

- Português em código, comentários, mensagens de commit (`tipo(escopo): descrição (#87)`) e documentação. Sem atribuição de IA em commits e PR (regra do `CLAUDE.md`).
- **Só leitura e exibição.** Nenhuma mudança em `alerts.resolve`, `alerts.acknowledge`, `AlertStore`, `OrmAlertEscalationStore` ou no `UPDATE` de status. O inventário `test/unit/red_alert_discard_paths_test.dart` tem de continuar verde sem alteração na lista.
- **Escopo sem duplicação.** O contador novo vive no mesmo `SELECT` de `OrmAdminReadStore.indicators` (`backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart:47-80`), com o mesmo `WHERE $_escopo` e o mesmo parâmetro `@ubs`. Nenhum filtro de papel ou de UBS é escrito de novo; `AdminReadService.indicators` não muda.
- **Partição fechada dos vermelhos** (decisão deste plano; rótulos da tela entre aspas):

  | `AlertStatus` | Contador de `AdminIndicators` | Rótulo na tela Indicadores |
  |---|---|---|
  | `pending` | `openRedAlerts` | "Abertos (pendentes)" (mantido: `login_flow_test.dart:21` e o e2e da #44 o procuram) |
  | `escalated` (legado: nada o grava desde a #44, D3) | `openRedAlerts` | idem; um escalonado é um aberto sem confirmação |
  | `acknowledged` | `acknowledgedRedAlerts` | "Reconhecidos (em atendimento)" — **não cumulativo**: o concluído sai daqui |
  | `resolved` | `resolvedRedAlerts` (novo) | "Concluídos" |

  Invariante: `red == openRedAlerts + acknowledgedRedAlerts + resolvedRedAlerts` em todo escopo. `overdueRed` do pulso não é contador da partição (é um subconjunto de `pending`).
- **Protocolo:** `resolvedRedAlerts: int` (obrigatório, não anulável) e `AdminAlert.resolvedAt: DateTime?`. Sem `table:` nos dois modelos, logo **sem migração** e sem `scripts/dev/append_audit_append_only.sh`. Compatibilidade na Task 2.
- Testes de integração do backend: `docker compose --profile test up -d postgres-test` (já no ar) e `dart test -j 1`.
- Dados sintéticos em todos os testes e no e2e; nada no banco de desenvolvimento.

## Pontos de atenção na revisão

1. **Estado novo ou legado fora de qualquer contador.** Um `AlertStatus` que não caia em nenhum balde some da coordenação em silêncio. Guarda: `switch` exaustivo em `RedAlertBucket.of` (erro de compilação para valor novo) e o teste de invariante no Postgres com uma linha `escalated` inserida (Task 3).
2. **Alerta sem microárea concluído.** O administrador conta; o coordenador não (regra da #40). Guarda: teste de escopo negativo no store e no endpoint (Tasks 3 e 4) e o alerta sem microárea do e2e (Task 8).
3. **`resolved` sem `resolvedAt`.** Uma linha concluída por SQL ou anterior à #76 chega com `resolvedAt` nulo: o cartão mostra "Status: Concluído" e nenhuma hora, nunca uma exceção. Guarda: teste de widget com `resolvedAt: null` (Task 7).
4. **Pulso cego ao contador novo.** Se `MonitoringController._mudou` não comparar `resolvedRedAlerts`, um pulso em que só ele mudou não sobe a revisão. Guarda: teste em `alerts_auto_refresh_test.dart` (Task 5).
5. **Deslocamento de coluna em `alerts()`.** Acrescentar `a."resolvedAt"` ao `SELECT` desloca `vencido` de `r[7]` para `r[8]`; um índice errado troca `overdue` por uma data. Guarda: os testes existentes de `overdue` em `admin_read_store_test.dart` (grupo "escalonamento (#44)") e o teste novo de `resolvedAt` (Task 3).

---

### Task 1: Reprodução no emulador (falha antes da correção)

**Arquivos:**
- Criar: `apps/admin/integration_test/admin_concluidos_e2e.dart`
- Criar: `scripts/qa/admin_concluidos_e2e.sh`
- Criar: `scripts/qa/admin_concluidos_e2e_test.sh`
- Criar: `docs/superpowers/plans/2026-10-26-issue-87-reproducao.log`

**Interfaces:**
- Consome: a anatomia de `scripts/qa/admin_alertas_escalonar_e2e.sh` (stack de e2e, `e2e_stack.sh up/seed/psql`, relé `/coordenador`, `adb reverse` da 8443 e da 8765, laço que lê linhas marcadoras de `$saida_teste`, `igual()`, `cleanup` que apaga `.e2e/fixtures.json` antes do `down`) e de `apps/admin/integration_test/admin_alertas_escalonar_e2e.dart` (`_pumpUntil`, `_abertosNoPainel`, `_entrar` com ativação da MFA do coordenador, `_cartao`, `_noCartao`). O seed `E2E_SEED_ADMIN_ALERTS=1` (3 alertas: `adminAlertIds[0]` vermelho pendente, `[1]` vermelho reconhecido 60 s depois, `[2]` verde pendente, todos na microárea do coordenador).
- Produz: o par script/teste que a Task 8 roda de novo com a correção. Linhas marcadoras: `E2E_RECONHECER id=`, `E2E_CONCLUIR id=`, `E2E_CONCLUIR_SEM_MICROAREA`; evidências `E2E_PAINEL_RECONHECIDO atraso_ms=`, `E2E_PAINEL_CONCLUIDO atraso_ms=`, `E2E_ALERTAS_CONCLUIDO_OK`.

O alerta percorre os estados por `UPDATE` no banco de e2e (o papel do ACS, como a #86 fez em `acs_ack_concluido_e2e.sh`): a mudança da issue é de leitura, e o que se prova é que o Painel acompanha cada transição pelo pulso, sem toque.

- [ ] **Passo 1: escrever `admin_concluidos_e2e.dart`** (`@Timeout(Duration(minutes: 10))`, mesmo esqueleto do e2e da #44; `E2E_ALERTA_PENDENTE`/`E2E_ALERTA_RECONHECIDO` por `--dart-define`, ids de `adminAlertIds[0]`/`[1]`). Um `testWidgets('alerta vermelho concluído continua visível nos Indicadores e na lista (#87)')`:
  1. `_entrar` como coordenador; esperar `Painel de Indicadores`; rolar até `Abertos (pendentes)`; `_pumpUntil` com "Abertos" = `1` **e** `_linhaDoPainel('Reconhecidos (em atendimento)', '1')` (generalização de `_abertosNoPainel` que recebe o rótulo). `expect(find.text('Concluídos'), findsOneWidget, reason: '#87: o Painel não tem a linha "Concluídos"')` — é aqui que a reprodução falha.
  2. `print('E2E_RECONHECER id=$pendente')`; `_pumpUntil` ≤ 40 s: Abertos `0`, Reconhecidos `2`, Concluídos `0`; `print('E2E_PAINEL_RECONHECIDO atraso_ms=…')`.
  3. `print('E2E_CONCLUIR id=$reconhecido')`; `_pumpUntil` ≤ 40 s: Abertos `0`, Reconhecidos `1`, Concluídos `1`; `print('E2E_PAINEL_CONCLUIDO atraso_ms=…')`. Em cada passo o cartão "Vermelho" segue `2`: soma fechada.
  4. `print('E2E_CONCLUIR_SEM_MICROAREA')`; bombear 40 s; Concluídos continua `1` (o alerta sem microárea é só do administrador).
  5. aba Alertas; `_pumpUntil` até `_cartao(reconhecido)`; `expect(_noCartao(reconhecido, find.text('Status: Concluído')), isTrue)`, `expect(_noCartao(reconhecido, find.textContaining('Concluído às')), isTrue)`, `expect(_noCartao(pendente, find.textContaining('Concluído às')), isFalse)`; filtro de status "Concluído" → só esse cartão; `print('E2E_ALERTAS_CONCLUIDO_OK')`.

- [ ] **Passo 2: escrever `admin_concluidos_e2e.sh`** a partir do script da #44 (cabeçalho com o passo a passo manual, `dev="${DEVICE:-emulator-5554}"`, `E2E_SEED_ADMIN_ALERTS=1 ./scripts/qa/e2e_stack.sh seed`, relé, `adb reverse`, `flutter test integration_test/admin_concluidos_e2e.dart -d "$dev" --dart-define=…`). O laço atende:
  - `E2E_RECONHECER id=<uuid>` → `UPDATE alerts SET status='acknowledged', "receivedAt"=NOW(), "acknowledgedAt"=NOW(), "acsId"=<acs da fixture> WHERE id=<uuid> AND status='pending'`;
  - `E2E_CONCLUIR id=<uuid>` → `UPDATE alerts SET status='resolved', "resolvedAt"=NOW() WHERE id=<uuid> AND status='acknowledged'`;
  - `E2E_CONCLUIR_SEM_MICROAREA` → `INSERT` de um vermelho `resolved` com `"microAreaId" IS NULL`, `"resolvedAt"=NOW()`, paciente `main`, `locationHash 'hash-e2e'`, sem linha no `alert_outbox`.
  Cada `id` é validado como UUID antes do SQL (como `inserir_alerta` da #44). Ao fim, exigir status 0 e as três evidências na saída, e conferir com `igual`:
  - `select count(*) from alerts where "riskLevel"='red' and status='resolved'` → `2`
  - `select count(*) from alerts where "riskLevel"='red' and status='resolved' and "microAreaId" is null` → `1`
  - `select count(*) from audit_logs where "resourceType"='admin_pulse'` → `0` (o pulso segue sem linha `read`)
  - `select count(*) from alert_outbox where "alertId" in (…ids…)` → `0` (nada foi republicado)
  Depois, `audit_chain_check` como no script da #44.

- [ ] **Passo 3: escrever `admin_concluidos_e2e_test.sh`** no molde de `admin_alertas_escalonar_e2e_test.sh`: `bash -n`; `DEVICE` com padrão; `-d "$dev"`; `E2E_SEED_ADMIN_ALERTS=1 ./scripts/qa/e2e_stack.sh seed` presente; as três marcas no `.dart` (`print('E2E_RECONHECER `, `print('E2E_CONCLUIR `, `print('E2E_CONCLUIR_SEM_MICROAREA`) e no `.sh`; os dois `UPDATE` com `status='acknowledged'` e `status='resolved'`; os quatro `igual`; `rm -f .e2e/fixtures.json` antes de `e2e_stack.sh down`; sufixo `_e2e`.
  Rodar: `bash scripts/qa/admin_concluidos_e2e_test.sh` → `OK`.

- [ ] **Passo 4: reproduzir no emulador** (código sem correção). Nenhum emulador está ligado agora (`adb devices` vazio; AVDs: `sinalacs_ci36`, `Medium_Phone`, `sinalacs_api24`, `sinalacs_api27`):
  ```bash
  export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator"
  emulator -avd sinalacs_ci36 -no-snapshot &
  adb wait-for-device && adb devices          # emulator-5554
  ./scripts/qa/admin_concluidos_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-26-issue-87-reproducao.log
  ```
  Esperado: **FALHA** no passo 1 do teste com `#87: o Painel não tem a linha "Concluídos"`. Antes do `down`, registrar à mão no log (com `./scripts/qa/e2e_stack.sh psql`) o estado do alerta `[1]` depois de um `UPDATE … 'resolved'` feito à mão e a tela Alertas mostrando "Status: Resolvido" sem hora. Isso documenta "como aparece hoje", que a issue pede.
  Ao terminar: `docker compose up -d` devolve a stack de desenvolvimento.

- [ ] **Passo 5: commit** (o e2e é opt-in, fora da CI; falha de propósito até a Task 8)

```bash
git add apps/admin/integration_test/admin_concluidos_e2e.dart scripts/qa/admin_concluidos_e2e.sh scripts/qa/admin_concluidos_e2e_test.sh docs/superpowers/plans/2026-10-26-issue-87-reproducao.log
git commit -m "test(e2e): alerta concluído some dos Indicadores do backoffice (#87, reprodução)"
```

---

### Task 2: Protocolo — `resolvedRedAlerts` e `AdminAlert.resolvedAt`, geração do cliente

**Arquivos:**
- Modificar: `backend/sinalacs_server/lib/src/models/api/admin_indicators.spy.yaml`
- Modificar: `backend/sinalacs_server/lib/src/models/api/admin_alert.spy.yaml`
- Gerados (nunca à mão): `backend/sinalacs_server/lib/src/generated/api/admin_indicators.dart`, `…/generated/api/admin_alert.dart`, `backend/sinalacs_client/lib/src/protocol/api/admin_indicators.dart`, `…/protocol/api/admin_alert.dart`. `protocol.dart`/`client.dart`/`endpoints.dart` não mudam (nenhuma classe nem método novo). Confirmar com `git status` depois do `generate`: só esses quatro.
- Modificar (só para compilar, valor `0`): `backend/sinalacs_server/test/unit/admin_read_service_test.dart:87`, `backend/sinalacs_server/test/unit/admin_monitoring_service_test.dart:35`, `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart:73` (temporário: `resolvedRedAlerts: 0`; a Task 3 troca pela consulta).

**Interfaces:**
- Produz: `AdminIndicators({…, required int resolvedRedAlerts, int? tmravSeconds})` e `AdminAlert({…, DateTime? escalatedAt, DateTime? resolvedAt, required bool overdue})`, no servidor e no cliente.

**Ordem:** a issue sugere "consulta e store → endpoint e `.spy.yaml` → geração do cliente". Aqui o `.spy.yaml` e o `generate` vêm antes do store porque `OrmAdminReadStore.indicators` devolve o tipo gerado `AdminIndicators`: sem o campo gerado, o teste do store nem compila.

**Compatibilidade (decisão):** campo **obrigatório**, não anulável, sem valor padrão. Servidor novo → app antigo: o `fromJson` gerado lê só as chaves que conhece, a chave extra é ignorada e o app antigo segue sem a linha. App novo → servidor antigo: `jsonSerialization['resolvedRedAlerts'] as int` lança `TypeError` em chave ausente; é um `Error`, não `Exception`, então passa pelo `_guard` de `BackendAdminDataSource` e cai no tratamento genérico da tela (texto fixo de erro), sem dado parcial. `int?` foi descartado: "Concluídos: —" leria como "sem amostra" (o significado do traço no TMRAV) e tornaria a soma do INV-03 inverificável na tela. Os três apps e o servidor saem do mesmo checkout e a stack local é reconstruída junta, então a direção "app novo, servidor antigo" não é um caminho de implantação deste projeto.

- [ ] **Passo 1: editar os dois `.spy.yaml`.** Em `admin_indicators.spy.yaml`, depois de `acknowledgedRedAlerts: int`:
  ```yaml
  ### Vermelhos concluídos pelo ACS (#87). Partição com `openRedAlerts`
  ### (`pending` e o legado `escalated`) e `acknowledgedRedAlerts`
  ### (`acknowledged`): `red` é sempre a soma dos três (INV-03).
  resolvedRedAlerts: int
  ```
  Em `admin_alert.spy.yaml`, depois de `escalatedAt: DateTime?`:
  ```yaml
  ### Conclusão do atendimento (#76), se houve. Nulo também numa linha
  ### `resolved` anterior à coluna: a tela mostra o estado sem a hora.
  resolvedAt: DateTime?
  ```
- [ ] **Passo 2: gerar.** `cd backend/sinalacs_server && serverpod generate`; `cd backend && dart analyze` → falha de compilação nos três construtores listados acima (prova de que o campo é obrigatório).
- [ ] **Passo 3: `resolvedRedAlerts: 0`** nos dois fakes de teste e, temporariamente, no store. `dart analyze` → limpo. `dart test test/unit/admin_read_service_test.dart test/unit/admin_monitoring_service_test.dart` → PASS.
- [ ] **Passo 4: commit**

```bash
git add backend/sinalacs_server/lib/src/models/api backend/sinalacs_server/lib/src/generated backend/sinalacs_client/lib/src/protocol backend/sinalacs_server/test/unit backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart
git commit -m "feat(backend): AdminIndicators.resolvedRedAlerts e AdminAlert.resolvedAt no protocolo (#87)"
```

---

### Task 3: Partição única e consulta do store

**Arquivos:**
- Criar: `backend/sinalacs_server/lib/src/application/admin/red_alert_bucket.dart`
- Criar: `backend/sinalacs_server/test/unit/red_alert_bucket_test.dart`
- Modificar: `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart:47-80` (indicators) e `:176-230` (alerts)
- Modificar: `backend/sinalacs_server/test/integration/admin_read_store_test.dart` (seed `_seed`, fixture `_alerta`, grupo de indicadores)

**Interfaces:**
- Produz:
  ```dart
  /// Em qual contador de `AdminIndicators` um vermelho cai, pelo status (#87).
  enum RedAlertBucket {
    open, acknowledged, resolved;

    /// `switch` exaustivo: um valor novo de `AlertStatus` não compila sem decidir o balde.
    static RedAlertBucket of(AlertStatus status);
    /// Os status do balde, na ordem de `AlertStatus.values`.
    List<AlertStatus> get statuses;
    /// `'pending','escalated'`: lista para um `IN (…)` de SQL. Só nomes de enum, nunca entrada do usuário.
    String get sqlList;
  }
  ```
- Consome: `AdminIndicators` da Task 2.

- [ ] **Passo 1: teste unitário** `red_alert_bucket_test.dart`:
  ```dart
  test('todo AlertStatus cai em exatamente um balde', () {
    for (final s in AlertStatus.values) {
      final baldes = RedAlertBucket.values.where((b) => b.statuses.contains(s));
      expect(baldes, hasLength(1), reason: s.name);
      expect(RedAlertBucket.of(s), baldes.single);
    }
  });
  test('escalated é aberto; acknowledged, reconhecido; resolved, concluído', () {
    expect(RedAlertBucket.of(AlertStatus.pending), RedAlertBucket.open);
    expect(RedAlertBucket.of(AlertStatus.escalated), RedAlertBucket.open);
    expect(RedAlertBucket.of(AlertStatus.acknowledged), RedAlertBucket.acknowledged);
    expect(RedAlertBucket.of(AlertStatus.resolved), RedAlertBucket.resolved);
  });
  test('sqlList só tem nomes de enum entre aspas simples', () {
    expect(RedAlertBucket.open.sqlList, "'pending','escalated'");
    expect(RedAlertBucket.resolved.sqlList, "'resolved'");
  });
  ```
  Rodar: `dart test test/unit/red_alert_bucket_test.dart` → FAIL (arquivo não existe).
- [ ] **Passo 2: implementar `red_alert_bucket.dart`** (`statuses` deriva de `of`, filtrando `AlertStatus.values`; `sqlList` = `statuses.map((s) => "'${s.name}'").join(',')`). Rodar → PASS.
- [ ] **Passo 3: teste de integração** em `admin_read_store_test.dart`. No `_seed`, dois vermelhos novos (o helper `_alerta` ganha `Duration? concluidoApos`, que preenche `resolvedAt: em.add(concluidoApos)`):
  - `a6`: `maA`, `resolved`, `em: _t − 90 min`, `reconhecidoApos: 90 s`, `concluidoApos: 10 min` (dentro da janela: o TMRAV vira `avg(60,120,90) = 90`, inalterado);
  - `b2`: `maB`, `resolved`, `em: _t − 40 dias`, `reconhecidoApos: 30 s`, `concluidoApos: 5 min` (fora da janela: o TMRAV da UBS B segue nulo).
  Atualizar as expectativas existentes: sistema `red 8`, `openRedAlerts 3`, `acknowledgedRedAlerts 3`, `tmravSeconds 90`; UBS A `red 5`, `openRedAlerts 1`, `acknowledgedRedAlerts 3`; UBS B `red 2`, `openRedAlerts 1`, `tmravSeconds` nulo. Testes novos no mesmo grupo:
  ```dart
  test('concluídos (#87): sistema 2, UBS A 1, UBS B 1', () async { … resolvedRedAlerts … });
  test('concluído sem microárea (#87): só o escopo de sistema o conta', () async {
    await _alerta(session, risco: RiskLevel.red, status: AlertStatus.resolved,
        em: _t.subtract(const Duration(minutes: 20)), reconhecidoApos: const Duration(seconds: 60),
        concluidoApos: const Duration(minutes: 5));            // sem `ma`
    expect((await store.indicators(const AdminScope.system(), now: _t)).resolvedRedAlerts, 3);
    expect((await store.indicators(const AdminScope.ubs(_ubsA), now: _t)).resolvedRedAlerts, 1);
    expect((await store.indicators(const AdminScope.ubs(_ubsB), now: _t)).resolvedRedAlerts, 1);
  });
  test('INV-03 (#87): red é a soma dos três contadores em todo escopo, mesmo com escalated legado', () async {
    await _alerta(session, risco: RiskLevel.red, status: AlertStatus.escalated,
        em: _t.subtract(const Duration(minutes: 15)), ma: _maA);
    for (final escopo in [const AdminScope.system(), const AdminScope.ubs(_ubsA), const AdminScope.ubs(_ubsB)]) {
      final r = await store.indicators(escopo, now: _t);
      expect(r.red, r.openRedAlerts + r.acknowledgedRedAlerts + r.resolvedRedAlerts, reason: '$escopo');
    }
    expect((await store.indicators(const AdminScope.ubs(_ubsA), now: _t)).openRedAlerts, 2);
  });
  test('alerts (#87): resolvedAt vem na linha e overdue não se desloca', () async {
    final pagina = await store.alerts(const AdminScope.ubs(_ubsB), limit: 50, offset: 0, now: _t);
    final concluido = pagina.items.singleWhere((a) => a.status == AlertStatus.resolved);
    expect(concluido.resolvedAt, _t.subtract(const Duration(days: 40)).add(const Duration(minutes: 5)));
    expect(concluido.overdue, isFalse);
    expect(pagina.items.singleWhere((a) => a.status == AlertStatus.pending).resolvedAt, isNull);
  });
  ```
  Rodar: `dart test -j 1 test/integration/admin_read_store_test.dart` → os novos FALHAM (`resolvedRedAlerts` é `0`, `resolvedAt` não existe no `AdminAlert` do store).
- [ ] **Passo 4: implementar no store.** Em `indicators`, os três `FILTER` de status viram `a."status" IN (${RedAlertBucket.open.sqlList})` etc. (o texto da consulta continua fixo: os nomes vêm do enum), mais a coluna `count(*) FILTER (WHERE a."riskLevel" = 'red' AND a."status" IN (${RedAlertBucket.resolved.sqlList}))` em `r[5]`, deslocando o TMRAV para `r[6]`. Em `alerts`, `a."resolvedAt"` depois de `a."escalatedAt"` (`r[7]`), `vencido` passa a `r[8]`, e `AdminAlert(resolvedAt: (r[7] as DateTime?)?.toUtc(), overdue: r[8] as bool)`. Atualizar o doc da classe (o escopo do contador novo é o mesmo). Rodar o arquivo inteiro → PASS, inclusive os grupos de `overdue`.
- [ ] **Passo 5: commit**

```bash
git add backend/sinalacs_server/lib/src/application/admin/red_alert_bucket.dart backend/sinalacs_server/test/unit/red_alert_bucket_test.dart backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart backend/sinalacs_server/test/integration/admin_read_store_test.dart
git commit -m "feat(backend): contador de vermelhos concluídos no escopo dos indicadores (#87)"
```

---

### Task 4: Endpoint — escopo por papel no RPC real

**Arquivos:**
- Modificar: `backend/sinalacs_server/test/integration/admin_endpoint_test.dart` (seed `_seed` e os testes de `indicators`)
- Modificar: `backend/sinalacs_server/test/unit/admin_read_service_test.dart` (um `expect` a mais)

**Interfaces:**
- Consome: `endpoints.admin.indicators(sessionBuilder, accessToken:)` e os tokens `_token(id, UserRole)` do próprio arquivo.

Não há código de produção nesta task: o endpoint e o serviço só repassam. O que se prova é o escopo por papel com tokens reais, com o caso negativo.

- [ ] **Passo 1: estender o `_seed`** do endpoint com um vermelho `resolved` na microárea B (`acknowledgedAt` e `resolvedAt` preenchidos) e ajustar as expectativas tocadas: no teste do admin `ind.red` `2 → 3` e `alerts … hasLength(3) → 4`; no do coordenador A `.red` segue `1`.
- [ ] **Passo 2: testes** (um por papel existente):
  - admin: `expect(ind.resolvedRedAlerts, 1)`;
  - coordenador A: `expect(ind.resolvedRedAlerts, 0, reason: 'o concluído é da UBS B')`;
  - coordenador B (há `_coordB` no arquivo? se não, criar nos moldes de `_coordA` com `ubsId` B): `expect(ind.resolvedRedAlerts, 1)`;
  - `acs` e `patient`: já recusados nos testes de papel (`AlertPermissionException`); acrescentar `resolvedRedAlerts` nada muda — confirmar que os testes existentes continuam cobrindo `indicators`.
  - invariante no endpoint: para admin e coordenadores, `ind.red == ind.openRedAlerts + ind.acknowledgedRedAlerts + ind.resolvedRedAlerts`.
  Em `admin_read_service_test.dart`, no teste que já verifica a ordem `audit → store`, `expect(r.resolvedRedAlerts, 0)` (o serviço devolve o que o store deu, sem recalcular).
  Rodar: `dart test -j 1 test/integration/admin_endpoint_test.dart test/unit/admin_read_service_test.dart` → PASS (é teste de caracterização: passa sem código novo; se falhar, o escopo do store está errado).
- [ ] **Passo 3: suíte do backend** `cd backend/sinalacs_server && dart test -j 1` → PASS; `cd backend && dart analyze` → limpo.
- [ ] **Passo 4: commit**

```bash
git add backend/sinalacs_server/test
git commit -m "test(backend): escopo por papel do contador de concluídos no admin.indicators (#87)"
```

---

### Task 5: App admin — camada de dados e pulso

**Arquivos:**
- Modificar: `apps/admin/lib/core/data/admin_data_source.dart:14-30` (`DashboardIndicators`) e `:52-80` (`AlertSummary`)
- Modificar: `apps/admin/lib/core/data/backend_admin_data_source.dart:42-54`, `:205-233`, `:353-370`
- Modificar: `apps/admin/lib/core/data/mock_admin_data_source.dart:131-178` (seed), `:261-277` (indicadores), `:300-314` (`_comEscalonamento`), `:474-489` (pulso)
- Modificar: `apps/admin/lib/app/monitoring_controller.dart` (`_mudou`)
- Testes: `apps/admin/test/backend_admin_data_source_test.dart`, `apps/admin/test/mock_admin_data_source_test.dart`, `apps/admin/test/alerts_auto_refresh_test.dart`; ajustar os construtores de `DashboardIndicators(` em `dashboard_tmrav_test.dart`, `alerts_auto_refresh_test.dart`, `indicators_stale_test.dart` e os `api.AdminIndicators(` de `backend_admin_data_source_test.dart` (listar com `grep -rn "DashboardIndicators(\|api.AdminIndicators(" apps/admin/test`).

**Interfaces:**
- Produz: `DashboardIndicators({…, required int acknowledgedRedAlerts, required int resolvedRedAlerts, required int? tmravSeconds})` e `AlertSummary({…, DateTime? escalatedAt, DateTime? resolvedAt, bool overdue = false})`.
- Consome: o cliente gerado da Task 2 (`r.resolvedRedAlerts`, `a.resolvedAt`).

- [ ] **Passo 1: testes.**
  - `backend_admin_data_source_test.dart`: no teste "indicadores: mapeia contagens…", `resolvedRedAlerts: 4` no `api.AdminIndicators` e `expect(r.resolvedRedAlerts, 4)`; no de `fetchAlerts`, um item com `resolvedAt: DateTime.utc(2026, 10, 26, 12)` e `expect(lista.single.resolvedAt, …)`; no do pulso, `resolvedRedAlerts` embutido passa como veio.
  - `mock_admin_data_source_test.dart`: no primeiro teste, `expect(indicators.resolvedRedAlerts, 0)` e `expect(indicators.countsByRisk[RiskLevel.red], indicators.openRedAlerts + indicators.acknowledgedRedAlerts + indicators.resolvedRedAlerts)`; teste novo: `fetchAlerts(status: AlertStatus.resolved)` devolve `alert-4` e `alert-6` com `resolvedAt` não nulo, e `alertsPulse().maxChangedAt` não é anterior ao maior `resolvedAt`.
  - `alerts_auto_refresh_test.dart`: teste `'lista recarrega quando só o contador de concluídos muda (#87)'`: `fonte.indicadores = DashboardIndicators(…base…, resolvedRedAlerts: base.resolvedRedAlerts + 1)`; `await ciclo(tester)`; `expect(fonte.buscasDeAlertas, 2)`.
  Rodar: `cd apps/admin && flutter test test/backend_admin_data_source_test.dart test/mock_admin_data_source_test.dart test/alerts_auto_refresh_test.dart` → FAIL de compilação.
- [ ] **Passo 2: implementar.** `DashboardIndicators.resolvedRedAlerts` (obrigatório, doc: "partição com `openRedAlerts` e `acknowledgedRedAlerts`; a soma é o vermelho total"); `AlertSummary.resolvedAt` (doc: "nulo numa linha concluída antes da coluna"); mapeamentos em `fetchDashboardIndicators`, `fetchAlerts` e `alertsPulse`; mock: `resolvedAt` em `alert-4` (`DateTime(2026, 9, 10, 19, 40)`) e `alert-6` (`DateTime(2026, 9, 9, 11, 30)`), `resolvedRed` contado por `status == AlertStatus.resolved`, `_comEscalonamento` repassa `resolvedAt`, e o `maior` do pulso inclui `a.resolvedAt` (espelho de `fa549b2`); `_mudou` compara `ia.resolvedRedAlerts != ib.resolvedRedAlerts`. Atualizar os construtores dos testes listados com `resolvedRedAlerts: 0` (ou o valor-base).
- [ ] **Passo 3: rodar** os três arquivos → PASS; `flutter analyze` → limpo; `flutter test` → PASS (nenhum teste antigo assume a ausência do campo).
- [ ] **Passo 4: commit**

```bash
git add apps/admin/lib/core/data apps/admin/lib/app/monitoring_controller.dart apps/admin/test
git commit -m "feat(admin): contador de concluídos e resolvedAt na camada de dados e no pulso (#87)"
```

---

### Task 6: Tela Indicadores — linha "Concluídos"

**Arquivos:**
- Modificar: `apps/admin/lib/app/app.dart:372-374`
- Criar: `apps/admin/test/indicators_resolved_test.dart`

**Interfaces:**
- Consome: `DashboardIndicators.resolvedRedAlerts` (Task 5), `ScriptedPulseDataSource.indicadores` (`test/support/scripted_pulse_data_source.dart`), `IndicatorsScreen(dataSource:, monitoring:)` e a montagem de `indicators_stale_test.dart`.

- [ ] **Passo 1: teste de widget.** Fonte `_ComContadores extends MockAdminDataSource` (molde de `_ComTmrav` em `dashboard_tmrav_test.dart`) que devolve `openRedAlerts: 1, acknowledgedRedAlerts: 1, resolvedRedAlerts: 2` e `countsByRisk[red]: 4`. Helper `bool linha(String rotulo, String valor)` = o `Padding` ancestral do rótulo contém o valor (mesma técnica de `_abertosNoPainel`).
  ```dart
  testWidgets('Indicadores mostra Abertos, Reconhecidos e Concluídos, e a soma fecha com Vermelho', …) {
    // via SinalAdminApp + entrarComCredenciais, como dashboard_tmrav_test
    expect(linha('Abertos (pendentes)', '1'), isTrue);
    expect(linha('Reconhecidos (em atendimento)', '1'), isTrue);
    expect(linha('Concluídos', '2'), isTrue);
    expect(find.text('Reconhecidos'), findsNothing, reason: 'o rótulo antigo, sem a ressalva, saiu');
    // 1 + 1 + 2 == 4, o cartão Vermelho
    expect(find.descendant(of: find.byKey(const Key('risk_counter_red')), matching: find.text('4')), findsOneWidget);
  });
  testWidgets('a linha Concluídos anda pelo pulso, sem toque (#87)', …) {
    // IndicatorsScreen com ScriptedPulseDataSource e MonitoringController(now:), como indicators_stale_test
    // pulso 1: linha('Concluídos', '0'); fonte.indicadores = …resolvedRedAlerts: 1…; ciclo de 30 s; linha('Concluídos', '1')
  });
  ```
  Rodar: `flutter test test/indicators_resolved_test.dart` → FAIL (rótulo e linha ausentes).
- [ ] **Passo 2: implementar** em `app.dart`: `_InfoRow('Reconhecidos (em atendimento)', '${data.acknowledgedRedAlerts}')`, `_InfoRow('Concluídos', '${data.resolvedRedAlerts}')` entre Reconhecidos e TMRAV; comentário de duas linhas sobre a partição (#87) e o INV-03.
- [ ] **Passo 3: rodar** o arquivo → PASS; `flutter test test/login_flow_test.dart test/text_scale_test.dart test/responsive_layout_test.dart test/touch_targets_test.dart` → PASS (uma `_InfoRow` a mais não pode estourar a 200 % de fonte nem no celular).
- [ ] **Passo 4: commit**

```bash
git add apps/admin/lib/app/app.dart apps/admin/test/indicators_resolved_test.dart
git commit -m "feat(admin): linha Concluídos no Painel de Indicadores (#87)"
```

---

### Task 7: Tela Alertas — estado "Concluído" e a hora da conclusão

**Arquivos:**
- Criar: `apps/admin/lib/app/resolved_badge.dart`
- Modificar: `apps/admin/lib/app/app.dart:277-282` (`statusLabel`) e `:766-775` (cartão)
- Criar: `apps/admin/test/alerts_resolved_test.dart`
- Modificar: `apps/admin/test/contrast_tokens_test.dart` (se o selo usar cor própria; ver passo 2)

**Interfaces:**
- Produz: `class ResolvedBadge extends StatelessWidget { const ResolvedBadge(this.resolvedAt, {super.key}); final DateTime resolvedAt; }` — texto `'Concluído às ${horaLocal(resolvedAt)}'` (`horaLocal` de `escalate_alert_dialog.dart`), ícone `Icons.check_circle_outline` + texto, nunca só cor.
- Consome: `AlertSummary.resolvedAt` (Task 5), `statusLabel`.

- [ ] **Passo 1: teste de widget** `alerts_resolved_test.dart` sobre `AlertsScreen` com `MockAdminDataSource` (molde de `montarAlertas` em `alerts_auto_refresh_test.dart`, tela alta `800×2400`):
  ```dart
  testWidgets('cartão concluído mostra "Concluído" e a hora; pendente não mostra hora', …) {
    expect(find.descendant(of: find.byKey(const Key('alert_alert-4')), matching: find.text('Status: Concluído')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('alert_alert-4')), matching: find.text('Concluído às ${horaLocal(DateTime(2026, 9, 10, 19, 40))}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('alert_alert-1')), matching: find.textContaining('Concluído às')), findsNothing);
    expect(find.text('Status: Resolvido'), findsNothing);
  });
  testWidgets('resolved sem resolvedAt mostra o estado sem a hora e não lança', …) {
    // fonte que devolve um AlertSummary(status: resolved, resolvedAt: null)
    expect(tester.takeException(), isNull);
    expect(find.text('Status: Concluído'), findsOneWidget);
    expect(find.textContaining('Concluído às'), findsNothing);
  });
  testWidgets('o filtro de status oferece "Concluído" e filtra por ele', …) {
    // abre alerts_status_filter, toca 'Concluído', espera só alert-4 e alert-6
  });
  ```
  Rodar: `flutter test test/alerts_resolved_test.dart` → FAIL (`Resolvido`, sem selo).
- [ ] **Passo 2: implementar.** `statusLabel(AlertStatus.resolved) => 'Concluído'` (o mesmo vocabulário do ACS, "Concluir atendimento", e do paciente, "Atendido"); no cartão, depois de `Text('Status: …')`: `if (alert.resolvedAt != null) ...[const SizedBox(height: 6), ResolvedBadge(alert.resolvedAt!)]` antes do bloco `escalatedAt`/`overdue` (um concluído nunca é `overdue`, o servidor decide). Cor do selo: `Colors.white70` como `EscalatedBadge`; se optar por `AdminColors.green`, usar o par `*OnSurface` e acrescentar o par em `contrast_tokens_test.dart` (regra do `apps/CLAUDE.md`). Recomendação: `white70`, sem cor clínica (verde é risco, não estado).
- [ ] **Passo 3: rodar** o arquivo, `test/alerts_screen_test.dart`, `test/overdue_red_banner_test.dart`, `test/alerts_escalate_test.dart`, `test/touch_targets_test.dart` → PASS; `flutter analyze` → limpo; `flutter test` → PASS.
- [ ] **Passo 4: commit**

```bash
git add apps/admin/lib/app/resolved_badge.dart apps/admin/lib/app/app.dart apps/admin/test
git commit -m "feat(admin): estado Concluído e hora da conclusão na lista de alertas (#87)"
```

---

### Task 8: Validação no emulador, suíte completa e documentação

**Arquivos:**
- Modificar: `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart:316` (`adminAlertIds` de 3 para 4), `backend/sinalacs_server/bin/seed_e2e_fixtures.dart:141-165` (4º alerta), `apps/admin/integration_test/admin_login_e2e.dart:196-210`
- Criar: `docs/superpowers/plans/2026-10-26-issue-87-e2e.log`
- Modificar: `PROGRESS.md` (seção nova e a linha "Aberto" da #76 em `:1671`), `apps/CLAUDE.md` (parágrafo "Admin app", a frase dos indicadores), `backend/CLAUDE.md` (bullet "TMRAV" da #40), `docs/telas-admin.md` (uma linha; captura **pendente**, nunca inventada), `CLAUDE.md` raiz (a frase "Since #44 the Alertas and Indicadores screens…" ganha "; since #87 the Indicadores screen also counts resolved red alerts")

**Interfaces:**
- Consome: Task 1 (script e teste de e2e) e tudo o que veio antes.

- [ ] **Passo 1: seed de e2e com um concluído.** 4º alerta em `E2E_SEED_ADMIN_ALERTS`: `adminAlertIds[3]`, `red`, `resolved`, `reconhecidoEmSegundos: 60`, `resolvedAt = NOW() - interval '1 hour' + 300 s` (o helper `alerta` ganha `concluidoEmSegundos`). `admin_login_e2e.dart`: Vermelho `3`, Amarelo `0` segue `findsOneWidget` só se nenhuma outra linha mostrar `0` (Abertos `1`, Reconhecidos `1`, Concluídos `1`, logo `0` continua único), TMRAV `60s`, `4` cartões, `find.text('Status: Concluído')` uma vez. Rodar `bash scripts/qa/admin_login_e2e_test.sh` → `OK`.
- [ ] **Passo 2: e2e da #87 com a correção.** Emulador ligado (Task 1, passo 4):
  `./scripts/qa/admin_concluidos_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-26-issue-87-e2e.log`
  Esperado: status 0, `E2E_PAINEL_RECONHECIDO`, `E2E_PAINEL_CONCLUIDO` (atraso ≤ 40 000 ms cada), `E2E_ALERTAS_CONCLUIDO_OK`, os quatro `igual` e a cadeia íntegra. É isto que confirma, em vez de presumir, que o pulso com `resolvedAt` (`fa549b2`) atualiza a tela: a transição `acknowledged → resolved` só move `resolvedAt` e os dois contadores, e o Painel andou sem troca de aba.
- [ ] **Passo 3: e2e do login do admin** (dados reais do painel): `./scripts/qa/admin_login_e2e.sh` → status 0.
  Depois: `docker compose up -d`.
- [ ] **Passo 4: suítes completas.** `cd backend/sinalacs_server && dart test -j 1`; `cd backend && dart analyze`; `cd apps/admin && flutter analyze && flutter test`; `bash scripts/qa/admin_concluidos_e2e_test.sh`; `graphify update .`. Tudo verde antes do próximo passo.
- [ ] **Passo 5: documentação.** `PROGRESS.md`, seção `## Contador "Concluídos" do backoffice (#87) — 2026-10-2x` com Entregue / Provas / Aberto (aberto: paginação real da lista; a linha "Concluídos" conta todo o histórico do escopo, sem janela de tempo, como "Reconhecidos"; a captura de tela do `docs/telas-admin.md`). Na seção da #76, trocar "o contador \"reconhecidos\" do backoffice … sai dele" por "resolvido na #87". Nos três `CLAUDE.md`, uma frase cada, com a partição e o INV-03.
- [ ] **Passo 6: commit e PR**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart backend/sinalacs_server/bin/seed_e2e_fixtures.dart apps/admin/integration_test/admin_login_e2e.dart docs/superpowers/plans/2026-10-26-issue-87-e2e.log PROGRESS.md CLAUDE.md apps/CLAUDE.md backend/CLAUDE.md docs/telas-admin.md graphify-out
git commit -m "docs: contador Concluídos do backoffice validado no emulador (#87)"
gh pr create --base develop --title 'feat: contador "Concluídos" no backoffice (#87)' --body '…resumo, partição, INV-03, logs de reprodução e de e2e…'
```

---

## Riscos

- **Rótulo "Reconhecidos (em atendimento)" é mudança de copy.** Nenhum teste procura "Reconhecidos" sozinho (`grep` em `apps/admin/test` e `integration_test` não acha), mas `docs/telas-admin.md` e o PRD falam em "reconhecidos": a doc acompanha na Task 8.
- **`escalated` em "Abertos" muda a semântica de `openRedAlerts` para linhas legadas.** Não há escritor desde a #44 e o teste de invariante da Task 3 fixa a decisão; se um dia o escalonamento voltar a gravar `escalated`, é o `switch` exaustivo que obriga a decidir de novo.
- **O e2e troca a stack de desenvolvimento pela de e2e** e exige o emulador `emulator-5554`; o `cleanup` devolve o banco de e2e ao zero, e `docker compose up -d` volta a de desenvolvimento. Fora da CI, como os demais `admin_*_e2e.sh`.
- **Janela de 40 s nas provas do Painel:** pulso de 30 s + folga, como no e2e da #44. Um pulso perdido por timeout de rede (20 s) faz o teste falhar sem defeito no código; o log registra o atraso medido.
