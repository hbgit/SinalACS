# Issue #80 — Reserva por HTTP para o ACS receber alertas quando o MQTT cai (R2) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quando o MQTT do aparelho do ACS não está conectado, o app passa a listar por RPC (HTTPS) os alertas abertos da microárea e os põe na mesma fila de priorização, sem duplicar o que o MQTT entregar depois e sem nunca desfazer um ACK.

**Architecture:** Um método novo, `alerts.openForMicroArea`, devolve os alertas não concluídos (`pending`, `escalated` legado, `acknowledged`) da microárea **do token** (INV-01), lidos da tabela `alerts` — a mesma fonte do outbox, então não depende do broker. No app, `AlertHttpFallback` (serviço puro, sem `Timer`) consulta e funde na `AlertQueue` por `mergeFromServer`; o `AcsHomeShell` dispara a consulta ao abrir o painel, ao voltar do segundo plano e, a cada 30 s, enquanto o broker estiver desconectado. Uma linha de status no painel diz que a reserva está ativa e quando foi a última consulta.

**Tech Stack:** Serverpod 3.4.13 (Dart), Postgres; Flutter (`apps/acs`), `sinalacs_client` gerado; bash + `adb` + `e2e_stack.sh` para a prova no `emulator-5554`.

**Spec:** issue #80 (`gh issue view 80`) e `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas R2, INV-03 e item 6 do backlog); `spec/PRD_system.md` §R2 (linha 1064: "Fallback para HTTP + retry com backoff") e TMRAV < 90 s (linha 65).

## Global Constraints

- Microárea **sempre do token**, nunca parâmetro (INV-01): `openForMicroArea(accessToken)` não recebe `microAreaId`.
- Só o papel `acs` com microárea: paciente, staff e ACS sem microárea → `AlertPermissionException` (via `Authorization.require`, como `acknowledge`).
- Alerta vermelho nunca é descartado em silêncio (INV-03): `mergeFromServer` **nunca remove** cartão; ausência na resposta não apaga nada.
- Uma reentrega (HTTP ou MQTT) nunca desfaz um ACK local nem tira o marcador `escalated` (mesma regra de `AlertQueue.upsert`).
- Nenhuma identidade a mais no fio: o item traz só o que o envelope MQTT já traz (`AlertDelivery.toJson`) mais `status`, `acknowledgedAt` e `escalated`; nunca `escalatedBy`, `escalationReason`, `deviceId`, nome ou CPF.
- Sem auditoria de leitura por consulta (decisão D2 abaixo).
- Intervalo da reserva: `Duration(seconds: 30)` (`AcsHomeShell.defaultAlertFallbackInterval`) — cabe no TMRAV < 90 s.
- Teto da resposta: `RedAlertService.openAlertsLimit = 200`; os não confirmados vêm antes dos confirmados.
- Copy em pt-BR; nada de cor clínica decorativa; mensagens dinâmicas com `Semantics(liveRegion: true)`.
- Nunca dado real: só fixtures sintéticas (`seed_e2e_fixtures.dart`) e UUIDs do seed.
- Não editar `lib/src/generated/` à mão: `serverpod generate`. Nenhuma migração (só modelo de API, sem `table:`).
- Commits sem atribuição de IA (regra do `CLAUDE.md` do repositório, que prevalece sobre o lembrete do harness).

## Decisões

