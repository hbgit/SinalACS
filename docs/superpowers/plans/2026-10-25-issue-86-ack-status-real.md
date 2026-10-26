# Issue #86 — ACK devolve o status real do alerta — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** `alerts.acknowledge` passa a devolver em `AlertAckResult.status` o status lido sob a trava da linha (`resolved` quando o atendimento já foi concluído), e o app do ACS, ao receber `resolved`, marca o cartão como concluído em vez de mostrar de novo "Concluir atendimento".

**Arquitetura:** `OrmAlertStore.acknowledge` já trava a linha (`SELECT … FOR UPDATE`, #76) e já lê o alerta antes do `UPDATE`. Ele passa a classificar o ACK num desfecho (`AlertAckOutcome`) a partir do status lido, a devolvê-lo em `AlertAckRecord` e a pedir o evento de auditoria por desfecho (`auditFor`, mesmo padrão do `resolve`). `RedAlertService.acknowledge` devolve `AlertStatus?` (nulo = não encontrado), o endpoint repassa esse valor e o app do ACS decide entre `markResolved` e `markAcknowledged`. O status gravado não muda em nenhum caso.

**Tecnologias:** Serverpod 3.4.13 (Dart), PostgreSQL, Flutter (`apps/acs`), `package:test` com o harness `withServerpod`, `flutter_test`, `integration_test` no emulador.

**Spec:** issue #86 (`gh issue view 86`), origem no item adiado da #76 (PR #85, plano `docs/superpowers/plans/2026-10-16-issue-76-alerta-atendido.md`). Requisito: RF05 de `spec/PRD_system.md`. Decisão do dono sobre a auditoria (2026-10-25): **continua uma linha por ACK** (decisão da #44), mas o ACK que não muda o status grava um `result` que diz isso.

## Base do branch (antes da Task 1)

O PR #98 (#83, telemetria) **ainda não foi mergeado** e já trocou o retorno de `AlertStore.acknowledge` de `bool` para `AlertAckRecord?` (com `firstAcknowledgement`). No `develop` (7583818) o retorno continua `bool`. Este plano parte da assinatura do #98, porque partir do `develop` daria conflito garantido no mesmo método.

- [ ] `gh pr view 98 --json state` → se `MERGED`: `git switch develop && git pull && git switch -c fix/issue-86-ack-status`. Se ainda `OPEN`: `git switch -c fix/issue-86-ack-status feat/issue-83-telemetria`, e o PR da #86 só vai depois do #98 (rebase em `develop` nessa hora).
- [ ] A reprodução (Task 1) roda nesse ponto de partida, antes de qualquer correção. O defeito é o mesmo no `develop` e no #98: os dois têm `status: acknowledged ? AlertStatus.acknowledged : null` em `alerts_endpoint.dart`.

## Restrições globais

- Português em código, comentários, mensagens e documentação, como o resto do repositório.
- **Não alterar o status persistido**: o `UPDATE` do ACK continua idêntico (mesmas colunas: `acsId`, `receivedAt`, `acknowledgedAt`, `status`; `resolved` continua `resolved`).
- **INV-03**: o ACK que encontra o alerta grava exatamente uma linha de auditoria, na mesma transação, por último (fail-closed). Um ACK que não muda o status **não** grava `acknowledged`/`acknowledged_mqtt`.
- `result` da auditoria do ACK (fixado aqui; distinto de `already_resolved`, que é do `resolve` e já existe na trilha):

  | Desfecho | RPC | MQTT |
  |---|---|---|
  | `acknowledged` (mudou para `acknowledged`) | `acknowledged` | `acknowledged_mqtt` |
  | `alreadyAcknowledged` | `ack_already_acknowledged` | `ack_already_acknowledged_mqtt` |
  | `alreadyResolved` | `ack_already_resolved` | `ack_already_resolved_mqtt` |

- Nenhum `.spy.yaml` muda: `AlertAckResult.status` já é `AlertStatus?` e o enum já tem `resolved`. Sem `serverpod generate` com diferença e sem migração.
- Testes de integração: `docker compose --profile test up -d postgres-test` e `dart test -j 1`.
- Nenhum dado real; fixtures sintéticas.
- Sem atribuição de IA em commits e PR (regra do `CLAUDE.md`).

## Matriz de estados do ACK

Status lido sob `FOR UPDATE` → o que se grava, o que se devolve e o que se audita:

| Status lido | Status gravado | `AlertAckOutcome` | `AlertAckResult` (`acknowledged`, `status`) | `result` da auditoria (RPC) |
|---|---|---|---|---|
| `pending` | `acknowledged` | `acknowledged` | `true`, `acknowledged` | `acknowledged` |
| `escalated` (legado, anterior à #44) | `acknowledged` | `acknowledged` | `true`, `acknowledged` | `acknowledged` |
| `acknowledged` (ACK repetido) | `acknowledged` (igual) | `alreadyAcknowledged` | `true`, `acknowledged` | `ack_already_acknowledged` |
| `resolved` | `resolved` (igual) | `alreadyResolved` | `true`, **`resolved`** | `ack_already_resolved` |
| inexistente, de outra microárea ou id que não é UUID | nada | — (`null`) | `false`, `null` | nenhuma linha |

`firstAcknowledgement` (telemetria #83) não muda: continua `acknowledgedAt == null` lido sob a trava, independente do desfecho.

## Mapa de impacto da mudança de assinatura

**Implementações de `AlertStore`** (todas quebram com `audit:` → `auditFor:` e com o campo novo de `AlertAckRecord`):
- `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart:106` — `OrmAlertStore` (produção)
- `backend/sinalacs_server/test/unit/red_alert_service_test.dart:18` — `FakeAlertStore`, e `_NotFoundAckStore` (`:626`)
- `backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart:87` — `_MemoryStore`
- `backend/sinalacs_server/test/unit/red_alert_lifecycle_test.dart:16` — `RecordingStore`

**Quem chama `AlertStore.acknowledge` diretamente:**
- `lib/src/application/alerts/red_alert_service.dart:315` — `RedAlertService.acknowledge`
- `test/integration/alert_escalation_store_test.dart:525-555` (dois testes: trilha falhando, ACK depois do escalonamento)
- `test/integration/red_alert_discard_paths_db_test.dart:183`

**Quem chama `RedAlertService.acknowledge`** (quebra com `bool` → `AlertStatus?` na Task 3):
- `lib/src/endpoints/alerts_endpoint.dart:84`
- `lib/server.dart:208` — callback do ACK por MQTT (só registra em log)
- `test/unit/red_alert_service_test.dart:439,464,553,607,620`; `test/unit/red_alert_lifecycle_test.dart:156`; `test/unit/red_alert_discard_paths_test.dart:339`; `test/integration/red_alert_discard_paths_db_test.dart:215`

**Quem consome `AlertAckResult`** (não quebra a compilação, muda o comportamento na Task 4):
- `apps/acs/lib/app/app.dart:2136` — `_acknowledge`
- `apps/acs/test/support/fakes.dart:241` — `FakeAcsBackend.acknowledge`
- `apps/acs/lib/core/network/backend_client.dart:833` e `apps/acs/integration_test/support/envio_fora_do_ar.dart:64` só repassam, sem mudança.

**Quem lê o `result` `acknowledged` da trilha:** `scripts/qa/acs_alert_fallback_e2e.sh:134` (primeiro ACK de um `pending`: continua `acknowledged`, sem mudança). Nada em `lib/` ou em `apps/admin` compara esse texto. O TMRAV e o pulso leem colunas de `alerts`, não a trilha.

## Pontos de atenção na revisão

1. **ACK e conclusão no mesmo instante, no mesmo alerta**: o status devolvido precisa ser o da linha travada, nunca um palpite. Coberto pelo teste de corrida da Task 2 (o ACK devolve `resolved` se e só se a linha do `resolve` vem antes da sua na trilha).
2. **Cartão recebido pela reserva HTTP ou pelo MQTT no aparelho B como `pending`, quando o alerta já foi concluído**: a reserva (`openForMicroArea`) não devolve `resolved`, então o aparelho B só descobre a conclusão pelo ACK. Coberto pela Task 4 (widget) e pela Task 5 (emulador).
3. **Servidor antigo** (sem esta correção) **ou resposta com `status` nulo e `acknowledged: true`**: o app precisa continuar marcando como confirmado. Teste na Task 4.
4. **ACK repetido de um alerta já confirmado**: devolve `acknowledged`, não grava `acknowledged` de novo na trilha e não emite telemetria. Coberto pela Task 2 (matriz) e pela Task 3 (unitário).
5. **ACK por MQTT de um alerta concluído**: mesmo desfecho, com o sufixo `_mqtt`. Coberto pela Task 3.

---

### Task 1: Reprodução — roteiro no emulador do aparelho B (falha antes da correção)

**Arquivos:**
- Criar: `apps/acs/integration_test/ack_after_resolved_e2e.dart`
- Criar: `scripts/qa/acs_ack_concluido_e2e.sh`
- Criar: `scripts/qa/acs_ack_concluido_e2e_test.sh`

**Interfaces:**
- Consome: a infraestrutura da #80. `scripts/qa/acs_alert_fallback_e2e.sh` (stack de e2e, relé 8765, `adb reverse` da 8443, broker fora do alcance do aparelho, `sql()`, `fx()`, `inserir_alerta()`) e `apps/acs/integration_test/alert_http_fallback_e2e.dart` (`_SemBiometria`, `_uuidV4`, `_ate`, `acsCredentialFromRelay`).
- Produz: o par script/teste que a Task 5 roda de novo, já com a correção.

**Simulação do aparelho B:** o alerta é inserido `pending` por SQL e sem linha no `alert_outbox`, então chega à tela só pela reserva HTTP (como na #80). Depois que o cartão aparece, o script conclui o alerta no banco, fazendo o papel do aparelho A (`UPDATE alerts SET status='resolved', "acknowledgedAt"=NOW(), "receivedAt"=NOW(), "resolvedAt"=NOW() WHERE id=…`). Para o aparelho B o cartão continua `pending`, porque a reserva nunca devolve `resolved` e nada é removido da fila. Só o ACK dele revela a conclusão. Como A conclui não importa para o teste; importa o estado da linha quando o ACK de B chega.

- [ ] **Passo 1: escrever o teste de integração** `ack_after_resolved_e2e.dart`, com `@Timeout(Duration(minutes: 5))`, no mesmo esqueleto do `alert_http_fallback_e2e.dart` (copiar `_SemBiometria`, `_uuidV4` e `_ate`; arquivos de `integration_test` não se importam entre si). Um `testWidgets('ACK no aparelho B de um alerta já concluído no A não oferece "Concluir atendimento"')`:
  1. login com `acsCredentialFromRelay()`; esperar `alert_fallback_status` ("Sem central") por até 60 s;
  2. `print('E2E_DISPARAR_ALERTA id=$id')`; esperar `Key('alert_$id')` por até 45 s;
  3. `print('E2E_CONCLUIR_NO_APARELHO_A id=$id')`; bombear 6 s (o laço do script confere a cada 1 s);
  4. tocar "Confirmar recebimento" dentro do cartão;
  5. esperar até 20 s que apareça `Key('resolved_$id')` **ou** `Key('resolve_$id')`; se aparecer `resolve_$id`, `fail('#86: "Concluir atendimento" reapareceu depois do ACK de um alerta já concluído')`;
  6. `expect(find.byKey(Key('resolved_$id')), findsOneWidget)`, `expect(find.byKey(Key('resolve_$id')), findsNothing)`, `expect(find.text('Este atendimento já foi concluído.'), findsOneWidget)`; `print('E2E_ACK_CONCLUIDO_OK')`;
  7. bombear 35 s (um tique inteiro da reserva) e repetir os dois `expect` de chave; `print('E2E_SEGUE_CONCLUIDO_OK')`.

- [ ] **Passo 2: escrever o script** `acs_ack_concluido_e2e.sh`, copiando do `acs_alert_fallback_e2e.sh` o cabeçalho, o `cleanup` (o manifesto é apagado antes do `down`), a stack, o relé, os `adb reverse`, `sql`, `fx`, `inserir_alerta` e o comando `flutter test` com os mesmos `--dart-define`, mas apontando para `integration_test/ack_after_resolved_e2e.dart`. O laço reage a duas linhas marcadoras: `E2E_DISPARAR_ALERTA` chama `inserir_alerta`; `E2E_CONCLUIR_NO_APARELHO_A` chama `concluir_no_aparelho_a` (o `UPDATE` acima, depois de validar o UUID como `inserir_alerta` faz, registrando `[script] alerta … concluído no aparelho A (hora)`). Depois do teste: exigir status 0, as duas marcas do script e `E2E_ACK_CONCLUIDO_OK`/`E2E_SEGUE_CONCLUIDO_OK` na saída, e conferir no banco com `igual`:
  - `select status from alerts where id = …` → `resolved`
  - `select count(*) from audit_logs where "resourceType"='alert' and "resourceId"=… and result='ack_already_resolved'` → `1`
  - `select count(*) from audit_logs where "resourceType"='alert' and "resourceId"=… and result='acknowledged'` → `0`
  - `select count(*) from alert_outbox where "alertId"=…` → `0`

- [ ] **Passo 3: escrever o teste de texto** `acs_ack_concluido_e2e_test.sh`, no molde do `acs_alert_fallback_e2e_test.sh`: `bash -n`; `dev="${DEVICE:-emulator-5554}"`; `reverse --remove tcp:8883` e nunca `reverse tcp:8883`; as duas marcas no teste e no script; o `UPDATE … 'resolved'`; os quatro `igual`; `rm -f .e2e/fixtures.json` antes do `e2e_stack.sh down`; o teste com sufixo `_e2e`.
  Rodar: `./scripts/qa/acs_ack_concluido_e2e_test.sh` → `OK`.

- [ ] **Passo 4: reproduzir o defeito no emulador** (código ainda sem correção):
  `emulator -avd <avd> &` (ou `adb devices` mostra `emulator-5554`), depois `./scripts/qa/acs_ack_concluido_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-25-issue-86-reproducao.log`.
  Esperado: **FALHA** no passo 5 do teste, com `#86: "Concluir atendimento" reapareceu…`. O banco não chega a ser conferido; para registrar o lado do servidor, rodar à mão antes do `down` (ou acrescentar `|| true` só nesta execução) e anotar no log que a trilha mostra `acknowledged` para um alerta `resolved`. Isso confirma o cenário da issue no aparelho B.

- [ ] **Passo 5: commit** (o e2e é opt-in, fora da CI; falha de propósito até a Task 4)

```bash
git add apps/acs/integration_test/ack_after_resolved_e2e.dart scripts/qa/acs_ack_concluido_e2e.sh scripts/qa/acs_ack_concluido_e2e_test.sh docs/superpowers/plans/2026-10-25-issue-86-reproducao.log
git commit -m "test(e2e): ACK no aparelho B de alerta já concluído (#86, reprodução)"
```

---

### Task 2: Store — desfecho do ACK lido sob a trava e auditoria por desfecho

**Arquivos:**
- Modificar: `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart` (interface `AlertStore.acknowledge`, `AlertAckRecord`, enum novo `AlertAckOutcome`; dentro de `RedAlertService.acknowledge`, só o `auditFor`)
- Modificar: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart:106-190`
- Modificar (fakes): `test/unit/red_alert_service_test.dart`, `test/unit/red_alert_discard_paths_test.dart`, `test/unit/red_alert_lifecycle_test.dart`
- Testes: `test/integration/alert_escalation_store_test.dart` (grupo novo e os dois testes de ACK existentes), `test/integration/red_alert_discard_paths_db_test.dart:183`

**Interfaces:**
- Produz:
  - `enum AlertAckOutcome { acknowledged, alreadyAcknowledged, alreadyResolved }`, com doc por valor no estilo de `AlertResolveOutcome`.
  - `AlertAckRecord` ganha `required this.outcome` (`final AlertAckOutcome outcome`) e o getter `AlertStatus get status`, que é `resolved` para `alreadyResolved` e `acknowledged` nos outros. Os três campos atuais ficam.
  - `AlertStore.acknowledge({required String alertId, required String acsId, required String microAreaId, required AuditEvent Function(AlertAckOutcome outcome) auditFor})` → `Future<AlertAckRecord?>`. O parâmetro `audit:` sai.
- `RedAlertService.acknowledge` continua devolvendo `Future<bool>` nesta task (a troca é a Task 3), para o endpoint e o `server.dart` seguirem compilando.

- [ ] **Passo 1: escrever os testes que falham** em `alert_escalation_store_test.dart`, num `withServerpod('Dado o ACK do store ORM (#86)', …)` novo, com `_semear`, `_alerta` e `_AuditoriaGravada` do próprio arquivo e `OrmAlertStore(session: () => session, appendAudit: trilha.call)`. O `auditFor` do teste devolve um `AuditEvent` com `result: o.name`.
  - `'matriz: status lido → desfecho, status gravado e uma linha de auditoria'`: um caso por linha da matriz (`pending`, `escalated`, `acknowledged` com `acknowledgedAt` preenchido, `resolved` com `acknowledgedAt` e `resolvedAt` preenchidos via `base:`). Para cada um: `r!.outcome`, `r.status`, o status relido do banco (= coluna "Status gravado"), `resolvedAt` preservado no caso `resolved`, `trilha.eventos.single.result == r.outcome.name`.
  - `'alerta de outra microárea: null e nenhuma linha de auditoria'`: `_alerta(s, ma: _maB)` com `microAreaId: _maA` → `null`, `trilha.eventos` vazio.
  - `'ACK sobre resolved não muda o status gravado nem o resolvedAt'`: status `resolved` e `resolvedAt` iguais aos de antes (restrição do dono: só o valor devolvido muda).
  - Nos dois testes existentes (`:525` e `:536`), trocar `audit: const AuditEvent(...)` por `auditFor: (_) => const AuditEvent(...)`; no segundo, acrescentar `expect(ok!.outcome, AlertAckOutcome.acknowledged)`.
  - No grupo sem rollback (`:570`), um teste novo: `'ACK e conclusão simultâneos: o status devolvido é o da linha travada'`, com `rodadas` vezes: alerta `acknowledged`; `Future.wait([ack, resolve])` com stores de `sessionBuilder.build` e uma única `_AuditoriaGravada` compartilhada (a ordem de `eventos` é a ordem da trava, porque a trilha é gravada dentro da transação). Esperado: status final `resolved`; se `eventos.first` é o do resolve (`AlertResolveOutcome.resolved`), o ACK devolveu `alreadyResolved`/`resolved`; senão, `alreadyAcknowledged`/`acknowledged`. Nunca outro par.
  - Em `red_alert_discard_paths_db_test.dart:183`, `audit:` → `auditFor: (_) => …`.

- [ ] **Passo 2: rodar e ver falhar**
  `cd backend/sinalacs_server && dart test -j 1 test/integration/alert_escalation_store_test.dart`
  Esperado: erro de compilação (`auditFor` e `outcome` não existem).

- [ ] **Passo 3: implementar.** Em `OrmAlertStore.acknowledge`, o desfecho é calculado do `alert.status` já lido sob a trava (`resolved` → `alreadyResolved`; `acknowledged` → `alreadyAcknowledged`; `pending`/`escalated` → `acknowledged`). O `UPDATE`, a linha de entrega e a ordem (trilha por último) ficam como estão. `_appendAudit(session, transaction, auditFor(outcome))`, e o `AlertAckRecord` leva `outcome`. Em `RedAlertService.acknowledge`, `auditFor` monta o `AuditEvent` atual com `result` pela tabela das Restrições globais (`switch` total sobre `AlertAckOutcome`, sufixo `_mqtt` quando `porMqtt`). Atualizar o comentário do método (`// Toda confirmação que encontra o alerta é auditada…`) para dizer que a repetição e o ACK sobre concluído também são auditados, com `result` próprio. Fakes:
  - `FakeAlertStore`: `outcome` = `alreadyAcknowledged` quando o `acknowledged.add(alertId)` devolve `false`, senão `acknowledged`; campo `AlertAckOutcome? forcedOutcome` (nulo = essa regra), para a Task 3 simular `resolved`; `audits.add(auditFor(outcome))`.
  - `_MemoryStore`: o desfecho sai do `status[alertId]` lido (`'resolved'` → `alreadyResolved` sem regravar; `'acknowledged'` → `alreadyAcknowledged`; senão `acknowledged`, grava `'acknowledged'`); `audits.add(auditFor(outcome))`.
  - `RecordingStore` e `_NotFoundAckStore`: só a assinatura (o primeiro com `outcome: AlertAckOutcome.acknowledged`).

- [ ] **Passo 4: rodar e ver passar**
  `dart test -j 1 test/integration/alert_escalation_store_test.dart test/integration/red_alert_discard_paths_db_test.dart`
  `dart test test/unit`
  Esperado: tudo verde, incluindo `red_alert_discard_paths_test.dart` (inventário de escritores de `alerts`, que não muda).

- [ ] **Passo 5: commit**

```bash
git add backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart backend/sinalacs_server/test
git commit -m "fix(alertas): ACK lê o desfecho sob a trava e audita sem fingir mudança (#86)"
```

---

### Task 3: Serviço e endpoint — `AlertAckResult.status` com o status real

**Arquivos:**
- Modificar: `lib/src/application/alerts/red_alert_service.dart` (`RedAlertService.acknowledge`)
- Modificar: `lib/src/endpoints/alerts_endpoint.dart:75-96`
- Modificar: `lib/server.dart:208-220`
- Testes: `test/unit/red_alert_service_test.dart`, `test/unit/red_alert_lifecycle_test.dart:156`, `test/unit/red_alert_discard_paths_test.dart:339`, `test/integration/red_alert_cycle_test.dart` (grupo `concluir o atendimento (#76)`), `test/integration/red_alert_discard_paths_db_test.dart:215`

**Interfaces:**
- Consome: `AlertAckRecord.status`, `AlertAckOutcome`, `FakeAlertStore.forcedOutcome` (Task 2).
- Produz: `Future<AlertStatus?> RedAlertService.acknowledge({required AuthenticatedUser user, required String alertId})`, que devolve `null` quando o alerta não foi encontrado e `ack.status` nos demais casos. `AlertAckResult(alertId, acknowledged: status != null, status: status)`.

- [ ] **Passo 1: escrever os testes que falham**
  - `red_alert_cycle_test.dart`, no teste `'confirmar de novo depois de concluído não volta a acknowledged'` (`:623`), acrescentar `expect(ack.status, AlertStatus.resolved)` e `expect(await resultadosDaTrilha(alertId), ['acknowledged', 'resolved', 'ack_already_resolved'])`. **Esta é a reprodução no backend:** rodada antes do Passo 3, falha com `Expected: AlertStatus.resolved / Actual: AlertStatus.acknowledged`. Copiar a saída para o log da Task 1.
  - No mesmo grupo, um teste novo: `'ACK repetido de um alerta confirmado devolve acknowledged e audita ack_already_acknowledged'` (`alertaConfirmado()`, segundo ACK, `status == acknowledged`, trilha `['acknowledged', 'ack_already_acknowledged']`, status gravado `acknowledged`).
  - `red_alert_service_test.dart`: os `expect(ok, isTrue)` viram `expect(status, AlertStatus.acknowledged)` e o `isFalse` de `:620` vira `isNull`. Testes novos: `'ACK sobre alerta concluído devolve resolved e audita ack_already_resolved'` (`forcedOutcome = AlertAckOutcome.alreadyResolved`); `'… pelo MQTT audita ack_already_resolved_mqtt'` (`deviceId: RedAlertService.mqttAckDeviceId`); e, no grupo da telemetria, `'ACK sobre concluído não emite alert_received_acs'` com `forcedOutcome` e um ACK anterior, de modo que `firstAcknowledgement` seja `false`.
  - `red_alert_lifecycle_test.dart:156`, `red_alert_discard_paths_test.dart:339`, `red_alert_discard_paths_db_test.dart:215`: `isTrue` vira `AlertStatus.acknowledged`.

- [ ] **Passo 2: rodar e ver falhar**
  `dart test test/unit/red_alert_service_test.dart` → erro de compilação (o tipo devolvido ainda é `bool`).
  `dart test -j 1 test/integration/red_alert_cycle_test.dart --name 'depois de concluído'` → falha com `Actual: AlertStatus.acknowledged`.

- [ ] **Passo 3: implementar.** No serviço, `return null` no lugar de `return false` e `return ack.status` no lugar de `return true` (a telemetria continua condicionada a `firstAcknowledgement`). No endpoint, `final status = await service.acknowledge(…)` e o `AlertAckResult` da seção Interfaces. Atualizar o doc do método no endpoint: `status` é o da linha travada e pode ser `resolved`. Em `server.dart`, o log usa `status != null` para `registrado`/`sem correspondência` e mostra `status.name` quando houver; sem identidade nova no log.

- [ ] **Passo 4: conferir o cliente gerado.** Nenhum modelo mudou:
  `cd backend/sinalacs_server && serverpod generate && git status --porcelain ../sinalacs_client lib/src/generated`
  Esperado: saída vazia. Se aparecer diferença, parar e investigar antes de seguir (seria versão diferente do `serverpod_cli`, não algo desta issue).

- [ ] **Passo 5: rodar e ver passar**
  `dart test test/unit` e `dart test -j 1 test/integration/red_alert_cycle_test.dart test/integration/red_alert_discard_paths_db_test.dart test/integration/acs_open_alerts_test.dart test/integration/admin_endpoint_monitoring_test.dart`, depois `cd .. && dart analyze`.
  Esperado: verde, e `dart analyze` sem issues.

- [ ] **Passo 6: commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_server/test
git commit -m "fix(alertas): alerts.acknowledge devolve resolved quando o atendimento já foi concluído (#86)"
```

---

### Task 4: App do ACS — `resolved` no retorno do ACK vira `markResolved`

**Arquivos:**
- Modificar: `apps/acs/lib/app/app.dart:2136-2152` (`_acknowledge`)
- Modificar: `apps/acs/test/support/fakes.dart:28-31,241-255` (`FakeAcsBackend`)
- Teste: `apps/acs/test/alert_resolve_test.dart` (grupo `fluxo no painel`)

**Interfaces:**
- Consome: `AlertAckResult.status` (Task 3; o tipo já existia no cliente).
- Produz: `FakeAcsBackend.ackStatus` (`AlertStatus?`). Quando nulo, a resposta continua a de hoje (`acknowledged ? AlertStatus.acknowledged : null`); quando definido, vai em `status`.

**Regra no app:** `status == AlertStatus.resolved` → `_queue.markResolved(id)` e o aviso `'Este atendimento já foi concluído.'`; senão, `acknowledged == true` → `markAcknowledged` e o aviso atual; senão, o aviso atual de não reconhecido. Um servidor antigo (`status` nulo ou `acknowledged` com `acknowledged: true`) cai no segundo caso, como hoje.

- [ ] **Passo 1: escrever os testes de widget que falham**, em `fluxo no painel`, usando `SinalAcsApp` + `FakeAlertFeed` como `abrirComAlertaConfirmado` (mas sem o toque de confirmação dentro do helper):
  - `'ACK de alerta já concluído em outro aparelho marca concluído e não oferece "Concluir atendimento" (#86)'`: `FakeAcsBackend()..ackStatus = AlertStatus.resolved`; entregar `testAlert(alertId: 'alerta-1')`; tocar `ack_alerta-1`; `pumpAndSettle`. Esperado: `resolved_alerta-1` `findsOneWidget`, `resolve_alerta-1` e `ack_alerta-1` `findsNothing`, o texto `'Este atendimento já foi concluído.'` `findsOneWidget`, `backend.resolvedAlertIds` vazio (nenhuma conclusão foi pedida). Depois, entregar o mesmo alerta de novo (reentrega MQTT) e conferir que `resolve_alerta-1` continua `findsNothing`.
  - `'servidor sem status no ACK continua marcando confirmado'`: `ackStatus` nulo e `acknowledged: true`; depois do toque, `resolve_alerta-1` `findsOneWidget` (comportamento atual preservado).

- [ ] **Passo 2: rodar e ver falhar**
  `cd apps/acs && flutter test test/alert_resolve_test.dart`
  Esperado: o primeiro teste falha (`resolve_alerta-1` encontrado: é o defeito da issue, agora no teste de widget); o segundo passa.

- [ ] **Passo 3: implementar** a regra acima em `_acknowledge`, com um comentário de uma linha citando a #86 (outro aparelho ou reentrega concluiu antes). Implementar `ackStatus` no fake.

- [ ] **Passo 4: rodar e ver passar**
  `flutter test test/alert_resolve_test.dart test/alert_queue_merge_test.dart`, depois `flutter test` e `flutter analyze`.
  Esperado: tudo verde.

- [ ] **Passo 5: commit**

```bash
git add apps/acs/lib/app/app.dart apps/acs/test/support/fakes.dart apps/acs/test/alert_resolve_test.dart
git commit -m "fix(acs): ACK que volta resolved marca o atendimento concluído (#86)"
```

---

### Task 5: Validação no emulador, suíte completa e documentação

**Arquivos:**
- Criar: `docs/superpowers/plans/2026-10-25-issue-86-e2e.log`
- Modificar: `backend/CLAUDE.md` (parágrafo do escalonamento #44, item "ACK e expurgo": os três `result` do ACK por desfecho; endpoint `alerts.acknowledge`: `status` é o da linha travada)
- Modificar: `PROGRESS.md` (seção do RF05/#76: o item adiado da #86 fica fechado, com a evidência)

- [ ] **Passo 1: emulador, roteiro do aparelho B.** Com o `emulator-5554` no ar:
  `./scripts/qa/acs_ack_concluido_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-25-issue-86-e2e.log`
  Esperado, em ordem: `[script] alerta … inserido`, o cartão pela reserva, `[script] alerta … concluído no aparelho A`, `E2E_ACK_CONCLUIDO_OK`, `E2E_SEGUE_CONCLUIDO_OK`, e os quatro `igual` do banco (`resolved`, `1` para `ack_already_resolved`, `0` para `acknowledged`, `0` no outbox). Sem `resolve_<id>` na tela em nenhum momento.
- [ ] **Passo 2: regressão da #80 no emulador.** `./scripts/qa/acs_alert_fallback_e2e.sh` continua verde (primeiro ACK de um `pending`: trilha `acknowledged`).
- [ ] **Passo 3: suítes completas.** `cd backend/sinalacs_server && dart test -j 1` (unitários e integração, incluindo os testes da #76 em `red_alert_cycle_test.dart` e a corrida da Task 2); `cd apps/acs && flutter test`; `./scripts/qa/acs_ack_concluido_e2e_test.sh` e `./scripts/qa/acs_alert_fallback_e2e_test.sh`. Anotar as contagens no log.
- [ ] **Passo 4: documentação**, nos dois arquivos acima, com o fato e o motivo, sem repetir o plano.
- [ ] **Passo 5: grafo e commit**

```bash
graphify update .
git add docs/superpowers/plans/2026-10-25-issue-86-e2e.log backend/CLAUDE.md PROGRESS.md
git commit -m "docs(alertas): ACK devolve o status real, evidência no emulador (#86)"
```

---

## Riscos

1. **ACK e conclusão no mesmo instante.** O status devolvido vem do `alert.status` lido **depois** do `SELECT … FOR UPDATE`, na mesma transação do `UPDATE` e da trilha. O `resolve` trava a mesma linha (`orm_alert_store.dart:211-220`), então as duas transações se serializam e o ACK vê o `resolved` já commitado ou bloqueia até ele. Um ACK que chega antes devolve `acknowledged`; nesse caso o próprio ACS concluiu em seguida, e o cartão do aparelho B fica "confirmado", não "concluído", até o próximo toque, que devolve `alreadyResolved`. A janela que sobra é a mesma de qualquer leitura (o estado muda depois da resposta) e não é o defeito da issue. Provado pelo teste de corrida da Task 2.
2. **Apps já instalados.** O valor `resolved` existe no `AlertStatus` do cliente desde a #76, então um app da #76 em diante desserializa a resposta sem erro. Ele só olha `acknowledged` (que continua `true`) e mantém o comportamento de hoje (o botão reaparece, o toque devolve `alreadyResolved` e corrige a tela). Nada piora; a melhora chega com a atualização do app. Um app anterior à #76 não conhece `resolved` e falharia ao desserializar (`byName`), mas ele também não conclui atendimentos e já não conversa com o servidor da #76 em diante. No protótipo não há base instalada; registrar no PR.
3. **Cliente Serverpod.** Não precisa regenerar: nenhum `.spy.yaml` muda. A Task 3 confere com `serverpod generate` e diff vazio.
4. **`result` novo na trilha.** `ack_already_*` não começa com `acknowledged`, então a busca do backoffice por `acknowledged` (`ILIKE 'acknowledged%'`) deixa de encontrar as repetições, e isso é o que se quer. Nenhum código em `lib/` ou `apps/admin` compara o texto; o e2e da #80 confere só o primeiro ACK. As linhas antigas da trilha (repetições gravadas como `acknowledged` antes desta correção) ficam como estão: a trilha é append-only.
5. **Fora do escopo, observado na leitura:** o ACK sobre um alerta `resolved` ou já confirmado continua regravando `acsId` com o ACS que confirmou por último (comportamento anterior, mantido pela restrição de não mudar o que se grava). Se o "quem atendeu" importar para o backoffice, abrir issue própria.
