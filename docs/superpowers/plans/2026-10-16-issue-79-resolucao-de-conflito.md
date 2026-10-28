# Issue #79 — Resolução de conflito de visita no ACS (R1) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O ACS vê cada visita em conflito, compara lado a lado a versão do aparelho com a do servidor e decide qual prevalece (ou edita e envia uma nova versão), sem que nenhuma das duas se perca em silêncio.

**Architecture:** O servidor passa a devolver, junto com `SyncStatus.conflict`, a cópia da visita do servidor (só ao autor, depois das checagens de território e autoria que já existem) e ganha `visits.resolveConflict`, um compare-and-set explícito sobre a versão que o ACS viu. No app, o conflito sai da fila de retentativa para uma lista própria **persistida** no SQLCipher (schema v8, aditivo), com a cópia do servidor; uma tela nova compara e resolve. "Manter a do servidor" é local (descarta a cópia do aparelho, com confirmação); "Manter a minha"/"Editar e enviar" chama o servidor.

**Tech Stack:** Serverpod 3.4.13 (Dart), Flutter (`sqflite_sqlcipher`), Postgres, emulador Android `emulator-5554` + `scripts/qa/acs_full_e2e.sh`.

**Spec:** issue #79 (origem: item #5 de `docs/auditoria-prd/2026-10-15-lacunas-prd.md`); `spec/PRD_system.md` §2.3.2 (estado `Conflict` → "UI informa ACS sobre conflito; compara versões; ACS decide qual prevalece ou gera nova versão") e tabela de riscos R1 ("ACS resolve via UI (comparação lado a lado)"); `spec/ui_design.md`; `spec/ux_accessibility_assessment.md`; `spec/lgpd_design.md` §5 (fila por dono).

## Estado verificado em `develop` (271367d)

- `VisitSyncService._syncOne` (`backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart:513-532`): mesma versão = reenvio idempotente; `entry.version == existing.version - 1` = atualiza para `existing.version + 1`; qualquer outra = `conflict` com só `serverVersion`, sem conteúdo. O caminho de conflito só é alcançado depois de território, autoria (`existing.acsId == acsId`) e legado.
- `OfflineVisitQueue._applyOutcomes` (`apps/acs/lib/core/services/offline_visit_queue.dart:526-531`): o conflito **volta para `_pending`** e é acrescentado a `_conflicts` (só RAM). Consequências medidas na leitura do código: (a) cada "Sincronizar agora" reenvia a visita, recebe o mesmo conflito e **duplica** a entrada em `_conflicts` (o contador cresce sem limite); (b) `_conflicts` não é persistido — reiniciado o app, o contador zera e a visita volta a ser só "pendente"; (c) nada no app mostra a versão do servidor. É o "parada na fila para sempre" da issue.
- `forceConflict` em `OfflineVisitQueue.sync` não tem nenhum chamador em `apps/acs` (grep) — sai.
- Testes que codificam a semântica atual e mudam neste plano: `apps/acs/test/login_flow_test.dart:~495-505` e `~635` (conflito volta a pendente e uma 2ª sync o "resolve"), `apps/acs/test/offline_burst_test.dart:~63-66` (`pendingCount == 1` depois do conflito).

## Decisões (o executor não reabre)

- **D1 — cópia do servidor no conflito.** `VisitSyncResult` ganha `serverVisit: VisitSyncEntry?`, preenchido **só** no `conflict` do caminho com autor (`sync` e `syncDeferred`; nunca em `syncLegacy`, cujo transportador não é autor). É o próprio autor recebendo a própria visita, já decifrada como no `visits.pull`; grava `read`/`visit_conflict` (`recordSafely`, `resourceId` = id da visita, sem conteúdo clínico), como o `pull` grava `visit_pull`. Modelo de API, **sem migração** de banco.
- **D2 — `visits.resolveConflict` explícito**, em vez de reaproveitar a regra `version == servidor - 1` do `sync` (obscura e sem trilha da decisão). Compare-and-set sobre `expectedServerVersion`: igual → grava o conteúdo enviado com `version + 1`, `synced`; diferente → `conflict` com a cópia nova, nada gravado. Mesmas recusas do `sync` (território, outro agente, sem autor, ids malformados, `rejected` com os mesmos textos). Visita inexistente no servidor → cria como o `sync` (honra "manter a minha"). Trilha: `write`/`visit`/`conflict_resolved_local`, `resourceId` = id da visita, com `recordSafely` — convenção do domínio de visitas (o upload do trabalho de campo não para por queda da trilha), não a fail-closed do backoffice.
- **D3 — conflito sai da retentativa.** Reenviar uma visita em conflito devolve o mesmo conflito; ela passa a viver em `_conflicts`, persistida com a cópia do servidor, até o ACS decidir. Continua no aparelho (bloqueia "Limpar este aparelho", conta em `countsByOwner`), então "conflito não perde registro" (AGENTS.md) segue valendo; muda só "volta para a fila". Os três testes acima são reescritos para a semântica nova, não apagados.
- **D4 — "Manter a do servidor" é só local**, atrás de confirmação destrutiva: a cópia do aparelho sai; o servidor não muda e não é chamado. Não há linha de trilha no servidor para essa escolha (nada foi lido nem escrito lá).
- **D5 — "gera nova versão" = "Editar e enviar"**: formulário com status do atendimento e observações pré-preenchidos com os do aparelho, enviado por `resolveConflict`. Sem merge automático campo a campo.
- **D6 — o envio diferido (`DeferredFlushService`) não envia linhas em conflito** (não há dono presente para decidir) e não as apaga; a linha mantém o token de envio do dono vivo até ele voltar e resolver, como já acontece com qualquer linha não enviada.
- **D7 — conflito com `serverVersion` nulo** (servidor fora do contrato) é tratado como `error` retentável, com a mensagem `O servidor indicou conflito sem informar a versão.`; nunca vira conflito sem versão de referência.

