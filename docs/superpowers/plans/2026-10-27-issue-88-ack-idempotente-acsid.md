# Issue #88 — ACK repetido não reescreve o ACS do alerta — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa a tarefa. Os passos usam checkbox (`- [ ]`). **Decisão do dono registrada em 2026-10-27: opção (1), registrar sem mudar a resposta.** As Tasks 7 a 9 só começam depois das Tasks 1 a 6, que cobrem os cinco pontos pedidos junto com a decisão (seção "Ponto de decisão").

**Objetivo:** um ACK que encontra o alerta já `acknowledged` ou `resolved` deixa de reescrever `alerts.acsId` (e, por consequência, `receivedAt`/`acknowledgedAt`/`status`), continua registrando o ACS em `alert_deliveries` e segue auditado com a ação distinta que a #86 já criou; dois ACS confirmando ao mesmo tempo são decididos pelo próprio `UPDATE` condicional, e só o vencedor vira `acsId`.

**Arquitetura:** `OrmAlertStore.acknowledge` passa a decidir o desfecho pelo **resultado do `UPDATE`**: `UPDATE alerts SET … WHERE id AND "microAreaId" AND status IN ('pending','escalated') RETURNING …` — uma linha é `acknowledged`; zero linhas leva a um `SELECT … FOR UPDATE` que separa `alreadyAcknowledged`, `alreadyResolved` e inexistente (e serializa com `resolve`, que trava a mesma linha). Nos desfechos idempotentes não há escrita em `alerts`: só a linha de `alert_deliveries` (`INSERT … ON CONFLICT ("alertId","acsId") DO NOTHING`) e a auditoria, na mesma transação, fail-closed. Serviço, endpoint, modelos `.spy.yaml` e app do ACS **não mudam**.

**Tecnologias:** Serverpod 3.4.13 (Dart), PostgreSQL, `package:test` com o harness `withServerpod`, Flutter (`apps/acs`), `integration_test` no emulador, bash (`scripts/qa`).

**Spec:** issue #88 (`gh issue view 88`), origem no item adiado da #76 (PR #85). Plano anterior no mesmo método: `docs/superpowers/plans/2026-10-25-issue-86-ack-status-real.md`. Invariantes: INV-01 (territorialização), INV-03 (vermelho nunca descartado em silêncio) de `spec/PRD_system.md`; trilha append-only (#82). Continuação (opção 2 e nota sobre `resolvedBy`): issue aberta em 2026-10-27, referenciada na #88.

## Estado da #86 e base do branch (coordenação, item 1 do pedido)

Verificado em 2026-10-27: a issue #86 continua **aberta** no GitHub, mas o PR #104 (`fix/issue-86-ack-status`) está **MERGED em `develop`** (merge `faea711`, 2026-10-26; `develop` hoje em `9c6e423`, limpo). O que a #86 já entregou e este plano **reaproveita sem alterar**:

- `AlertAckOutcome {acknowledged, alreadyAcknowledged, alreadyResolved}` e `AlertAckRecord {outcome, triggeredAt, acknowledgedAt, firstAcknowledgement}` em `red_alert_service.dart`.
- `AlertStore.acknowledge({alertId, acsId, microAreaId, auditFor})` — a assinatura que a issue temia conflitar já é a final; nenhuma mudança de assinatura aqui.
- Os `result` da auditoria: `acknowledged`, `ack_already_acknowledged`, `ack_already_resolved` (+ `_mqtt`). A proposta "auditar um evento distinto (ex.: `already_acknowledged`)" da issue **já está feita** com esses nomes; este plano não cria nome novo.
- `receivedAt`/`acknowledgedAt` com `??` e `status` que não rebaixa `resolved`.

O que **continua defeituoso** (confirmado em `orm_alert_store.dart:146-162`): o `Alert.db.updateRow(... acsId: acsUuid ...)` roda em **todo** desfecho, então o ACK repetido de outro ACS troca `alerts.acsId`. E o desfecho é lido num `SELECT` anterior ao `UPDATE` (serializado pela trava, mas é o padrão que o ponto 2 do dono manda trocar).

Ordem de execução: **não há junção a fazer**; a #88 parte de `develop` e a #86 pode ser fechada no merge `develop → main`.

- [ ] `git switch develop && git pull && git switch -c fix/issue-88-ack-acsid`
- [ ] `gh pr list --state open --search "acknowledge"` → nenhum PR aberto toca `orm_alert_store.dart` (se houver, rebase sobre ele antes da Task 3).

## Restrições globais