- **D1 — Quais alertas.** Status `pending`, `escalated` (linhas legadas) e `acknowledged`; `resolved` fica fora. O confirmado volta porque o painel mantém o confirmado até a conclusão (`markResolved`) e um ACS que reabre o app depois de "Sair" precisa ver o que ainda pede atendimento. Ordem: não confirmados (`pending`/`escalated`) por `triggeredAt` ascendente, depois confirmados por `triggeredAt` ascendente; corte em 200.
- **D2 — Sem linha de auditoria por consulta.** A consulta repete a cada 30 s com o broker fora; gravar `read` a cada uma inundaria `audit_logs` (mesma razão de `admin.alertsPulse`, #44, "zero `read` do `admin_pulse`"). O conteúdo é o mesmo que o MQTT entrega sem auditoria, e o ACK/resolução seguem auditados. Registrar a decisão no `PROGRESS.md`.
- **D3 — Quando consultar.** Sempre uma vez ao abrir o painel e ao voltar ao primeiro plano (independe do MQTT: cobre o "Sair" que esvaziou a fila local e a sessão persistente perdida). Periodicamente só enquanto `_brokerConnected == false`, só em primeiro plano; o `Timer` é cancelado quando o broker conecta e quando o app vai para `paused`. Sem backoff próprio: 30 s fixos já são o piso de custo, e uma falha apenas aparece na linha de status.
- **D4 — Chip do cabeçalho inalterado** (`Sem central` continua verdadeiro: o tempo real caiu). Quem explica a reserva é a linha `alert_fallback_status` no painel.
- **D5 — Sem persistência local de alertas** (o "persistência em sqflite" do R2 no PRD): a reserva reconstrói a fila a partir do servidor a cada abertura; gravar alerta no aparelho traria dado de saúde a mais para o SQLCipher sem ganho. Registrar como fora de escopo.

## Review Focus

1. **Mesmo alerta por MQTT e por HTTP** (a reserva acha o alerta e logo depois o broker reconecta e reentrega pela sessão persistente): um cartão só, e o ACK já dado não volta a "pendente". → teste `mergeFromServer depois de upsert do MQTT não duplica` (Task 3) e o widget `MQTT e reserva entregam o mesmo alerta: um cartão` (Task 4).
2. **ACK feito em outro aparelho / pelo caminho MQTT** enquanto o cartão local está pendente: a consulta seguinte marca como confirmado (não o deixa piscando como novo). → teste `servidor confirmado promove cartão local pendente` (Task 3).
3. **Consulta lenta sobreposta ao próximo tique ou ao `dispose`**: no máximo uma em voo; resposta que chega depois do `dispose` não chama `setState`. → widget `consulta em voo não se sobrepõe e não quebra no dispose` (Task 4).
4. **Sessão vencida durante a consulta periódica**: segue o caminho já existente (`onSessionExpired` → reautenticação) e o `PendingAlertsBanner` continua contando a fila. → widget `SessionExpired na reserva abre a reautenticação` (Task 4).
5. **Broker cai depois de ter conectado** (autoReconnect, sem `feed_error`): a reserva tem de ligar mesmo sem banner de falha. → widget `queda depois de conectar liga a reserva` (Task 4).

---

### Task 1: Contrato no backend — store e serviço

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/api/acs_open_alert.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart` (interface `AlertStore`, novo `OpenAlertSnapshot`, `RedAlertService.openForAcs`, `openAlertsLimit`)
- Modify (fakes que implementam `AlertStore`): `test/unit/red_alert_service_test.dart` (`FakeAlertStore`), `test/unit/red_alert_lifecycle_test.dart` (`RecordingStore`), `test/unit/red_alert_discard_paths_test.dart` (`_MemoryStore`)
- Test: `backend/sinalacs_server/test/unit/red_alert_service_test.dart` (grupo novo `openForAcs`)

**Interfaces:**
- Produces:
  - Modelo `AcsOpenAlert` (sem `table:`): `alertId: String`, `patientId: String`, `microAreaId: String`, `riskLevel: RiskLevel`, `locationHash: String`, `locationCell: String?`, `triggeredAt: DateTime`, `status: AlertStatus`, `acknowledgedAt: DateTime?`, `escalated: bool`. Comentário `###` citando #80, R2 e que o conjunto de campos espelha o envelope MQTT.
  - `class OpenAlertSnapshot` (mesmos campos de `AcsOpenAlert`, tipos Dart puros, `riskLevel: RiskLevel`, `status: AlertStatus`).
  - `AlertStore.openInMicroArea(String microAreaId, {required int limit}) → Future<List<OpenAlertSnapshot>>` — já ordenado e cortado conforme D1.
  - `static const int RedAlertService.openAlertsLimit = 200;`
  - `RedAlertService.openForAcs({required AuthenticatedUser user}) → Future<List<OpenAlertSnapshot>>` — `Authorization.require(user, roles: {UserRole.acs}, onDenied: () => StateError('Somente ACS territorializados podem listar alertas.'))`, depois `_store.openInMicroArea(user.microAreaId!, limit: openAlertsLimit)`.

- [ ] **Step 1: Escrever os testes que falham** (grupo `openForAcs` em `red_alert_service_test.dart`; o `FakeAlertStore` ganha `openInMicroArea` que grava `lastOpenQuery = (microAreaId, limit)` e devolve uma lista configurável):
  - `'lista pela microárea do token e com o teto de 200'` → `lastOpenQuery == (acs.microAreaId, 200)` e a lista do store volta sem alteração.
  - `'paciente não lista alertas da microárea'` → `throwsA(isA<StateError>())`, e `lastOpenQuery` segue `null`.
  - `'ACS sem microárea é recusado'` → `throwsA(isA<StateError>())`.
  - Os dois outros fakes implementam `openInMicroArea` com `=> []` (ou `throw UnimplementedError()` onde o arquivo já faz isso).

- [ ] **Step 2: Rodar e ver falhar**
  Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_service_test.dart`
  Expected: erro de compilação (`openForAcs`/`openInMicroArea` não existem).

- [ ] **Step 3: Implementar** o modelo, `serverpod generate`, `OpenAlertSnapshot`, o método na interface e `openForAcs` (assinaturas acima). `OrmAlertStore` ganha só um `throw UnimplementedError()` provisório, preenchido na Task 2.

- [ ] **Step 4: Rodar e ver passar**
  Run: `cd backend/sinalacs_server && dart analyze && dart test test/unit`
  Expected: sem issues; todos os testes de `test/unit` passam.

- [ ] **Step 5: Commit**
  ```bash
  git add backend/sinalacs_server/lib backend/sinalacs_client backend/sinalacs_server/test/unit
  git commit -m "feat(backend): contrato de alertas abertos da microárea para o ACS (#80)"
  ```

### Task 2: `OrmAlertStore.openInMicroArea` e `alerts.openForMicroArea`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart`
- Create: `backend/sinalacs_server/test/integration/acs_open_alerts_test.dart`

**Interfaces:**
- Consumes: Task 1 (`AlertStore.openInMicroArea`, `RedAlertService.openForAcs`, `AcsOpenAlert`).
- Produces: RPC `alerts.openForMicroArea({required String accessToken}) → Future<List<AcsOpenAlert>>`; `StateError` → `AlertPermissionException(message: error.message)`. Gerado no cliente como `client.alerts.openForMicroArea(accessToken: …)`.

- [ ] **Step 1: Escrever os testes de integração que falham** (`withServerpod`, mesma montagem de `red_alert_cycle_test.dart`: UUIDs do seed inseridos por caso, `_RecordingPublisher`, dev-login). Casos:
  - `'com o broker fora, o alerta criado aparece para o ACS da microárea'` — `publisher.offline = true`, paciente chama `createRedAlert` (resultado `published: false`); ACS chama `openForMicroArea` → 1 item, `alertId` igual, `status == AlertStatus.pending`, `riskLevel == RiskLevel.red`, `escalated == false`, `microAreaId == _microAreaId`, `acknowledgedAt == null`. **Este é o caso que fecha o R2 no servidor.**
  - `'confirmado continua listado; concluído sai'` — após `acknowledge` → item com `status == acknowledged` e `acknowledgedAt != null`; após `resolve` → lista vazia.
  - `'não confirmados vêm antes dos confirmados, cada grupo do mais antigo ao mais novo'` — três alertas inseridos por ORM com `triggeredAt` t0 < t1 < t2, o de t0 `acknowledged`: ordem `[t1, t2, t0]`.
  - `'escalonado aparece com escalated: true'` — linha com `escalatedAt` preenchido (e outra com `status: escalated` legado) → `escalated == true` nas duas.
  - `'ACS de outra microárea não vê'` — alerta em outra microárea (inserido por ORM) não aparece.
  - `'paciente é recusado'` → `throwsA(isA<AlertPermissionException>())`.
  - `'não grava linha de auditoria de leitura'` — contagem de `AuditLog` antes e depois da chamada é igual (D2).
  - `'corta em 200'` — 201 alertas `pending` inseridos por ORM → 200 itens, o mais novo fora.

- [ ] **Step 2: Rodar e ver falhar**
  Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test -j 1 test/integration/acs_open_alerts_test.dart`
  Expected: FAIL (`UnimplementedError` / método inexistente no endpoint).

- [ ] **Step 3: Implementar** `openInMicroArea` no `OrmAlertStore` (duas consultas `Alert.db.find`: `microAreaId.equals(...) & status.inSet({pending, escalated})` ordenada por `triggeredAt` com `limit`, depois `status.equals(acknowledged)` com o restante do limite; mapeia `escalated = escalatedAt != null || status == AlertStatus.escalated`; respeita `transaction: _transaction`) e o método do endpoint (doc-comment curto: reserva do R2, microárea do token, sem auditoria de leitura por D2). Rodar `serverpod generate`.

- [ ] **Step 4: Rodar e ver passar**
  Run: `cd backend/sinalacs_server && dart analyze && dart test -j 1 test/integration/acs_open_alerts_test.dart test/integration/red_alert_cycle_test.dart`
  Expected: todos passam.

- [ ] **Step 5: Commit**
  ```bash
  git add backend/sinalacs_server backend/sinalacs_client
  git commit -m "feat(backend): alerts.openForMicroArea lista os alertas abertos do ACS por HTTP (#80)"
  ```

### Task 3: App — cliente, fusão na fila e serviço da reserva

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`AcsBackend.openAlerts`, `MisconfiguredBackend`, `BackendClient`)
- Modify: `apps/acs/lib/core/services/alert_queue.dart` (`PrioritizedAlert.fromServer`, `AlertQueue.mergeFromServer`)
- Create: `apps/acs/lib/core/services/alert_http_fallback.dart`
- Modify: `apps/acs/test/support/fakes.dart` (`FakeAcsBackend.openAlerts`), `apps/acs/integration_test/full_journey_e2e.dart` (o decorator de `AcsBackend` repassa `openAlerts`)
- Test: `apps/acs/test/alert_queue_merge_test.dart`, `apps/acs/test/alert_http_fallback_test.dart`

**Interfaces:**
- Consumes: `client.alerts.openForMicroArea(accessToken:)` (Task 2).
- Produces:
  - `Future<List<AcsOpenAlert>> AcsBackend.openAlerts();` — `BackendClient` usa `_requireToken()` + `_guard(...)` como `acknowledge`; `MisconfiguredBackend` → `_recusar()`.
  - `factory PrioritizedAlert.fromServer(AcsOpenAlert alert)` — `riskLevel: alert.riskLevel.name`, `acknowledged: alert.status == AlertStatus.acknowledged`, `escalated: alert.escalated`, demais campos 1:1.
  - `int AlertQueue.mergeFromServer(Iterable<PrioritizedAlert> alerts)` — devolve quantos cartões foram **criados ou mudaram**; chama `notifyListeners()` uma vez, só se > 0; nunca remove.
  - `class AlertHttpFallback { AlertHttpFallback({required AcsBackend backend, required AlertQueue queue}); Future<int> poll(); }` — `poll()` = `queue.mergeFromServer(backend.openAlerts() mapeado por fromServer)`; repassa a `BackendFailure` sem engolir.

- [ ] **Step 1: Escrever os testes que falham.** `alert_queue_merge_test.dart`:
  - `'alerta novo do servidor entra na fila e conta 1'` → `mergeFromServer([a]) == 1`, `alerts.single.alertId == a.alertId`, ouvinte chamado 1×.
  - `'mesma resposta de novo não muda nada nem notifica'` → segunda chamada `== 0`, ouvinte segue em 1.
  - `'outra microárea é ignorada'` → `== 0`, fila vazia.
  - `'servidor confirmado promove cartão local pendente'` → `upsert(a)` e depois `mergeFromServer([a confirmado]) == 1`, `alerts.single.acknowledged == true`.
  - `'servidor pendente não desfaz ACK local'` → `markAcknowledged(a)`; `mergeFromServer([a pendente]) == 0`, segue `acknowledged`.
  - `'reforço do servidor marca escalated; ausência do marcador não o tira'` → `== 1` e `escalated == true`; depois `[a sem escalated]` → `== 0`, segue `escalated`.
  - `'cartão ausente da resposta não é removido'` → `upsert(a)`, `mergeFromServer([]) == 0`, `alerts.length == 1`.
  - `'mergeFromServer depois de upsert do MQTT não duplica'` → `upsert(fromMqtt(x))` + `mergeFromServer([fromServer(x)])` → `alerts.length == 1`.
  - `'concluído localmente não volta a pendente'` → `markResolved(a)`; `mergeFromServer([a confirmado]) == 0`, `resolved == true`.

  `alert_http_fallback_test.dart`: `'poll funde a resposta do backend'` (FakeAcsBackend com `openAlertsResult = [x]` → `poll() == 1`); `'falha do backend sobe como BackendFailure e não mexe na fila'`.

- [ ] **Step 2: Rodar e ver falhar**
  Run: `cd apps/acs && flutter test test/alert_queue_merge_test.dart test/alert_http_fallback_test.dart`
  Expected: erro de compilação (`mergeFromServer`, `fromServer`, `AlertHttpFallback` inexistentes).

- [ ] **Step 3: Implementar** as assinaturas acima. `FakeAcsBackend` ganha `List<AcsOpenAlert> openAlertsResult = []`, `Object? openAlertsFailure`, `int openAlertsCalls` e `Completer<void>? openAlertsGate` (para o teste de consulta lenta da Task 4).

- [ ] **Step 4: Rodar e ver passar**
  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: sem issues; suíte inteira verde.

- [ ] **Step 5: Commit**
  ```bash
  git add apps/acs
  git commit -m "feat(acs): fila funde alertas abertos lidos por HTTP sem duplicar nem desfazer ACK (#80)"
  ```

### Task 4: App — ciclo da reserva no `AcsHomeShell` e linha de status

**Files:**
- Modify: `apps/acs/lib/app/app.dart` (`AcsHomeShell`, seu `State`, `DashboardScreen`, e o repasse de `alertFallbackInterval` nas mesmas camadas por onde passa `syncInterval`: `SinalAcsApp` → … → `AcsHomeShell`)
- Test: `apps/acs/test/alert_http_fallback_shell_test.dart`

**Interfaces:**
- Consumes: `AlertHttpFallback` (Task 3), `FakeAcsBackend.openAlerts*` (Task 3).
- Produces:
  - `static const Duration AcsHomeShell.defaultAlertFallbackInterval = Duration(seconds: 30);` e parâmetro opcional `Duration? alertFallbackInterval` (mesmo padrão de `syncInterval`).
  - Estado: `bool _pollingAlerts`, `DateTime? _alertFallbackAt` (última consulta bem-sucedida), `bool _alertFallbackFailed`, `Timer? _alertFallbackTimer`.
  - `DashboardScreen` recebe `({DateTime? at, bool failed})? alertFallback`; quando não-nulo, desenha abaixo do `feed_error` um bloco `Key('alert_fallback_status')` com `Semantics(liveRegion: true)` e o texto:
    - antes da 1ª resposta: `Consultando alertas pelo servidor…`
    - ok: `Recebendo alertas pelo servidor a cada 30 s. Última consulta às HH:MM.`
    - falhou: `A consulta de alertas pelo servidor também falhou às HH:MM. Nova tentativa em 30 s.` (HH:MM do horário local; o "30" vem do intervalo efetivo em segundos).
  - O shell passa `alertFallback` só quando `!_brokerConnected`.

- [ ] **Step 1: Escrever os widget tests que falham** (com `FakeAcsBackend`, um `AlertFeed` falso que controla `onConnectionChanged`, `alertFallbackInterval: Duration(seconds: 1)` e `tester.pump(Duration)` para avançar o relógio):
  - `'ao abrir o painel consulta uma vez, mesmo com o broker conectado'` → `openAlertsCalls == 1`; nenhum tique periódico depois de 3 s; `alert_fallback_status` ausente.
  - `'broker fora: o alerta do servidor aparece sem toque e a linha de status mostra a reserva'` → feed `start` lança `AlertFeedFailure(unreachable, transient: true)`; após 1 tique `find.byKey(Key('alert_${id}'))` acha 1; texto contém `Recebendo alertas pelo servidor`.
  - `'queda depois de conectar liga a reserva'` → feed conecta, depois `onConnectionChanged(false)`; avança 1 s → `openAlertsCalls` cresce.
  - `'broker volta: o tique para'` → `onConnectionChanged(true)`; avança 3 s → `openAlertsCalls` não cresce; linha some.
  - `'MQTT e reserva entregam o mesmo alerta: um cartão'` → servidor devolve X; depois o feed falso faz `queue.upsert(fromMqtt(X))` → um único `Key('alert_X')`.
  - `'falha da consulta aparece na linha e não apaga a fila'` → `openAlertsFailure = BackendFailure(...)` → texto `também falhou`; cartões já presentes continuam.
  - `'consulta em voo não se sobrepõe e não quebra no dispose'` → `openAlertsGate` segura a 1ª; avança 3 tiques → `openAlertsCalls == 1`; desmonta o app e libera o gate → nenhuma exceção (`tester.takeException() == null`).
  - `'em segundo plano não consulta; ao voltar consulta na hora'` → `AppLifecycleState.paused`, avança 3 s sem chamadas; `resumed` → +1 chamada imediata.
  - `'SessionExpired na reserva abre a reautenticação'` → `openAlertsFailure` = a falha que o `FakeAcsBackend` já usa para sessão vencida nos testes de `session_reauth_test.dart`; espera a mesma tela/chave que aquele teste espera.

- [ ] **Step 2: Rodar e ver falhar**
  Run: `cd apps/acs && flutter test test/alert_http_fallback_shell_test.dart`
  Expected: FAIL (parâmetro/chave inexistentes).

- [ ] **Step 3: Implementar.** `_pollAlerts()` single-flight (`if (_pollingAlerts) return;`), `if (!mounted) return` depois de cada `await`, chamado: em `didChangeDependencies` logo depois de `_backend` ser atribuído; em `resumed`; pelo `Timer.periodic` da reserva. `_syncAlertFallbackTimer()` liga o timer quando `!_brokerConnected` e o app está em primeiro plano, desliga caso contrário; chamado em `_onBrokerConnectionChanged`, no fim de `_connectFeed` (sucesso e falha), em `paused`/`resumed` e cancelado no `dispose`. `BackendFailure` recuperável → `_alertFallbackFailed = true`; a sessão vencida já é tratada pelo `onSessionExpired` do `BackendClient`, não duplique esse caminho.

- [ ] **Step 4: Rodar e ver passar**
  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: sem issues; suíte inteira verde (inclui `text_scale_test.dart`, `shell_dispose_test.dart` e `contrast_tokens_test.dart`).

- [ ] **Step 5: Commit**
  ```bash
  git add apps/acs
  git commit -m "feat(acs): consulta alertas pelo servidor a cada 30 s enquanto o MQTT está fora (#80)"
  ```

### Task 5: Prova no emulador — alerta chega só pela reserva

**Files:**
- Create: `apps/acs/integration_test/alert_http_fallback_e2e.dart` (sufixo `_e2e`: fora da descoberta do `flutter test integration_test`)
- Create: `scripts/qa/acs_alert_fallback_e2e.sh`
- Create: `scripts/qa/acs_alert_fallback_e2e_test.sh` (estrutura, sem Docker nem aparelho, no molde de `admin_alertas_escalonar_e2e_test.sh`)

**Interfaces:**
- Consumes: `acsCredentialFromRelay()` (`integration_test/support/e2e_acs.dart`), `e2e_stack.sh up|psql|down`, `lib_rele.sh`, o seed `seed_e2e_fixtures.dart` (manifesto `.e2e/fixtures.json`: `acs.id`, `microAreaId`, paciente `main`).
- Produces: linhas marcadoras na saída do `flutter test`: `E2E_DISPARAR_ALERTA id=<uuid>`, `E2E_ALERTA_VIA_HTTP atraso_ms=<n>`, `E2E_ACK_OK`, `E2E_RESERVA_OK`.

Anatomia do script = `acs_full_e2e.sh` (stack de e2e, fixtures, relé, `adb reverse tcp:8443 tcp:443` e `tcp:8765`, `cleanup` que apaga o manifesto antes do `down`) + leitura em tempo real das marcadoras de `admin_alertas_escalonar_e2e.sh`. Diferenças:
- `adb -s "$dev" reverse --remove tcp:8883 || true` antes do teste, e `--dart-define=SINALACS_MQTT_HOST=localhost` — o broker fica **inalcançável a partir do aparelho**, enquanto o backend segue falando com o Mosquitto da stack (não pausar nada: a #44 mostrou que pausar o backend derruba a conexão MQTT dele).
- `--dart-define=E2E_FIXTURES=…` como no `acs_full_e2e.sh`.
- Ao ver `E2E_DISPARAR_ALERTA id=<uuid>`, o script insere por `e2e_stack.sh psql` um `alerts` com as colunas do `INSERT` de `seed_e2e_fixtures.dart` (paciente `main`, `acsId`, `microAreaId` das fixtures, `triggeredAt = NOW()`, `'red'`, `'hash-e2e'`, `'pending'`, tópico da microárea, `'device-e2e'`, `0`, `0`). Sem linha no `alert_outbox`: o alerta só pode chegar pela reserva.

- [ ] **Step 1: Escrever o teste de integração** (`@Timeout(Duration(minutes: 5))`), um `testWidgets`:
  1. Login real pela tela com `acsCredentialFromRelay()` (o mesmo `BackendClient` com CA do asset que `full_journey_e2e.dart` monta) e `SinalAcsApp(...)` com o intervalo padrão de 30 s (não encurtar: a prova é do valor de produção).
  2. Espera até 60 s por `Key('feed_error')` **ou** pelo chip `Sem central`, e por `Key('alert_fallback_status')`; falha com mensagem clara se o MQTT tiver conectado (o cenário não estaria provando nada).
  3. Gera um UUID v4, imprime `E2E_DISPARAR_ALERTA id=<uuid>` e marca o instante.
  4. Sem tocar na tela, `pump` em laço até `Key('alert_<uuid>')` aparecer, teto 45 s (30 s de intervalo + folga); imprime `E2E_ALERTA_VIA_HTTP atraso_ms=<n>`.
  5. Toca no botão de confirmar do cartão (mesma chave/rótulo que `red_alert_cycle_test.dart` usa), espera o cartão confirmado, aguarda mais 35 s (um tique da reserva) e confere que **continua** confirmado e que há exatamente um cartão com aquela chave; imprime `E2E_ACK_OK`, depois `E2E_RESERVA_OK`.

- [ ] **Step 2: Escrever o script e o teste de estrutura.** O `_test.sh` confere por `grep` no script: `reverse --remove tcp:8883`; `SINALACS_MQTT_HOST=localhost`; leitura de `E2E_DISPARAR_ALERTA`; `rm -f .e2e/fixtures.json` no `cleanup` antes do `down`; asserções finais abaixo; e que o `.dart` tem sufixo `_e2e`. Asserções do script no banco ao fim (função `igual` do script do #44):
  - `status` do alerta = `acknowledged` e `acknowledgedAt` não nulo;
  - exatamente 1 linha em `audit_logs` com `resourceType='alert'`, `resourceId=<uuid>`, `result='acknowledged'`;
  - 0 linhas em `audit_logs` com `resourceType='alert'` e `actionType='read'` (D2);
  - 0 linhas em `alert_outbox` para o `<uuid>` (prova de que não veio pelo broker);
  - a saída contém `E2E_ALERTA_VIA_HTTP`, `E2E_ACK_OK` e `E2E_RESERVA_OK`, e o atraso impresso é ≤ 45000.

- [ ] **Step 3: Rodar o teste de estrutura**
  Run: `bash scripts/qa/acs_alert_fallback_e2e_test.sh`
  Expected: `OK` e saída 0.

- [ ] **Step 4: Rodar no emulador**
  Run: `adb devices` (precisa listar `emulator-5554`), depois `./scripts/qa/acs_alert_fallback_e2e.sh 2>&1 | tee docs/superpowers/plans/2026-10-17-issue-80-e2e.log`
  Expected: saída 0; o log mostra `E2E_ALERTA_VIA_HTTP atraso_ms=` ≤ 45000, `E2E_RESERVA_OK` e as quatro asserções do banco. Se falhar, investigar com superpowers:systematic-debugging antes de mudar código; nunca afrouxar a asserção.

- [ ] **Step 5: Restaurar a stack de desenvolvimento e rodar a regressão do caminho MQTT**
  Run: `docker compose up -d && ./scripts/qa/e2e.sh --emulator`
  Expected: verde — inclui `integration_test/red_alert_cycle_test.dart`, que prova o alerta chegando pelo MQTT real com a reserva agora ativa ao abrir o painel.

- [ ] **Step 6: Commit**
  ```bash
  git add apps/acs/integration_test/alert_http_fallback_e2e.dart scripts/qa/acs_alert_fallback_e2e.sh scripts/qa/acs_alert_fallback_e2e_test.sh docs/superpowers/plans/2026-10-17-issue-80-e2e.log
  git commit -m "test(acs): e2e no emulador do alerta recebido só pela reserva HTTP (#80)"
  ```

### Task 6: Documentação e fechamento

**Files:**
- Modify: `PROGRESS.md` (seção nova "Reserva por HTTP dos alertas do ACS (#80)": o que foi entregue, D1–D5, prova e evidência, abertos: sem som/vibração/notificação do SO, consulta só em primeiro plano, sem persistência local de alertas)
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (R2 → **entregue** com a evidência; INV-03 tira o "falta"; item 6 do backlog riscado como os já resolvidos, com "resolvido na #80 (2026-10-17)")
- Modify: `CLAUDE.md` (raiz: `alerts` na lista de endpoints ganha `openForMicroArea`), `apps/CLAUDE.md` (parágrafo do ACS: `AlertHttpFallback`, `mergeFromServer`, `alert_fallback_status`, intervalo de 30 s), `backend/CLAUDE.md` (endpoint e D2, se ele lista métodos de `alerts`)

- [ ] **Step 1: Escrever as alterações de documentação** acima, com os números reais dos testes medidos nas Tasks 2–5 (não estimar).
- [ ] **Step 2: Gates finais**
  Run: `cd backend/sinalacs_server && dart analyze && dart test -j 1` ; `cd apps/acs && flutter analyze && flutter test` ; `bash scripts/qa/ci_invariants.sh` ; `graphify update .`
  Expected: tudo verde (o backend precisa do banco de teste no ar).
- [ ] **Step 3: Commit**
  ```bash
  git add PROGRESS.md CLAUDE.md apps/CLAUDE.md backend/CLAUDE.md docs/auditoria-prd/2026-10-15-lacunas-prd.md
  git commit -m "docs: registra a reserva por HTTP dos alertas do ACS (#80)"
  ```
- [ ] **Step 4:** Seguir superpowers:finishing-a-development-branch (PR para `develop` com `Closes #80`, como na #79).