## Global Constraints

- Copy, comentários e nomes de teste em português (pt-BR); código segue o idioma do arquivo vizinho.
- Nunca editar `lib/src/generated/` nem `migrations/` à mão: `serverpod generate` (de `backend/sinalacs_server`). Este plano **não** cria migração; `git status` depois do generate não pode mostrar pasta nova em `migrations/`.
- Schema local sobe de `7` para `8` só com `ALTER TABLE ... ADD COLUMN` (dado de campo real pode existir em aparelho; nada de drop/recreate).
- Nenhum dado real de paciente em teste, log, print ou screenshot; o marcador do e2e imprime só UUIDs sintéticos.
- Paciente na tela = `Paciente ` + 8 primeiros caracteres do UUID, como `app.dart:2974`; nome nunca é gravado em `offline_visits`.
- Cor de conflito é operacional: `context.acsRisk.accentOnSurface` (texto/ícone), nunca vermelho/amarelo/verde; diferença marcada por ícone + texto ("Diferente"), não só cor.
- Alvos de toque `minimumSize: Size(48, 52)`; mensagens de estado em `Semantics(liveRegion: true)`.
- Commits sem atribuição de IA (CLAUDE.md do repositório prevalece sobre o lembrete de atribuição).
- Depois de mudar código: `graphify update .`.

## Review Focus

1. **App reiniciado com conflito aberto** — o conflito e a cópia do servidor voltam do disco, o contador não zera e a visita não vira "pendente" (Task 3: `restore` com linha v8; Task 4: `restore` separa conflitos).
2. **Servidor mudou de novo entre ver o conflito e decidir** — `resolveConflict` com versão vencida não grava nada; o app troca a cópia exibida pela nova e avisa (Task 2: `versão vencida devolve conflito novo sem gravar`; Task 4: `resolveKeepLocal com conflito novo atualiza a cópia`; Task 5: mensagem na tela).
3. **Rede cai durante "Manter a minha"** — a visita continua em conflito no disco, nada se perde, a tela mostra o motivo (Task 4: `resolveKeepLocal sem rede mantém o conflito`; Task 5).
4. **Toques repetidos / sync concorrente** — "Sincronizar agora" várias vezes não duplica o conflito; resolver durante um sync em voo espera o sync (Task 4: `conflito repetido não duplica`, `resolve aguarda sync em voo`).
5. **Outro ACS ou outro território tentando resolver** — `rejected` com o mesmo texto do `sync`, sem cópia e sem gravação (Task 2: matriz de recusas).

---