- Português em código, comentários, mensagens, commits e documentação. Sem atribuição de IA em commits e PR (`CLAUDE.md`).
- **Nenhuma regra de transição de status muda**: `pending|escalated → acknowledged` no primeiro ACK; `acknowledged` e `resolved` ficam como estão. Nenhuma escrita em `alerts` fora do desfecho `acknowledged`.
- **O desfecho `acknowledged` sai do `UPDATE` condicional**, nunca de um `SELECT` anterior (ponto 2 do dono). O `SELECT … FOR UPDATE` só existe no caminho de zero linhas, para classificar o que já estava gravado.
- **Trilha append-only (#82)**: nada apaga ou reescreve `audit_logs`; o ACK que encontra o alerta grava **exatamente uma** linha, na mesma transação, por último (fail-closed), como hoje.
- **`alert_deliveries`** (modelo `AlertDeliveryRecord`; a issue a chama de `alert_acknowledgements`) mantém o índice único `alert_deliveries_alert_acs_key ("alertId", "acsId")` — **o par**, confirmado em `migrations/20261025212039302/definition.sql:67` (ponto 1 do dono); o `ON CONFLICT` é sobre esse par, e a violação é reentrega esperada, nunca erro.
- Sem migração e sem `.spy.yaml` novo (`serverpod generate` sem diferença).
- Testes de integração: `docker compose --profile test up -d postgres-test` e, de `backend/sinalacs_server`, `dart test -j 1 …`. Nenhum dado real; fixtures sintéticas.
- `test/unit/red_alert_discard_paths_test.dart` inventaria os escritores de `alerts` em `lib/` (regex sobre `UPDATE alerts` e `Alert.db.update*`): o store continua sendo o único escritor do ACK; não criar outro. Atualizar o texto da entrada `orm_alert_store.dart` em `_allowedWriters`.

## Matriz de casos (item 3 do pedido)

Status lido × origem do ACK → o que se grava e o que volta. "X" é o ACS que fez o ACK; "A" é o ACS já gravado em `alerts.acsId`. Vale a opção (1) aprovada.

| Status | Origem | `alerts` | `alert_deliveries` | `audit_logs` (`result`, RPC / MQTT) | `AlertAckResult` |
|---|---|---|---|---|---|
| `pending` ou `escalated` (legado) | qualquer ACS X da microárea (1º ACK, inclusive reentrega que chega primeiro) | `UPDATE` casa 1 linha: `status=acknowledged`, `acsId=X`, `receivedAt=COALESCE(receivedAt, now)`, `acknowledgedAt=COALESCE(acknowledgedAt, now)`; colunas de escalonamento intactas | insere `(alert, X)` | `acknowledged` / `acknowledged_mqtt` | `true`, `acknowledged` |
| `acknowledged` | mesmo ACS A (reentrega) | **nada** (`UPDATE` casa 0) | nada (par já existe; `ON CONFLICT DO NOTHING`) | `ack_already_acknowledged` (+`_mqtt`) | `true`, `acknowledged` |
| `acknowledged` | outro ACS X da microárea | **nada** — `acsId` segue A | insere `(alert, X)` | `ack_already_acknowledged` (+`_mqtt`), `userId = X` | `true`, `acknowledged` |
| `resolved` | mesmo ACS A | **nada** | nada | `ack_already_resolved` (+`_mqtt`) | `true`, `resolved` |
| `resolved` | outro ACS X da microárea | **nada** — `acsId` e `resolvedAt` seguem | insere `(alert, X)` | `ack_already_resolved` (+`_mqtt`), `userId = X` | `true`, `resolved` — o app marca concluído e **não** oferece "Concluir atendimento" (ponto 4) |
| qualquer | ACS de outra microárea (RPC: microárea do token; MQTT: do payload) | nada (`UPDATE` casa 0; `SELECT` vazio) | nada | **nenhuma linha** (como hoje) | `false`, `null` |

Regra única por trás da tabela: **`alerts` só é escrita pelo `UPDATE` condicional do primeiro ACK**. `alerts.acsId` passa a significar "quem confirmou primeiro" — hoje significa "quem confirmou por último". `AlertAckRecord.firstAcknowledgement` passa a ser "o `UPDATE` casou uma linha" (telemetria `alert_received_acs` uma vez por alerta, #83). Um alerta `pending` que já tenha `acsId` preenchido (os scripts de e2e inserem assim) é confirmado normalmente e `acsId` vira o ACS que confirmou: `pending` significa que ninguém confirmou.

Ponto 5 do dono, conferido: `AlertStore.resolve({alertId, microAreaId, now, auditFor})` **não recebe `acsId`** e seu `UPDATE` grava só `status` e `resolvedAt` (`orm_alert_store.dart`, comentário "Só status e resolvedAt"). Não há o mesmo defeito ali. Mas **não existe `resolvedBy`**: quem concluiu está apenas na linha `resolved` da trilha (`userId`). A Task 7 pina por teste que `resolve` por outro ACS não toca `acsId`; a coluna `resolvedBy` vai como nota na issue de continuação.

Limitação registrada, fora do escopo: o ACK por MQTT não é autenticado (`acsId`/`microAreaId` vêm do payload, aberto no `PROGRESS.md`); um payload com a microárea certa e um `acsId` inventado passa pela mesma regra.

## Auditoria (item 5 do pedido; ponto 3 do dono)

- `ack_already_acknowledged`/`ack_already_resolved` já existem na trilha desde a #86: só **acrescentam** linhas, nunca editam; casam a regex do filtro do backoffice (`^[a-z0-9_:]{1,64}$`).
- Não são mudança de status: `admin.indicators`, `acknowledgedRedAlerts`/`resolvedRedAlerts` (#87) e o TMRAV leem `alerts.status`/`acknowledgedAt`, **não** a trilha. Nada passa a contar errado.
- Consultas por `result = 'acknowledged'` são por **igualdade** (filtro do `admin.auditLogs`, scripts `acs_alert_fallback_e2e.sh`, `acs_ack_concluido_e2e.sh`): `ack_already_*` não entra nelas. O `search` do backoffice casa prefixo (`ILIKE 'x%'`): `search=ack` lista os três, `search=acknowledged` só o primeiro — em vigor desde a #86.
- **Reentrega do próprio ACS × ACK de outro ACS têm o mesmo `result`** (decisão aceita pelo dono). A distinção sai de `audit_logs.userId` (uuid) comparado a `alerts.acsId` (uuid), por `audit_logs.resourceId` (uuid). Consulta que vai para o `backend/CLAUDE.md` na Task 9:

```sql
-- ACKs repetidos feitos por um ACS diferente do responsável gravado no alerta
SELECT l.sequence, l."timestamp", l."userId" AS confirmou, a."acsId" AS responsavel, l.result
FROM audit_logs l
JOIN alerts a ON a.id = l."resourceId"
WHERE l."resourceType" = 'alert'
  AND l.result LIKE 'ack_already_%'
  AND l."userId" IS DISTINCT FROM a."acsId"
ORDER BY l.sequence;
```
  O CSV da exportação (#45) traz `autor` (matrícula) e `resultado`, mas não `alerts.acsId`: pelo CSV sozinho vê-se **quem** repetiu o ACK, não se era o responsável; a consulta acima é o caminho.
- INV-03: o ACK idempotente continua gravando a entrega e a auditoria na mesma transação; se a trilha falhar, a entrega é desfeita (Task 3 prova).

## Dados históricos (item 7 do pedido)

Hoje, um alerta confirmado por dois ACS tem `acsId` do **último**; `alert_deliveries` tem uma linha por ACS com `acknowledgedAt` de cada ACK, então **quem confirmou primeiro é reconstruível** pela linha mais antiga. Consulta de diagnóstico (vai para o `PROGRESS.md` na Task 6):

```sql
SELECT a.id, a."acsId" AS gravado, d."acsId" AS primeiro, d."acknowledgedAt"
FROM alerts a
JOIN LATERAL (SELECT "acsId", "acknowledgedAt" FROM alert_deliveries
              WHERE "alertId" = a.id ORDER BY "acknowledgedAt", id LIMIT 1) d ON true
WHERE a."acsId" IS DISTINCT FROM d."acsId";
```

Decisão: **sem correção retroativa** (registrada na #88 em 2026-10-27). O projeto é protótipo sem dado real, os volumes `pg_data/` são descartáveis (`CLAUDE.md`), `alerts` não é tabela auditada (um `UPDATE` de correção não deixaria rastro) e a reconstrução acima vale para quem precisar. Alertas inseridos por SQL nos scripts de e2e (sem linha em `alert_deliveries`) não aparecem na consulta.

## Review Focus

1. **Alerta `pending` com `acsId` já preenchido** (scripts de e2e inserem assim): o primeiro ACK de outro ACS **troca** `acsId`. Task 3, linha `pending` da matriz.
2. **Linha de `alert_deliveries` já existente para um alerta ainda `pending`**: o ACK não pode falhar na violação do índice. Task 5.
3. **Trilha falhando no caminho idempotente**: a linha de `alert_deliveries` do segundo ACS **tem** de ser desfeita. Task 3, teste fail-closed.
4. **`escalated` → primeiro ACK** precisa manter `escalatedAt`/`escalationReason`: o `UPDATE` novo lista as colunas; o teste `ACK depois do escalonamento preserva as colunas de escalonamento` já pina. Task 3 confere que segue verde.
5. **Zero linhas no `UPDATE` e `SELECT` lendo `pending`**: inalcançável em READ COMMITTED (o `UPDATE` espera a trava e reavalia o `WHERE` sobre a versão nova), então é `StateError` fail-closed, nunca um `acknowledged` inventado. Task 3, Step 3.

---

### Task 1: Reprodução no backend — o ACK de outro ACS troca `acsId`

**Files:**
- Modify: `backend/sinalacs_server/test/integration/alert_escalation_store_test.dart` (constantes, `_semear`, `limpar`, grupo `Dado o ACK do store ORM (#86)`)

**Interfaces:**
- Produces: constante `_acsB = '00000000-0000-4000-8000-0000000044e7'` (segundo ACS, `users.microAreaId = _maA`, `acs.ubsId = _ubsA`, `active = true`) semeada por `_semear` e removida por `limpar`; helper `confirmar(alertId, {ma = _maA, acs = _acs})` no grupo `#86` (parâmetro novo `acs`, que vira `acsId` e `userId` do evento).

- [ ] **Step 1: Semear o segundo ACS.** Em `_semear`, inserir `User` + `Acs` para `_acsB` ao lado do `_acs` existente (mesmos campos, `enrollmentId` distinto, ex.: `'ACS-B'`). Em `limpar` do grupo "sem rollback", incluir `_acsB` nos `deleteWhere` de `Acs` e `User`.

- [ ] **Step 2: Escrever o teste que falha**, no grupo `Dado o ACK do store ORM (#86)`:

```dart
test('ACK de outro ACS sobre alerta já confirmado não troca acsId (#88)', () async {
  final a = await alertaCom(AlertStatus.acknowledged);
  await Alert.db.updateRow(session, a.copyWith(acsId: UuidValue.fromString(_acs)));

  final r = await confirmar(a.id!.uuid, acs: _acsB);

  expect(r!.outcome, AlertAckOutcome.alreadyAcknowledged);
  final depois = (await Alert.db.findById(session, a.id!))!;
  expect(depois.acsId!.uuid, _acs, reason: 'acsId é de quem confirmou primeiro');
  expect(depois.acknowledgedAt, _t);
  expect(trilha.eventos.single.result, 'alreadyAcknowledged');
  expect(trilha.eventos.single.userId, _acsB);
});
```

- [ ] **Step 3: Rodar e ver falhar.**
Run: `cd backend/sinalacs_server && dart test -j 1 test/integration/alert_escalation_store_test.dart -N "não troca acsId"`
Expected: FAIL em `acsId é de quem confirmou primeiro` (valor `_acsB`).

- [ ] **Step 4: Commit da reprodução.**
```bash
git add backend/sinalacs_server/test/integration/alert_escalation_store_test.dart
git commit -m "test(alertas): ACK de outro ACS troca o acsId do alerta (#88, reprodução)"
```

### Task 2: Reprodução no emulador — dois ACS da mesma microárea

**Files:**
- Create: `scripts/qa/acs_ack_segundo_acs_e2e.sh` (copiar a anatomia de `scripts/qa/acs_ack_concluido_e2e.sh`)
- Create: `scripts/qa/acs_ack_segundo_acs_e2e_test.sh` (guarda de estrutura, como `acs_ack_concluido_e2e_test.sh`)
- Create: `apps/acs/integration_test/ack_by_second_acs_e2e.dart` (copiar `ack_after_resolved_e2e.dart`)

**Interfaces:**
- Consumes: `secondAcsCredentialFromRelay()` de `integration_test/support/e2e_acs.dart` (relé `/acs-b`, bloco `acsB` do manifesto, mesma microárea); `fx "d['acs']['id']"` (ACS A) e `fx "d['acsB']['id']"` (ACS B) no script.
- Produces: marcadores `E2E_DISPARAR_ALERTA id=<uuid>`, `E2E_CONFIRMAR_NO_APARELHO_A id=<uuid>`, `E2E_ACK_B_OK`; o script falha antes da correção na asserção `acsId segue o ACS A`.

- [ ] **Step 1: Teste de integração.** O aparelho entra como **ACS B** (`secondAcsCredentialFromRelay()`), espera `alert_fallback_status` (broker fora do alcance, como na #86), imprime `E2E_DISPARAR_ALERTA`, espera o cartão `alert_$id`, imprime `E2E_CONFIRMAR_NO_APARELHO_A`, espera 6 s (menos que o tique de 30 s da reserva, para o cartão ainda oferecer o ACK), toca "Confirmar recebimento" e afirma (teto 20 s): texto `Recebimento confirmado à central.` presente, `Key('resolve_$id')` presente (opção 1: o cartão vai a confirmado e oferece concluir), `Key('resolved_$id')` ausente. Imprime `E2E_ACK_B_OK`. Falha com mensagem própria se aparecer `A central não reconheceu este alerta.`.

- [ ] **Step 2: Script.** Igual ao da #86 até o `inserir_alerta`, com duas diferenças: o `INSERT` em `alerts` vai com `"acsId" = NULL`; e o marcador `E2E_CONFIRMAR_NO_APARELHO_A` executa, numa transação:
```sql
update alerts set status = 'acknowledged', "acsId" = '<acs_id A>', "receivedAt" = NOW(), "acknowledgedAt" = NOW() where id = '<id>' and status = 'pending';
insert into alert_deliveries ("alertId", "acsId", "acknowledgedAt") values ('<id>', '<acs_id A>', NOW());
```
e guarda `acknowledgedAt` em variável para comparar depois. Asserções no banco ao fim (`igual`), depois de exigir `E2E_ACK_B_OK` na saída:
  - `acsId segue o ACS A`: `select "acsId" from alerts where id = …` = `$acs_id` — **falha antes da correção** (vem `$acs_b_id`).
  - `acknowledgedAt não mudou`: igual ao valor guardado.
  - `status`: `acknowledged`.
  - `duas entregas (A e B)`: `select count(*) from alert_deliveries where "alertId" = …` = 2, e `select count(*) … and "acsId" = '$acs_b_id'` = 1.
  - `uma linha ack_already_acknowledged do ACS B`: `… where "resourceId" = … and result = 'ack_already_acknowledged' and "userId" = '$acs_b_id'` = 1.
  - `nenhuma linha acknowledged`: 0.
  - `nada no alert_outbox`: 0.

- [ ] **Step 3: Guarda de estrutura.** `acs_ack_segundo_acs_e2e_test.sh` confere, por `grep -qF`, os três marcadores, o `"acsId" = NULL` do insert, a asserção `result = 'ack_already_acknowledged'`, a contagem por `"acsId" = '$acs_b_id'` em `alert_deliveries` e o `d.pop('acsB',None)` do manifesto (senhas nunca no argv). Run: `bash scripts/qa/acs_ack_segundo_acs_e2e_test.sh` → `OK`.

- [ ] **Step 4: Rodar no emulador antes da correção** (AVD `sinalacs_ci36`; sobe **com janela**, `~/Android/Sdk/emulator/emulator -avd sinalacs_ci36`; `adb devices` mostra `emulator-5554`):
Run: `./scripts/qa/acs_ack_segundo_acs_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-27-issue-88-reproducao.log`
Expected: a tela passa (a resposta hoje já é `acknowledged`), e o banco falha em `erro: esperado '<acs A>' (acsId segue o ACS A)`, saída 1. Ao final o script derruba a stack de e2e; `docker compose up -d` devolve a de desenvolvimento.

- [ ] **Step 5: Commit.**
```bash
git add scripts/qa/acs_ack_segundo_acs_e2e.sh scripts/qa/acs_ack_segundo_acs_e2e_test.sh apps/acs/integration_test/ack_by_second_acs_e2e.dart docs/superpowers/plans/2026-10-27-issue-88-reproducao.log
git commit -m "test(e2e): ACK do ACS B sobre alerta confirmado pelo A (#88, reprodução)"
```

### Task 3: Desfecho pelo `UPDATE` condicional; `alerts` só no primeiro ACK

**Files:**
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart` (corpo de `run` em `acknowledge`, linhas 118-185)
- Modify: `backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart` (texto da entrada `orm_alert_store.dart` em `_allowedWriters`)
- Test: `backend/sinalacs_server/test/integration/alert_escalation_store_test.dart` (grupo `#86`)

**Interfaces:**
- Consumes: `AlertAckOutcome`, `AlertAckRecord` (inalterados).
- Produces: `acknowledge` com este fluxo, todo dentro de `run(transaction)`:
  1. `UPDATE alerts SET status = @ack, "acsId" = @acs::uuid, "receivedAt" = COALESCE("receivedAt", @now::timestamp), "acknowledgedAt" = COALESCE("acknowledgedAt", @now::timestamp) WHERE id = @id::uuid AND "microAreaId" = @ma::uuid AND status IN (@pending, @escalated) RETURNING "triggeredAt", "acknowledgedAt"` via `session.db.unsafeQuery` (parâmetros nomeados: os nomes de status vêm de `AlertStatus.x.name`, nunca de literal duplicado).
  2. Uma linha → `outcome = acknowledged`, `firstAcknowledgement = true`, `triggeredAt`/`acknowledgedAt` do `RETURNING`.
  3. Zero linhas → `SELECT status, "triggeredAt", "acknowledgedAt" FROM alerts WHERE id = @id::uuid AND "microAreaId" = @ma::uuid FOR UPDATE`. Vazio → `return null` (sem entrega, sem auditoria). `resolved` → `alreadyResolved`; `acknowledged` → `alreadyAcknowledged`; `pending`/`escalated` → `throw StateError('alerta ainda pendente depois do UPDATE condicional sem efeito (#88)')` (Review Focus 5). `firstAcknowledgement = false`.
  4. Entrega (hoje `findFirstRow` + `insertRow`; a Task 5 troca por `ON CONFLICT`), auditoria por último, `AlertAckRecord`.
  Os ids inválidos (não UUID) continuam chegando como hoje (o serviço não os filtra; `::uuid` falha como antes) — não mudar.

- [ ] **Step 1: Testes que falham**, no grupo `#86`:

```dart
test('matriz #88: só pending/escalated escrevem alerts; acsId/receivedAt/acknowledgedAt preservados', () async {
  const matriz = <(AlertStatus, String /*acsId esperado*/)>[
    (AlertStatus.pending, _acsB), (AlertStatus.escalated, _acsB),
    (AlertStatus.acknowledged, _acs), (AlertStatus.resolved, _acs),
  ];
  for (final (lido, esperado) in matriz) {
    final a = await alertaCom(lido);
    final semeado = await Alert.db.updateRow(session, a.copyWith(
      acsId: UuidValue.fromString(_acs), receivedAt: _t));
    final r = await confirmar(a.id!.uuid, acs: _acsB);
    final depois = (await Alert.db.findById(session, a.id!))!;
    expect(depois.acsId!.uuid, esperado, reason: '$lido');
    expect(depois.receivedAt, _t, reason: '$lido');
    if (lido == AlertStatus.acknowledged || lido == AlertStatus.resolved) {
      expect(depois.acknowledgedAt, semeado.acknowledgedAt, reason: '$lido');
      expect(r!.acknowledgedAt, semeado.acknowledgedAt, reason: '$lido');
      expect(r.firstAcknowledgement, isFalse, reason: '$lido');
    } else {
      expect(r!.firstAcknowledgement, isTrue, reason: '$lido');
      expect(depois.acknowledgedAt, r.acknowledgedAt, reason: '$lido');
    }
  }
});

test('ACK repetido pelo mesmo ACS não escreve alerts nem duplica a entrega', () async {
  final a = await alertaCom(AlertStatus.acknowledged);
  await Alert.db.updateRow(session, a.copyWith(acsId: UuidValue.fromString(_acs)));
  await confirmar(a.id!.uuid); // _acs
  final entregas = await AlertDeliveryRecord.db.find(session, where: (t) => t.alertId.equals(a.id!));
  expect(entregas, hasLength(1));
  expect(entregas.single.acsId.uuid, _acs);
});

test('entrega do segundo ACS é registrada e desfeita se a trilha falhar (fail-closed)', () async {
  final a = await alertaCom(AlertStatus.acknowledged);
  await Alert.db.updateRow(session, a.copyWith(acsId: UuidValue.fromString(_acs)));
  final falha = OrmAlertStore(session: () => session, appendAudit: (s, t, e) async => throw StateError('trilha fora'));
  await expectLater(falha.acknowledge(alertId: a.id!.uuid, acsId: _acsB, microAreaId: _maA,
      auditFor: (o) => AuditEvent(userId: _acsB, actionType: 'write', resourceType: 'alert', resourceId: a.id!.uuid, result: o.name)),
    throwsStateError);
  expect(await AlertDeliveryRecord.db.count(session, where: (t) => t.alertId.equals(a.id!) & t.acsId.equals(UuidValue.fromString(_acsB))), 0);
});
```

- [ ] **Step 2: Rodar e ver falhar.**
Run: `dart test -j 1 test/integration/alert_escalation_store_test.dart -N "#88"`
Expected: a matriz falha em `acknowledged`/`resolved` (`acsId` = `_acsB`); o fail-closed pode já passar (a transação desfaz tudo hoje) — se passar, fica como guarda.

- [ ] **Step 3: Implementar** o fluxo da seção Interfaces em `orm_alert_store.dart`, removendo o `SELECT id … FOR UPDATE` inicial, o `findById`, o `switch` sobre `alert.status` e o `Alert.db.updateRow`. Comentário de cabeçalho: "o desfecho é o resultado do `UPDATE` condicional, não de uma leitura anterior (#88); o `SELECT … FOR UPDATE` do caminho vazio serializa com `resolve` e o escalonamento, que travam a mesma linha". Ajustar o texto de `_allowedWriters['infrastructure/database/orm_alert_store.dart']` em `red_alert_discard_paths_test.dart` para "acknowledge() leva pending/escalated a acknowledged por UPDATE condicional e nunca escreve alerts nos desfechos repetidos (#88)".

- [ ] **Step 4: Rodar o arquivo inteiro e a suíte de unidade.**
Run: `dart test -j 1 test/integration/alert_escalation_store_test.dart && dart test test/unit`
Expected: PASS, inclusive `ACK depois do escalonamento preserva as colunas de escalonamento`, a matriz da #86, `ACK e conclusão simultâneos (#86)` (o `FOR UPDATE` do caminho vazio é o que mantém a ordem da trilha = ordem da trava) e `red_alert_discard_paths_test.dart`.

- [ ] **Step 5: Commit.**
```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart backend/sinalacs_server/test/integration/alert_escalation_store_test.dart backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart
git commit -m "fix(alertas): ACK decide o desfecho pelo UPDATE condicional e não reescreve acsId (#88)"
```

### Task 4: Corrida — dois ACS confirmam o mesmo `pending` ao mesmo tempo

**Files:**
- Test: `backend/sinalacs_server/test/integration/alert_escalation_store_test.dart`, grupo `Dado o store ORM do escalonamento (#44), sem rollback (corrida)` (ao lado de `ACK e conclusão simultâneos`)

- [ ] **Step 1: Teste** (5 rodadas, como os vizinhos; `limpar` já remove `_acsB` desde a Task 1):

```dart
test('dois ACS confirmam o mesmo pendente: o UPDATE que casa vira acsId, o outro é idempotente (#88)', () async {
  // por rodada: a = await _alerta(s); trilha única; novo() como no teste vizinho
  final r = await Future.wait([
    novo().acknowledge(alertId: a.id!.uuid, acsId: _acs,  microAreaId: _maA, auditFor: (o) => evento(_acs,  'ack:${o.name}')),
    novo().acknowledge(alertId: a.id!.uuid, acsId: _acsB, microAreaId: _maA, auditFor: (o) => evento(_acsB, 'ack:${o.name}')),
  ]);
  final desfechos = r.map((x) => x!.outcome).toList();
  expect(desfechos.where((o) => o == AlertAckOutcome.acknowledged), hasLength(1));
  expect(desfechos.where((o) => o == AlertAckOutcome.alreadyAcknowledged), hasLength(1));
  final vencedor = trilha.eventos.first.userId;           // a trilha é gravada sob a trava: ordem = ordem da trava
  expect(trilha.eventos.first.result, 'ack:acknowledged');
  expect(trilha.eventos.last.result, 'ack:alreadyAcknowledged');
  final lido = (await Alert.db.findById(s, a.id!))!;
  expect(lido.acsId!.uuid, vencedor);
  expect(lido.status, AlertStatus.acknowledged);
  expect(r[0]!.acknowledgedAt, r[1]!.acknowledgedAt);     // os dois devolvem o carimbo do vencedor
  expect(r.where((x) => x!.firstAcknowledgement), hasLength(1));
  expect(await AlertDeliveryRecord.db.count(s, where: (t) => t.alertId.equals(a.id!)), 2);
});
```
(`evento` ganha o parâmetro `userId`; os eventos do teste vizinho passam `_acs`.)

- [ ] **Step 2: Rodar.**
Run: `dart test -j 1 test/integration/alert_escalation_store_test.dart -N "dois ACS confirmam"`
Expected: PASS. Se `acknowledgedAt` divergir, o perdedor não está lendo sob `FOR UPDATE` depois do `UPDATE` vazio — rever o Step 3 da Task 3.

- [ ] **Step 3: Commit.**
```bash
git add backend/sinalacs_server/test/integration/alert_escalation_store_test.dart
git commit -m "test(alertas): corrida de dois ACS no mesmo alerta pendente (#88)"
```

### Task 5: Entrega idempotente por `ON CONFLICT` sobre o par `(alertId, acsId)`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart` (bloco `already`/`AlertDeliveryRecord.db.insertRow`)
- Test: `backend/sinalacs_server/test/integration/alert_escalation_store_test.dart` (grupo `#86`)

**Interfaces:**
- Produces: a inserção em `alert_deliveries` vira `session.db.unsafeExecute` com `INSERT INTO alert_deliveries ("alertId","acsId","acknowledgedAt") VALUES (@alert::uuid, @acs::uuid, @now::timestamp) ON CONFLICT ("alertId","acsId") DO NOTHING`, dentro da mesma `transaction`; o `findFirstRow` prévio some.

- [ ] **Step 1: Testes** (ponto 1 do dono: a chave é o par, e o segundo ACS **entra**):

```dart
test('o índice único de alert_deliveries é sobre o par (alertId, acsId) (#88)', () async {
  final linhas = await session.db.unsafeQuery(
    "SELECT indexdef FROM pg_indexes WHERE tablename = 'alert_deliveries' AND indexname = 'alert_deliveries_alert_acs_key'");
  final def = linhas.single[0] as String;
  expect(def, contains('UNIQUE INDEX'));
  expect(def, contains('("alertId", "acsId")'));
});

test('a reentrega não duplica e o segundo ACS entra: um par por ACS', () async {
  final a = await alertaCom(AlertStatus.acknowledged);
  await confirmar(a.id!.uuid);               // A, reentrega
  await confirmar(a.id!.uuid, acs: _acsB);   // B
  await confirmar(a.id!.uuid, acs: _acsB);   // B, reentrega
  final entregas = await AlertDeliveryRecord.db.find(session, where: (t) => t.alertId.equals(a.id!));
  expect(entregas.map((e) => e.acsId.uuid).toSet(), {_acs, _acsB});
  expect(entregas, hasLength(2));
});

test('entrega já registrada para alerta ainda pending: o ACK não falha e não duplica', () async {
  final a = await _alerta(session);
  await AlertDeliveryRecord.db.insertRow(session, AlertDeliveryRecord(
    alertId: a.id!, acsId: UuidValue.fromString(_acs), acknowledgedAt: _t));
  final r = await confirmar(a.id!.uuid);
  expect(r!.outcome, AlertAckOutcome.acknowledged);
  final entregas = await AlertDeliveryRecord.db.find(session, where: (t) => t.alertId.equals(a.id!));
  expect(entregas, hasLength(1));
  expect(entregas.single.acknowledgedAt, _t, reason: 'a primeira entrega não é reescrita');
});
```
(O helper `confirmar` do grupo `#86` precisa semear `alertaCom(AlertStatus.acknowledged)` com `acsId = _acs`, como na Task 1; se ainda não faz, ajustar `alertaCom` para gravar `acsId` quando o status não é `pending`.)

- [ ] **Step 2: Rodar.** Run: `dart test -j 1 test/integration/alert_escalation_store_test.dart -N "alert_deliveries|um par por ACS|ainda pending"` → PASS já com o `findFirstRow` atual; os testes existem para a troca não regredir.

- [ ] **Step 3: Trocar** o par `findFirstRow` + `insertRow` pelo `unsafeExecute` acima (comentário: "reentrega é caso esperado: o índice único do par decide, não uma leitura prévia (#88)"). `id` fica com o `DEFAULT gen_random_uuid()` da tabela.

- [ ] **Step 4: Rodar o arquivo e a suíte do backend.**
Run: `dart test -j 1`
Expected: PASS (inclui `red_alert_cycle_test.dart`, `red_alert_discard_paths_db_test.dart` e os testes da #76/#86).

- [ ] **Step 5: Commit.**
```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart backend/sinalacs_server/test/integration/alert_escalation_store_test.dart
git commit -m "fix(alertas): entrega do ACK idempotente por ON CONFLICT no par (alertId, acsId) (#88)"
```

### Task 6: Dados históricos — registro, sem correção retroativa

**Files:**
- Modify: `PROGRESS.md` (seção nova "ACK repetido e `acsId` (#88)", logo acima de "ACK de alerta já concluído (#86)"; e na seção da #86, remover do "Aberto" a frase "um ACK sobre alerta já confirmado ou concluído continua regravando `acsId` …")

- [ ] **Step 1: Escrever a seção** com: o que mudou (`alerts.acsId` = primeiro ACS; desfecho pelo `UPDATE` condicional; `alerts` não é escrita no ACK repetido), a consulta de diagnóstico da seção "Dados históricos" deste plano, a decisão "sem correção retroativa" (já registrada na #88 em 2026-10-27) e o motivo, a limitação do ACK por MQTT sem autenticação, e a referência à issue de continuação (opção 2 e `resolvedBy`).
- [ ] **Step 2: Commit.** `git commit -am "docs: #88, dados históricos sem correção retroativa e reconstrução por alert_deliveries"`

---

## Ponto de decisão (item 4 do pedido) — resolvido em 2026-10-27

**Aprovada a opção (1): registrar, resposta igual.** `acsId` fica com o primeiro ACS, o segundo entra em `alert_deliveries`, auditoria `ack_already_acknowledged` com o `userId` dele, resposta `true`/`acknowledged`, app mostra "Recebimento confirmado à central." e oferece concluir. A opção (2) — campo `acknowledgedByOther` e aviso "Outro ACS já confirmou" — foi para a issue de continuação (mudança de contrato, não pega carona numa correção de integridade). A opção (3), recusar, foi descartada.

Condições do dono, todas cobertas antes das Tasks 7 a 9: (1) chave do `ON CONFLICT` é o par → Task 5; (2) desfecho vem do `UPDATE`, não de `SELECT` anterior → Task 3 + Task 4; (3) consulta que distingue reentrega própria de ACK de outro ACS → seção "Auditoria" e Task 9; (4) `ack_already_resolved` não oferece concluir → provado por `apps/acs/test/alert_resolve_test.dart` ("ACK de alerta já concluído em outro aparelho marca concluído e não oferece Concluir atendimento (#86)", `resolve_alerta-1` ausente) e por `scripts/qa/acs_ack_concluido_e2e.sh`, reexecutados na Task 8; (5) `resolve` não sobrescreve `acsId` → teste de regressão na Task 7, `resolvedBy` na issue de continuação.

Para as três opções descartadas/adiadas, a tabela comparativa fica no histórico desta seção no git (commit do plano de 2026-10-27).

---

### Task 7: Semântica do segundo ACS e do `resolve` cobertas por teste

**Files:**
- Test: `backend/sinalacs_server/test/unit/red_alert_service_test.dart` (grupo do `acknowledge`)
- Test: `backend/sinalacs_server/test/integration/alert_escalation_store_test.dart` (grupo `#86`)

- [ ] **Step 1: Teste de unidade do serviço** (o `FakeAlertStore` já deduplica por `alertId`; só falta o par de usuários):

```dart
test('ACK de outro ACS sobre alerta já confirmado é idempotente e audita com o userId dele (#88)', () async {
  final store = FakeAlertStore();
  final service = RedAlertService(store: store, outbox: FakeAlertOutbox());
  const a = AuthenticatedUser(id: 'acs-a', role: UserRole.acs, microAreaId: 'area-1', deviceId: 'd-a');
  const b = AuthenticatedUser(id: 'acs-b', role: UserRole.acs, microAreaId: 'area-1', deviceId: 'd-b');
  await service.acknowledge(user: a, alertId: 'alerta-1');
  final status = await service.acknowledge(user: b, alertId: 'alerta-1');
  expect(status, AlertStatus.acknowledged);
  expect(store.audits.map((e) => (e.userId, e.result)).toList(),
      [('acs-a', 'acknowledged'), ('acs-b', 'ack_already_acknowledged')]);
});
```
Run: `dart test test/unit/red_alert_service_test.dart -N "outro ACS"` → PASS (pina a decisão).

- [ ] **Step 2: Testes do store** no grupo `#86`:
  - `ACK de outro ACS sobre resolved: acsId e resolvedAt intactos, entrega registrada, alreadyResolved` (mesma forma da Task 1 com `alertaCom(AlertStatus.resolved)`; espera `entregas` com `_acsB`, `depois.acsId == _acs`, `depois.resolvedAt == _t`, `r.status == AlertStatus.resolved`).
  - **Ponto 5:** `resolve por outro ACS não toca acsId (#88, regressão)`: `alertaCom(AlertStatus.acknowledged)` com `acsId = _acs`; `store.resolve(alertId, microAreaId: _maA, now: _t, auditFor: (o) => AuditEvent(userId: _acsB, …, result: o.name))` → `outcome == resolved`; `depois.acsId.uuid == _acs`; `depois.resolvedAt == _t`; `trilha.eventos.single.userId == _acsB` (a trilha é o único registro de quem concluiu — não há `resolvedBy`).
Run: `dart test -j 1 test/integration/alert_escalation_store_test.dart -N "sobre resolved|não toca acsId"` → PASS.

- [ ] **Step 3: Commit.**
```bash
git add backend/sinalacs_server/test
git commit -m "test(alertas): segundo ACS é registrado sem trocar o responsável; resolve não toca acsId (#88)"
```

### Task 8: Validação no emulador e suíte completa

**Files:**
- Create: `docs/superpowers/plans/2026-10-27-issue-88-e2e.log`

- [ ] **Step 1: Backend inteiro.** Run: `cd backend && dart analyze && cd sinalacs_server && dart test -j 1` → PASS, contagem anotada no log.
- [ ] **Step 2: App do ACS.** Run: `cd apps/acs && flutter analyze && flutter test` → PASS (nada mudou no app; prova de não regressão, inclui o teste do ponto 4).
- [ ] **Step 3: E2E da #88 depois da correção.** Run: `./scripts/qa/acs_ack_segundo_acs_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-27-issue-88-e2e.log` → `OK: …`, saída 0, e as asserções do banco impressas.
- [ ] **Step 4: E2E da #86 segue verde (ponto 4 no emulador).** Run: `./scripts/qa/acs_ack_concluido_e2e.sh` → `OK` ("a tela não ofereceu Concluir atendimento"). Opcional: `./scripts/qa/acs_alert_fallback_e2e.sh` (confere `result = 'acknowledged'` = 1 no primeiro ACK).
- [ ] **Step 5: `docker compose up -d`** para devolver a stack de desenvolvimento; commit do log: `git add docs/superpowers/plans/2026-10-27-issue-88-e2e.log && git commit -m "docs: #88 validada no emulador com dois ACS"`

### Task 9: Documentação, grafo e PR

**Files:**
- Modify: `backend/CLAUDE.md` (parágrafo "ACK e expurgo" da seção #44: acrescentar "desde a #88 o desfecho do ACK é o resultado do `UPDATE` condicional (`status IN (pending, escalated)`), `alerts` só é escrita no primeiro ACK — `acsId` é quem confirmou primeiro —, a entrega é idempotente por `ON CONFLICT` no par `(alertId, acsId)`, e a reentrega do próprio ACS e o ACK de outro ACS têm o **mesmo** `result`: distinguem-se por `audit_logs.userId` × `alerts.acsId`" + a consulta SQL da seção "Auditoria" deste plano, com a observação sobre o CSV da #45)
- Modify: `CLAUDE.md` raiz (frase de `alerts.acknowledge` na lista de endpoints: "`acsId` é o primeiro ACS, #88")
- Modify: `PROGRESS.md` (seção da Task 6: adicionar provas, a decisão (1) e a referência à issue de continuação)
- Modify: `docs/superpowers/plans/2026-10-27-issue-88-ack-idempotente-acsid.md` (checkboxes)

- [ ] **Step 1: Editar os três documentos.** Nada de contagem de testes inventada: copiar a do log da Task 8.
- [ ] **Step 2: `graphify update .`** (regra do `CLAUDE.md`).
- [ ] **Step 3: Commit e PR contra `develop`.**
```bash
git add -A && git commit -m "docs(alertas): ACK repetido não reescreve o responsável; consulta de distinção na trilha (#88)"
git push -u origin fix/issue-88-ack-acsid
gh pr create --base develop --title "fix(alertas): ACK repetido não reescreve o ACS responsável (#88)" --body-file <corpo com: o que mudou, matriz, decisão (1), os cinco pontos e onde cada um é provado, logs; sem atribuição de IA>
```
- [ ] **Step 4: Checks obrigatórios verdes** (`./scripts/qa/ci_invariants.sh --checks-obrigatorios` lista os 8); `android-e2e` informativo.

## Critérios de aceite (espelho da issue)

- [ ] ACK em alerta `acknowledged` ou `resolved` não altera `acsId`, `receivedAt` nem `acknowledgedAt` — Tasks 1, 3 (matriz), 7.
- [ ] O ACK repetido gera auditoria com a ação distinta, nunca `acknowledged` — já desde a #86; pinado pelas Tasks 1, 3, 4 e pelo e2e.
- [ ] `alert_deliveries` registra cada ACS que confirmou, sem duplicar em reentregas — Tasks 3, 4, 5.
- [ ] Decisão sobre o segundo ACS registrada na issue e coberta por teste — comentário de 2026-10-27 na #88 + Task 7.
- [ ] Suíte existente (incluindo #76 e #86) continua passando e o cenário com dois ACS é validado no emulador — Task 8.