### Task 1: Backend — conflito devolve a cópia do servidor

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/api/visit_sync_result.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart` (`pull` e `_syncOne`)
- Test: `backend/sinalacs_server/test/unit/visit_sync_service_test.dart`
- Regenerado: `backend/sinalacs_server/lib/src/generated/**`, `backend/sinalacs_client/lib/src/protocol/**`

**Interfaces:**
- Produces: `VisitSyncResult.serverVisit: VisitSyncEntry?` (doc no `.spy.yaml`: "Preenchido apenas em `conflict` do caminho com autor: a visita como está no servidor, para o ACS comparar."). Helper privado `VisitSyncEntry _entryFor(VisitRecord visit)` usado por `pull` e pelo conflito (extrair do `pull` atual, sem mudar o que o `pull` devolve).

- [ ] **Step 1: Testes que falham** em `visit_sync_service_test.dart`, junto do teste `devolve conflito sem sobrescrever quando as versões divergem`:
  - `conflito devolve a visita do servidor ao autor`: sync `entry()` → sync `entry(version: 7, status: 'recusou atendimento')`; espera `syncStatus == conflict`, `serverVersion == 1`, `serverVisit!.status == 'realizada'`, `serverVisit!.version == 1`, `serverVisit!.localId == _localId`, `serverVisit!.notes` igual às notas gravadas.
  - `conflito grava read/visit_conflict sem conteúdo`: a trilha falsa recebe exatamente um evento `actionType: 'read'`, `resourceType: 'visit_conflict'`, `resourceId` = id da linha, e nenhum campo do evento contém o texto das notas.
  - `syncLegacy em conflito não devolve a cópia`: no teste legado já existente de conflito (`entry(version: 7, ...)`, linha ~545) acrescentar `expect(conflicted.single.serverVisit, isNull)`.
  - Nos testes de `synced`/`rejected`/`error` existentes que já pegam o resultado, acrescentar `serverVisit` nulo em um de cada.
- [ ] **Step 2:** `cd backend/sinalacs_server && dart test test/unit/visit_sync_service_test.dart` → FAIL (getter `serverVisit` não existe).
- [ ] **Step 3:** Adicionar o campo ao `.spy.yaml`, rodar `serverpod generate`; no `_syncOne`, no retorno de `conflict` (só alcançado com `legacy == false` ou com legado sem autor — preencher **só** quando `!legacy`), montar `serverVisit: _entryFor(existing)` e gravar o `read`/`visit_conflict` com `_audit.recordSafely`.
- [ ] **Step 4:** `dart test test/unit` e `dart analyze` → PASS / sem issues. `git status` sem pasta nova em `migrations/`.
- [ ] **Step 5: Commit** — `feat(backend): conflito de visita devolve a cópia do servidor ao autor (#79)`

### Task 2: Backend — `visits.resolveConflict`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/visits_endpoint.dart`
- Test: `backend/sinalacs_server/test/unit/visit_sync_service_test.dart` (grupo novo `resolveConflict`)
- Create: `backend/sinalacs_server/test/integration/visit_conflict_resolution_test.dart`
- Regenerado: cliente (`serverpod generate`)

**Interfaces:**
- Consumes: `VisitSyncResult.serverVisit` e `_entryFor` (Task 1).
- Produces:
  - `Future<VisitSyncResult> VisitSyncService.resolveConflict({required AuthenticatedUser user, required VisitSyncEntry entry, required int expectedServerVersion})`
  - `Future<VisitSyncResult> VisitsEndpoint.resolveConflict(Session session, {required String accessToken, required VisitSyncEntry visit, required int expectedServerVersion})` — `authenticate(accessToken)`, uma transação, mesma tradução `ArgumentError → AlertValidationException`, `StateError → AlertPermissionException` de `sync`. Cliente gerado: `client.visits.resolveConflict(accessToken: ..., visit: ..., expectedServerVersion: ...)`.
  - As checagens de identidade/território/autoria hoje inline em `_syncOne` (linhas ~346-512, ramo não legado) passam para um helper privado compartilhado pelos dois caminhos, para as recusas serem as **mesmas** (mesmo `SyncStatus`, mesma `message`, mesma auditoria `denied_territory`). Comportamento do `sync` não muda: os testes existentes do `sync`/`syncLegacy` têm de passar sem edição.

- [ ] **Step 1: Testes unitários que falham** (grupo `resolveConflict`):
  - `grava o conteúdo do aparelho quando a versão esperada é a corrente`: servidor em v3 (`sync entry()`, depois `entry(version: 0)`, depois `entry(version: 1)` — a regra atual leva a v3); `resolveConflict(entry(status: 'recusou atendimento'), expectedServerVersion: 3)` → `synced`, `serverVersion == 4`, linha com `status == 'recusou atendimento'`, `version == 4`; trilha com um `write`/`visit`/`conflict_resolved_local` e `resourceId` = id da linha.
  - `versão vencida devolve conflito novo sem gravar`: servidor em v3, `expectedServerVersion: 2` → `conflict`, `serverVersion == 3`, `serverVisit!.version == 3`, linha intacta, nenhuma linha `conflict_resolved_local`.
  - `visita inexistente é criada`: sem linha prévia → `synced`, `serverVersion == 1`.
  - Matriz de recusas, comparando `syncStatus` e `message` com o resultado de `service.sync` para a mesma entrada: ACS de outro território (`rejected`, + `denied_territory` auditado), outro agente (`visita registrada por outro agente`), visita sem autor (`visita sem autor registrado`), `localId`/`patientId` malformado (`identificadores devem ser UUID`), paciente inexistente (`error`, `paciente não encontrado`); em todas, `serverVisit` nulo e nenhuma escrita.
  - `expectedServerVersion menor que 1 é ArgumentError`; papel `patient` → `StateError`.
- [ ] **Step 2:** `dart test test/unit/visit_sync_service_test.dart` → FAIL (método não existe).
- [ ] **Step 3:** Implementar o serviço e o endpoint; `serverpod generate`.
- [ ] **Step 4: Teste de integração** `visit_conflict_resolution_test.dart` (`withServerpod`, tokens reais como em `patient_directory_and_territory_test.dart`): pelo endpoint, criar visita, levar a v3 por `visits.sync`, chamar `visits.sync` com `version: 1` → `conflict` com `serverVisit.version == 3`; `visits.resolveConflict(expectedServerVersion: 3)` → `synced` v4 e notas relidas decifradas iguais às enviadas; segunda chamada com `expectedServerVersion: 3` → `conflict` v4; ACS de outra microárea → `rejected`. Confere em `audit_logs` uma linha `conflict_resolved_local`.
- [ ] **Step 5:** `docker compose --profile test up -d postgres-test`; `dart test -j 1 test/integration/visit_conflict_resolution_test.dart test/integration/patient_directory_and_territory_test.dart test/unit` → PASS; `dart test test/unit/endpoint_auth_posture_test.dart` → PASS (o método está num `AuthenticatedEndpoint`, sem allowlist nova); `dart analyze` limpo.
- [ ] **Step 6: Commit** — `feat(backend): visits.resolveConflict com compare-and-set sobre a versão vista (#79)`

### Task 3: ACS — conflito persistido no SQLCipher (schema v8)

**Files:**
- Modify: `apps/acs/lib/core/services/offline_visit_queue.dart` (modelos)
- Modify: `apps/acs/lib/core/database/encrypted_database.dart` (`schemaVersion = 8`, DDL e `_upgrade`)
- Modify: `apps/acs/lib/core/database/sqlcipher_visit_store.dart` (mapeamento de linha)
- Test: `apps/acs/test/encrypted_database_test.dart`, `apps/acs/test/visit_storage_owner_test.dart`

**Interfaces:**
- Produces:
  - `class VisitConflictSnapshot { const VisitConflictSnapshot({required this.version, required this.status, required this.notes, this.completedAt}); final int version; final String status; final String notes; final DateTime? completedAt; Map<String, Object?> toJson(); factory VisitConflictSnapshot.fromJson(Map<String, Object?> json); }` — `notes` é o valor de `'campo'` do mapa do servidor, ou os valores unidos por `\n` quando não houver `'campo'`; `completedAt` em UTC ISO-8601 no JSON.
  - `factory VisitConflictSnapshot.fromEntry(VisitSyncEntry entry)` **não** fica aqui (a fila não importa o cliente gerado): a conversão vive em `backend_visit_synchronizer.dart` (Task 4).
  - `OfflineVisitRecord` ganha `final int? conflictServerVersion;` e `final VisitConflictSnapshot? conflictServer;` + `bool get inConflict => conflictServerVersion != null;`, ambos no construtor e no `copyWith` (sem caminho para zerá-los: a resolução remove ou substitui o registro).
  - Colunas novas em `offline_visits`: `conflict_server_version INTEGER`, `conflict_server_snapshot TEXT` (JSON). Nulas = não está em conflito.

- [ ] **Step 1: Testes que falham:**
  - `encrypted_database_test.dart`: `migração v7 → v8 preserva linhas e acrescenta as colunas de conflito` (abrir banco v7 com uma linha de dono e uma legada, reabrir em v8: as duas linhas intactas, colunas novas nulas); `onCreate v8 tem as colunas de conflito` (`PRAGMA table_info`).
  - `visit_storage_owner_test.dart`: `ida e volta de visita em conflito` — `save` de um registro com `conflictServerVersion: 3` e snapshot (`status: 'Paciente ausente'`, `notes: 'Sem resposta'`, `completedAt` fixo UTC) e `load` devolve os mesmos valores; registro sem conflito volta com os dois nulos; `countsByOwner` conta a linha em conflito; `wipeAllData` com só a linha em conflito lança `WipeBlocked(1)`.
  - Teste puro de `VisitConflictSnapshot.toJson/fromJson` (mesmo arquivo de teste da fila ou `test/offline_visit_queue_conflict_test.dart`, criado na Task 4 — aqui basta o round-trip).
- [ ] **Step 2:** `cd apps/acs && flutter test test/encrypted_database_test.dart test/visit_storage_owner_test.dart` → FAIL.
- [ ] **Step 3:** Implementar; atualizar o doc de `schemaVersion` com a linha "v8 acrescenta `conflict_server_version`/`conflict_server_snapshot`: a visita em conflito e a cópia do servidor ficam no aparelho até o ACS decidir (#79)". Migração no padrão da v4/v7: `PRAGMA table_info` + `ALTER TABLE offline_visits ADD COLUMN` só se a coluna faltar.
- [ ] **Step 4:** `flutter test` (suíte inteira do ACS) e `flutter analyze` → PASS.
- [ ] **Step 5: Commit** — `feat(acs): visita em conflito e cópia do servidor persistidas (schema v8) (#79)`

### Task 4: ACS — fila resolve conflitos e fala com o servidor

**Files:**
- Modify: `apps/acs/lib/core/services/offline_visit_queue.dart`
- Modify: `apps/acs/lib/core/services/backend_visit_synchronizer.dart`
- Modify: `apps/acs/lib/core/services/visit_queue_factory.dart` (liga o resolvedor)
- Modify: `apps/acs/lib/core/services/deferred_flush_service.dart` (D6)
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`AcsBackend`, `MisconfiguredBackend`, `BackendClient`)
- Modify: `apps/acs/test/support/fakes.dart`, `apps/acs/integration_test/full_journey_e2e.dart` (decorator `_rede`)
- Modify (semântica D3): `apps/acs/test/login_flow_test.dart`, `apps/acs/test/offline_burst_test.dart`
- Create: `apps/acs/test/offline_visit_queue_conflict_test.dart`
- Test: `apps/acs/test/deferred_flush_service_test.dart`, `apps/acs/test/backend_client_test.dart`

**Interfaces:**
- Consumes: `VisitConflictSnapshot`, campos de conflito do `OfflineVisitRecord` (Task 3); `client.visits.resolveConflict` e `VisitSyncResult.serverVisit` (Tasks 1–2).
- Produces:
  - `VisitSyncOutcome` ganha `final VisitConflictSnapshot? serverSnapshot;`.
  - `abstract interface class VisitConflictResolver { Future<VisitSyncOutcome> resolve(OfflineVisitRecord visit, {required int expectedServerVersion}); }` em `offline_visit_queue.dart`. `BackendVisitSynchronizer` implementa `VisitSynchronizer` **e** `VisitConflictResolver` (mesma checagem de dono de `push`); `DeferredVisitSynchronizer` e os falsos de teste existentes **não** mudam.
  - `OfflineVisitQueue({VisitStore? store, this.synchronizer, this.conflictResolver})`; `final VisitConflictResolver? conflictResolver;`.
  - `Future<void> OfflineVisitQueue.resolveKeepServer(String localId)` — remove de `_conflicts` e persiste; `localId` desconhecido é no-op.
  - `Future<SyncOutcome> OfflineVisitQueue.resolveKeepLocal(String localId, {String? outcome, String? notes})` — aplica `outcome`/`notes` editados (D5) ao registro e chama `conflictResolver.resolve(record, expectedServerVersion: record.conflictServerVersion!)`. Resultado: `synced` → sai do aparelho (`SyncOutcomeKind.synced`, `processed: 1`); `conflict` → fica, com versão e cópia novas, e o conteúdo editado preservado (`SyncOutcomeKind.conflict`); `rejected` → vai para `_rejected` com o motivo (`SyncOutcomeKind.rejected`); `error`/exceção → fica como estava antes da chamada, mas com a edição gravada (`SyncOutcomeKind.error` com a mensagem); sem `conflictResolver` → `error` com `A resolução de conflitos não está configurada neste aplicativo.`. Se um `sync()` estiver em voo, espera-o antes de ler o registro.
  - `_applyOutcomes`, caso `conflict`: o registro vai para `_conflicts` (substituindo outro de mesmo `localId`), **não** volta a `_pending`, com `conflictServerVersion: outcome.serverVersion` e `conflictServer: outcome.serverSnapshot`; `serverVersion` nulo → caminho `error` com a mensagem de D7. `restore()` separa por `inConflict` (antes de `rejectionReason`); `_persist()` grava `[..._pending, ..._conflicts, ..._rejected]`. Remover `forceConflict` e o ramo dele.
  - `AcsBackend.resolveVisitConflict(VisitSyncEntry visit, {required int expectedServerVersion, String? expectedUserId}) → Future<VisitSyncResult>`; `BackendClient` com a mesma renovação/checagem de dono de `syncVisits`; `MisconfiguredBackend` lança como os vizinhos; `FakeAcsBackend` grava as chamadas e devolve um resultado configurável; o decorator do e2e embrulha em `_rede`.
  - Em `backend_visit_synchronizer.dart`: `VisitConflictSnapshot conflictSnapshotFor(VisitSyncEntry entry)` (função de topo, pública para teste).
  - `DeferredFlushService`: linhas com `inConflict` não entram no lote e nunca são removidas por ele.

- [ ] **Step 1: Testes que falham** em `offline_visit_queue_conflict_test.dart` (falsos locais implementando `VisitSynchronizer`/`VisitConflictResolver`, store `InMemoryVisitStore`):
  - `conflito sai da retentativa e guarda a cópia do servidor`: outcome `conflict`, `serverVersion: 3`, snapshot → `pendingCount == 0`, `conflictCount == 1`, `conflictVisits.single.conflictServerVersion == 3`, snapshot igual; resultado `SyncOutcomeKind.conflict`.
  - `conflito repetido não duplica`: duas visitas, três `sync()` com a mesma resposta → `conflictCount == 2` e o falso recebeu as visitas em conflito **uma** vez só.
  - `restore separa pendente, conflito e recusada`: store pré-carregado com os três tipos → contadores 1/1/1.
  - `conflito sem versão é erro retentável`: `serverVersion: null` → fica pendente, `SyncOutcomeKind.error`, mensagem de D7.
  - `resolveKeepServer remove só aquela visita e persiste`.
  - `resolveKeepLocal sincronizado sai do aparelho` (e o resolvedor recebeu `expectedServerVersion: 3`, `outcome`/`notes` editados).
  - `resolveKeepLocal com conflito novo atualiza a cópia` (`serverVersion: 4`, novo snapshot, edição preservada).
  - `resolveKeepLocal recusado vai para recusadas` (motivo do servidor em `rejectionReason`).
  - `resolveKeepLocal sem rede mantém o conflito` (resolvedor lança `BackendFailure`-like → `error`, `conflictCount == 1`, store ainda tem a linha).
  - `resolve aguarda sync em voo` (sync preso num `Completer`; `resolveKeepLocal` só chama o resolvedor depois de o sync completar).
  - `deferred_flush_service_test.dart`: `envio diferido não manda nem apaga visita em conflito`.
  - `backend_client_test.dart`: `resolveVisitConflict recusa sessão de outro dono` (mesmo padrão do teste de `syncVisits` com `expectedUserId`), e teste de `conflictSnapshotFor` (`notes` com `'campo'` e sem `'campo'`).
  - Reescrever com a semântica D3: `login_flow_test.dart` (~495–505 e ~635: depois do conflito `pendingCount == 0`, `conflictCount == 1`; a "2ª sync" vira `resolveKeepLocal` → `synced`) e `offline_burst_test.dart` (~63–66: `pendingCount == 0`, comentário trocado para "conflito sai da retentativa e espera a decisão do ACS").
- [ ] **Step 2:** `flutter test test/offline_visit_queue_conflict_test.dart` → FAIL.
- [ ] **Step 3:** Implementar; `visit_queue_factory.dart` passa o mesmo `BackendVisitSynchronizer` como `synchronizer` e `conflictResolver`.
- [ ] **Step 4:** `flutter test` (suíte inteira) e `flutter analyze` → PASS; `flutter analyze integration_test` sem erro (o decorator compila).
- [ ] **Step 5: Commit** — `feat(acs): fila guarda o conflito fora da retentativa e resolve pelo servidor (#79)`

### Task 5: ACS — telas de comparação e decisão

**Files:**
- Create: `apps/acs/lib/app/visit_conflict_screen.dart`
- Modify: `apps/acs/lib/app/app.dart` (`VisitRegistrationScreen`: botão de entrada e texto do `SyncOutcomeKind.conflict`)
- Create: `apps/acs/test/visit_conflict_screen_test.dart`
- Modify: `apps/acs/test/text_scale_test.dart`, `apps/acs/test/contrast_tokens_test.dart` (só se surgir par token×superfície novo)

**Interfaces:**
- Consumes: `OfflineVisitQueue.conflictVisits`, `resolveKeepServer`, `resolveKeepLocal` (Task 4).
- Produces:
  - `class VisitConflictListScreen extends StatefulWidget { const VisitConflictListScreen({super.key, required this.queue}); final OfflineVisitQueue queue; }` — título "Visitas em conflito"; um item por conflito (`Key('conflict_item_<localId>')`, "Paciente <8>" + data local de registro); lista vazia mostra "Nenhuma visita em conflito." e fecha ao voltar.
  - `class VisitConflictCompareScreen extends StatefulWidget { const VisitConflictCompareScreen({super.key, required this.queue, required this.localId}); ... }`.
  - Em `VisitRegistrationScreen`, abaixo de `conflict_visits_count`: `OutlinedButton.icon(key: Key('resolve_conflicts'), label: Text('Resolver conflito(s)'))` que empurra a lista e faz `setState` ao voltar. Mensagem do `SyncOutcomeKind.conflict`: `'${n} visita(s) em conflito com o servidor. Toque em "Resolver conflito(s)" para comparar e escolher.'`.

Comparação (copy exata):
- Dois painéis, `Key('conflict_local')` "Neste aparelho" e `Key('conflict_server')` "No servidor (versão N)"; lado a lado (`Row`) com largura ≥ 600 dp, empilhados abaixo disso. Linhas: "Status do atendimento", "Observações" (vazio → "Sem observações"), "Concluída em" (`dd/MM/yyyy HH:mm`, hora local).
- Linha cujo valor difere entre os painéis: ícone `Icons.compare_arrows` + texto "Diferente", em `accentOnSurface`, com `Semantics(label: '<campo> diferente entre aparelho e servidor')`.
- Sem cópia do servidor (`conflictServer == null`): painel do servidor mostra "Conteúdo do servidor indisponível neste aparelho." e as três ações continuam disponíveis.
- Ações (`minimumSize: Size(48, 52)`): `Key('conflict_keep_local')` "Manter a minha versão"; `Key('conflict_edit')` "Editar e enviar" (abre, na própria tela, dropdown com as três opções de status de `app.dart` e campo de observações pré-preenchidos com os do aparelho, mais `Key('conflict_send_edited')` "Enviar versão editada"); `Key('conflict_keep_server')` "Manter a do servidor" → diálogo "Descartar a versão deste aparelho?" / "A visita registrada neste aparelho será apagada e a do servidor continua valendo. Isso não pode ser desfeito." com `Key('cancel_keep_server')` "Cancelar" e `Key('confirm_keep_server')` "Descartar a minha" (rótulo em `redOnSurface`, como as outras confirmações destrutivas do app).
- Resultado (`Semantics(liveRegion: true)`, `Key('conflict_status')`): `synced` → volta à lista com SnackBar "Versão do aparelho enviada ao servidor."; `conflict` → fica na tela, painel do servidor atualizado, "A visita mudou de novo no servidor. Compare outra vez antes de decidir."; `rejected` → volta à lista, "O servidor recusou esta visita: <motivo>"; `error` → fica, mostra a mensagem da fila. Botões desabilitados enquanto a chamada está em voo (sem duplo envio).

- [ ] **Step 1: Testes de widget que falham** (`visit_conflict_screen_test.dart`, fila real com falsos da Task 4):
  - `botão Resolver conflito(s) só aparece com conflito e abre a lista`.
  - `comparação mostra os dois lados e marca o que difere` (status diferente → "Diferente" na linha de status; observações iguais → sem marca na linha).
  - `Manter a do servidor pede confirmação; cancelar não apaga` / `confirmar remove a visita`.
  - `Manter a minha envia com a versão vista e volta à lista` (resolvedor recebeu `expectedServerVersion == conflictServerVersion`).
  - `Editar e enviar manda o status e as observações editados`.
  - `conflito novo atualiza o painel do servidor e avisa`.
  - `falha de rede mantém a visita e mostra o motivo`.
  - `sem cópia do servidor mostra o aviso e mantém as ações`.
  - `largura de celular empilha os painéis` (360 dp: `conflict_server` abaixo de `conflict_local`).
  - `text_scale_test.dart`: acrescentar a tela de comparação ao laço `janelas × [1.3, 2.0]` (sem overflow; `conflict_keep_local` alcançável por rolagem a 200%).
- [ ] **Step 2:** `flutter test test/visit_conflict_screen_test.dart test/text_scale_test.dart` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `flutter test` e `flutter analyze` → PASS; `flutter test test/contrast_tokens_test.dart test/no_fixed_white_text_test.dart` → PASS.
- [ ] **Step 5: Commit** — `feat(acs): tela de comparação lado a lado e decisão do conflito de visita (#79)`

### Task 6: Prova no emulador contra o backend real

**Files:**
- Modify: `apps/acs/integration_test/full_journey_e2e.dart` (testWidgets novo, inserido **antes** do teste `MFA: ...` — hoje o 4º —, porque depois dele o login da fixture passa a exigir TOTP)
- Modify: `scripts/qa/acs_full_e2e.sh` (bloco de asserções no banco)

**Interfaces:**
- Consumes: tudo das Tasks 1–5; o decorator `_rede` (offline simulado) e a sessão da fixture que o arquivo já usa.
- Produces: linha marcadora `E2E_CONFLITO manter_minha=<localId> manter_servidor=<localId> acs=<userId>`.

- [ ] **Step 1: Escrever o teste** `'conflito de visita: compara lado a lado, mantém a minha numa e a do servidor noutra (#79)'`:
  1. Login real; rede **desligada** no decorator; registrar duas visitas pela tela (status "Realizada com sucesso", observação sintética `e2e conflito`); ler os dois `localId` de `queue.pendingVisits`.
  2. Simular o "outro aparelho" do mesmo ACS **pelo `_inner`** (rede real, fora do decorator), para cada `localId`: `syncVisits` com `version: 1` e status `'Paciente ausente'` (cria v1), depois `version: 0` (v2), depois `version: 1` (v3).
  3. Religar a rede; tocar `sync_visits` → `conflict_visits_count` mostra "Em conflito: 2", `pending_visits_count` mostra 0.
  4. `resolve_conflicts` → item da 1ª visita → conferir "Realizada com sucesso" em `conflict_local`, "Paciente ausente" e "versão 3" em `conflict_server`, e "Diferente" → `conflict_keep_local` → volta à lista.
  5. Item da 2ª → `conflict_keep_server` → `confirm_keep_server`.
  6. Conferir `queue.conflictCount == 0` e `pendingCount == 0`; imprimir o marcador.
- [ ] **Step 2: Asserções do script** (após o bloco `E2E_FILA_POR_DONO`, com os helpers `sql`/`igual` existentes): para `manter_minha` → `version = 4`, `status = 'Realizada com sucesso'`, `"acsId" = acs`; para `manter_servidor` → `version = 3`, `status = 'Paciente ausente'`; `audit_logs` com exatamente 1 linha `resourceType = 'visit'` e `result = 'conflict_resolved_local'` com `"resourceId"` = id da 1ª visita, e ≥ 1 `visit_conflict`/`read`; cadeia de auditoria íntegra pelo mesmo passo que o script já roda (se roda; senão `dart run bin/audit_chain_check.dart` no banco de e2e).
- [ ] **Step 3: Rodar** `./scripts/qa/acs_full_e2e.sh` com `emulator-5554` ligado → todos os testes do arquivo PASS e o script termina com 0. Guardar a saída em `docs/superpowers/plans/2026-10-16-issue-79-e2e.log` (sem dado real: só fixtures sintéticas). Se falhar, usar superpowers:systematic-debugging antes de mexer.
- [ ] **Step 4: Commit** — `test(acs): e2e do conflito de visita no emulador contra o banco de teste (#79)`

### Task 7: Documentação e fechamento

**Files:**
- Modify: `PROGRESS.md` (seção nova "Resolução de conflito de visita (#79)": o que foi entregue, D1–D7, evidência do e2e com data, e abertos: escolha "manter a do servidor" sem trilha no servidor; conflito de visita legada segue sem tela — fica na quarentena como hoje; o envio diferido não resolve conflito)
- Modify: `apps/CLAUDE.md` (parágrafo da fila: "a conflict returns to the queue" → semântica D3, schema v8, tela, chaves)
- Modify: `backend/CLAUDE.md` (lista de endpoints: `visits.resolveConflict`, `serverVisit` no conflito, `visit_conflict`/`conflict_resolved_local` na trilha)
- Modify: `CLAUDE.md` raiz (lista de endpoints de `visits`; frase "Already delivered" com a resolução de conflito)
- Modify: `spec/lgpd_design.md` (tabela da fila por dono, linha nova: a cópia do servidor fica cifrada no SQLCipher só enquanto o conflito existe e sai com a decisão)
- Modify: `docs/telas-acs.md` (telas novas; screenshots só se capturadas de verdade com `./scripts/dev/run_acs.sh --build --captura`, senão nomeadas como pendentes)
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (R1 e DADOS-VERSION-OTIMISTA: "entregue", com a evidência)

- [ ] **Step 1:** Escrever as mudanças acima.
- [ ] **Step 2:** `bash scripts/qa/ci_invariants.sh` → PASS (nenhum job/CI mudou; confere que nada quebrou o guarda); `graphify update .`.
- [ ] **Step 3: Commit** — `docs: registra a resolução de conflito de visita (#79)`
- [ ] **Step 4:** Abrir PR para `develop` com `Closes #79`, corpo com D1–D7 e o resumo da evidência do e2e (superpowers:finishing-a-development-branch).
