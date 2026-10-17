# Issue #81 — Wipe remoto do aparelho do ACS e rotação da chave do cache (R3, CRIPTO-APP-CACHE) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um coordenador (só ACS da UBS dele) ou o administrador manda pelo backoffice limpar um aparelho do ACS. O aparelho perde o acesso na hora, apaga no próximo contato com o servidor tudo o que o SinalACS guarda nele, incluindo as visitas não enviadas, e troca a chave do SQLCipher. O servidor registra o pedido, a entrega e a confirmação na trilha.

**Architecture:** O pedido de limpeza é uma linha nova em `device_wipe_orders`, uma por `deviceId` (índice único). O id do aparelho já existe: é o UUID da instalação que o app manda no login, e ele fica em `acs_refresh_tokens.deviceId` e `acs_upload_tokens.deviceId`. Na mesma transação do pedido, o servidor revoga todos os refresh tokens e tokens de envio desse `deviceId`. O aparelho descobre o pedido por três caminhos, e os três chegam ao mesmo `RemoteWipeCoordinator`:
- `devices.pendingWipe(deviceId)`, um método público sem token, chamado na partida, na volta do segundo plano e quando a conexão volta;
- `DeviceWipeRequiredException` em `auth.refreshSession`, a cada 15 min no máximo;
- a mesma exceção em `auth.loginInstitutional`.

O coordenador grava um diário (`WipeJournal`), apaga o banco, a cópia `.recuperado`, a chave, os tokens e o id do aparelho, e depois confirma com `devices.confirmWipe`. A rotação da chave (CRIPTO-APP-CACHE) acontece por evento: o wipe remoto e o "Limpar este aparelho" passam a destruir o arquivo e a chave. A abertura seguinte cria uma chave nova.

**Tech Stack:** Serverpod 3.4.13 (Dart) + Postgres (migração nova); Flutter `apps/acs` e `apps/admin` com o `sinalacs_client` gerado; bash + `adb` + `e2e_stack.sh` + `otp_relay.py` para a prova no `emulator-5554`.

**Spec:** issue #81 (`gh issue view 81`); `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas R3, STRIDE-S, CRIPTO-APP-CACHE e item 7 do backlog); `spec/PRD_system.md` §6.3 (R3: "SQLCipher + chave derivada de biometria; remote wipe via API"; contingência: "1. Remote wipe via API 2. Rotação de chaves imediata", recuperação em 15 min); `spec/lgpd_design.md` §5.1 (custódia da chave).

## Global Constraints

- **Escopo decidido com o dono (2026-10-17):** wipe remoto + rotação da chave nesta issue. O certificado de cliente por aparelho (STRIDE-S) fica **fora**: vira uma decisão registrada no `PROGRESS.md` e uma issue de continuação (Task 8). Motivos: precisa de uma lib X.509/CSR fora do stack, de uma CA de aparelhos e de PKI de produção.
- Escopo do operador igual ao da #43: o coordenador só alcança ACS da própria UBS e o admin alcança todos (`AdminScopeResolver`, recurso `admin_acs`). Fora do escopo e inexistente recebem a **mesma** recusa (`AdminInvalidRequestException('Aparelho não encontrado.')`), com uma linha `denied` gravada antes de lançar.
- Um aparelho é "do ACS" só se existe linha em `acs_refresh_tokens` **ou** em `acs_upload_tokens` com `userId = acsId` e aquele `deviceId`. O sentinela `InstitutionalAuthService.deviceIdAbsent` nunca é listado nem aceito.
- O pedido é irreversível: não existe cancelamento (D4). Repetir o pedido é idempotente e devolve `alreadyOrdered: true` com o `requestedAt` original.
- Motivo de um conjunto fechado: enum `DeviceWipeReason { lost, stolen, replaced }`. Rótulos no admin: "Perdido", "Roubado", "Substituído".
- Os dois métodos públicos (`devices.pendingWipe` e `devices.confirmWipe`) não aceitam token e não devolvem identidade. `pendingWipe` devolve só `String?` (o `orderId`). `confirmWipe` não devolve nada e se comporta igual com um par errado (não vira oráculo).
- Auditoria. No admin: a leitura é `read`/`admin_acs_devices`; o pedido é `write`/`admin_device`, com `wipe_ordered` ou `already_ordered` e `resourceId = orderId`. Pelo aparelho: `write`/`acs_device`, com `wipe_delivered` (só na 1ª entrega) e `wipe_confirmed`; o `userId` é o `targetUserId` do pedido (o aparelho age em nome da conta) e o `resourceId` é o `orderId`.
- INV-03: limpar o aparelho nunca descarta um alerta no servidor. Os alertas seguem `pending` lá, e o escalonamento da #44 continua valendo. O app não chama `acknowledge` nem `resolve` durante o wipe.
- A chave do SQLCipher nunca aparece em log nem em mensagem de erro (LGPD-RF09).
- Não editar `lib/src/generated/` à mão: rodar `serverpod generate`. A migração sai de `serverpod create-migration`.
- Copy em pt-BR. Mensagens dinâmicas com `Semantics(liveRegion: true)`. Alvos de toque de 48×52 também nos diálogos do admin. Botão destrutivo com `AdminColors.redOnSurface`.
- Só fixtures sintéticas (`seed_e2e_fixtures.dart`). Nenhum dado real.
- Commits sem atribuição de IA (regra do `CLAUDE.md` do repositório, que prevalece sobre o lembrete do harness).

## Decisões

- **D1 — Identidade do aparelho = o `deviceId` da instalação**, sem tabela de aparelhos nova: a lista vem de `acs_refresh_tokens` ∪ `acs_upload_tokens`, agrupada por `deviceId`, e `lastSeenAt` é o maior `issuedAt`. O wipe troca o `deviceId` (`DeviceIdStore.delete`), então o id antigo nunca volta, e por isso o índice único em `device_wipe_orders.deviceId` basta para a idempotência.
- **D2 — O wipe remoto ignora o bloqueio de visitas não enviadas.** O "Limpar este aparelho" do ACS continua recusando (`WipeBlocked`). O remoto apaga tudo, inclusive visitas pendentes, em conflito, recusadas, legadas e de outros donos, porque o caso é aparelho perdido ou roubado. O diálogo do admin avisa disso antes da confirmação.
- **D3 — Prazo de entrega.** Com o aparelho online, ele recebe o pedido em até 15 min: o JWT vivo (15 min) não é revogado por chamada, mas a renovação seguinte recebe `DeviceWipeRequiredException`. A partida, a volta do segundo plano e a volta da conexão perguntam `pendingWipe` na hora. Aparelho offline para sempre não é alcançável: limite registrado, porque é inerente ao modelo.
- **D4 — Sem cancelamento.** As sessões já foram revogadas na transação do pedido, e um "desfazer" deixaria um pedido entregue pela metade. Se o pedido foi um engano, o ACS entra de novo depois da limpeza.
- **D5 — Revogação por aparelho, não por conta.** O pedido revoga os tokens de **todos** os usuários daquele `deviceId` (a fila é por dono, e o aparelho pode ter vários donos), porque o aparelho inteiro é apagado. As outras sessões do ACS em outros aparelhos não são tocadas: cortar a conta inteira é o `setAcsActive(false)` da #43.
- **D6 — Rotação da chave por evento, não por calendário (CRIPTO-APP-CACHE).** A chave é trocada no wipe remoto e no "Limpar este aparelho" (`VisitDatabase.destroy`: fecha, apaga o arquivo e os sidecars, apaga a `.recuperado` e apaga a chave). Não há `PRAGMA rekey` periódico, porque ele reescreve o arquivo inteiro com visitas pendentes dentro, e uma falha no meio arrisca exatamente o que a fila protege. Registrar no `spec/lgpd_design.md` §5.1 e no `PROGRESS.md`.
- **D7 — Diário antes de apagar.** `WipeJournal` (em `shared_preferences`; guarda só `orderId` e o `deviceId` antigo, nada sensível) é gravado **antes** de qualquer exclusão e tem a fase `erasing` ou `erased`. Na partida, `erasing` refaz a limpeza (que é idempotente) e `erased` só reenvia a confirmação. O diário só é apagado depois que `confirmWipe` responder.
- **D8 — Certificado por aparelho adiado** (ver Global Constraints). Fica registrado que o certificado de dev `acs-area-12` compartilhado continua no APK de debug, e que o release já recusa a chave privada no asset.

## Review Focus

1. **Pedido chega com o painel aberto e a fila com visitas em RAM** (o ACS está no meio de um formulário quando o app volta do segundo plano). Esperado: o painel some, a fila em memória é descartada sem tentar gravar, o banco é apagado e a tela `device_wiped` aparece. Nenhum `setState` pode rodar depois do `dispose` do painel. → widget `wipe remoto com painel aberto desmonta o painel e mostra device_wiped` (Task 5).
2. **O processo morre no meio da limpeza** (diário em `erasing`, banco já apagado, chave ainda presente). Esperado: a partida seguinte termina a limpeza **antes** de abrir o banco e confirma. → teste `diário em erasing termina a limpeza na partida antes de abrir o banco` (Task 4).
3. **Três gatilhos ao mesmo tempo** (o retorno do segundo plano dispara `pendingWipe`, a renovação recebe `DeviceWipeRequiredException` e a conexão volta). Esperado: uma limpeza só e uma confirmação só. → teste `gatilhos concorrentes compartilham uma só limpeza` (Task 4).
4. **`confirmWipe` falha sem rede depois da limpeza.** Esperado: o diário fica em `erased`, o app segue usável com um `deviceId` novo, e a confirmação é reenviada na próxima partida ou volta da conexão. O login novo funciona, porque o `deviceId` novo não tem pedido. → teste `confirmação sem rede fica no diário e é reenviada` (Task 4).
5. **Coordenador pede limpeza de aparelho de ACS de outra UBS, ou de um `deviceId` que o ACS nunca usou.** Esperado: a mesma recusa `Aparelho não encontrado.`, uma linha `denied` e nenhum token revogado. → teste `coordenador fora da UBS e aparelho alheio recebem a mesma recusa sem revogar nada` (Task 1).

---

### Task 1: Backend — pedido de limpeza e listagem de aparelhos (admin)

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/device_wipe_order.spy.yaml` (table `device_wipe_orders`)
- Create: `backend/sinalacs_server/lib/src/models/enums/device_wipe_reason.spy.yaml`, `.../enums/device_wipe_state.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/admin_acs_device.spy.yaml`, `.../api/admin_device_wipe_result.spy.yaml` (siga a pasta `api/` dos modelos da #43)
- Create: `backend/sinalacs_server/lib/src/application/devices/device_wipe_service.dart`
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_device_wipe_store.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (add `deviceWipeServiceFor`, next to `adminAccountServiceFor`, line 364)
- Modify: `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart` (two methods after `resetStaffMfa`)
- Create: migration via `serverpod create-migration`
- Test: `backend/sinalacs_server/test/unit/device_wipe_service_test.dart`, `backend/sinalacs_server/test/integration/device_wipe_store_test.dart`

**Interfaces:**
- Produces (models):
  - `DeviceWipeOrder { UuidValue? id (defaultPersist=random), String deviceId, UuidValue targetUserId (relation users), UuidValue requestedBy (relation users), DeviceWipeReason reason, DateTime requestedAt, DateTime? deliveredAt, DateTime? confirmedAt }`, with a unique index `device_wipe_orders_device_key` on `deviceId`.
  - `enum DeviceWipeReason { lost, stolen, replaced }`
  - `enum DeviceWipeState { pending, delivered, confirmed }`
  - `AdminAcsDevice { String deviceId, String label, DateTime lastSeenAt, DeviceWipeState? wipeState, DateTime? wipeRequestedAt, DateTime? wipeConfirmedAt }`, where `label = 'Aparelho ' + first 8 chars of deviceId`.
  - `AdminDeviceWipeResult { String orderId, DateTime requestedAt, bool alreadyOrdered }`
- Produces (`DeviceWipeStore`, abstract, in `device_wipe_service.dart`):
  - `Future<List<AdminAcsDevice>> devicesOf(String acsId)` (ordered by `lastSeenAt` desc)
  - `Future<bool> deviceBelongsTo(String acsId, String deviceId)`
  - `Future<({DeviceWipeOrder order, bool created})> orderWipe({required String deviceId, required String targetUserId, required String requestedBy, required DeviceWipeReason reason, required DateTime at})`. It runs in **one transaction**: insert or read the existing order (unique index), then `revokedAt = at` on every live row of `acs_refresh_tokens` and `acs_upload_tokens` with that `deviceId`. When the order already exists it revokes nothing new.
  - Task 2 uses: `Future<DeviceWipeOrder?> orderFor(String deviceId)`, `Future<bool> markDelivered(String orderId, DateTime at)` (true only the first time), `Future<bool> markConfirmed(String deviceId, String orderId, DateTime at)` (true only the first time, and only if the pair matches).
- Produces (`DeviceWipeService`):
  - `Future<List<AdminAcsDevice>> devicesOf(AuthenticatedUser user, {required String acsId})`
  - `Future<AdminDeviceWipeResult> orderWipe(AuthenticatedUser user, {required String acsId, required String deviceId, required DeviceWipeReason reason})`
- Produces (endpoint): `admin.acsDevices(accessToken, acsId) → List<AdminAcsDevice>` and `admin.orderDeviceWipe(accessToken, acsId, deviceId, reason) → AdminDeviceWipeResult`.
- Consumes: `AdminScopeResolver.resolve(user, recurso: 'admin_acs', actionType: …)`, `AdminAccountStore.acsById(scope, acsId)` (the ACS must be in scope), and `AuditTrail.record(AuditEvent)` with the audit/deny pattern of `admin_account_service.dart:570-620`.

- [ ] **Step 1: Write the failing unit tests** in `test/unit/device_wipe_service_test.dart`, with fakes for the store, the scope resolver and the audit (same doubles as `admin_account_service_test.dart`):
  - `admin pede limpeza: created, revoga e audita wipe_ordered`. Expect `result.alreadyOrdered == false`, `result.orderId == fakeStore.lastOrder.id`, and an audit line `(write, admin_device, wipe_ordered, resourceId: orderId)`.
  - `pedido repetido devolve alreadyOrdered com o requestedAt original e audita already_ordered`.
  - `coordenador fora da UBS e aparelho alheio recebem a mesma recusa sem revogar nada`. Three cases: ACS of another UBS; a `deviceId` with no token for that ACS; `deviceId == InstitutionalAuthService.deviceIdAbsent`. Each one throws `AdminInvalidRequestException` with `message == 'Aparelho não encontrado.'`, writes a `denied` line, and leaves `fakeStore.orderWipeCalls == 0`.
  - `paciente e ACS não alcançam` (the resolver refuses, as in #43).
  - `listagem audita read admin_acs_devices antes de ler e esconde o sentinela`.
- [ ] **Step 2:** Run `cd backend/sinalacs_server && dart test test/unit/device_wipe_service_test.dart`. Expected: FAIL (`DeviceWipeService` is not defined).
- [ ] **Step 3:** Write the models and run `serverpod generate` and then `serverpod create-migration`. Implement `DeviceWipeService` and the `DeviceWipeStore` interface, register the service in `AlertRuntime`, and add the two endpoint methods with doc comments in the style of `setAcsActive`. In `OrmDeviceWipeStore.orderWipe`, use `session.db.transaction` + `INSERT … ON CONFLICT ("deviceId") DO NOTHING RETURNING` (no row returned = read the existing one), then the two `UPDATE … SET "revokedAt" = @at WHERE "deviceId" = @d AND "revokedAt" IS NULL` statements, only when `created`.
- [ ] **Step 4: Write the integration tests** in `test/integration/device_wipe_store_test.dart` (`withServerpod`, same setup as `admin_account_store_test.dart`):
  - `orderWipe revoga refresh e envio de todos os donos do deviceId e só dele`: two users on device D and one user on device E. After the order, every live row of D has `revokedAt` set and E is untouched.
  - `segundo orderWipe não cria linha nem revoga de novo` (`created == false`, same `id`).
  - `devicesOf agrupa por deviceId, lastSeenAt = maior issuedAt, junta estado do pedido`: states `pending` → `delivered` → `confirmed` follow `deliveredAt`/`confirmedAt`.
- [ ] **Step 5:** Run `dart test test/unit/device_wipe_service_test.dart test/integration/device_wipe_store_test.dart` (test database up, as described in `backend/CLAUDE.md`). Expected: PASS. Then run `dart test` for the whole backend. Expected: no regression.
- [ ] **Step 6: Commit** `feat(backend): pedido de limpeza remota do aparelho do ACS pelo backoffice (#81)`

### Task 2: Backend — entrega e confirmação pelo aparelho, e recusa no login e na renovação

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/exceptions/device_wipe_required_exception.spy.yaml` (`orderId: String`, `message: String`)
- Modify: `backend/sinalacs_server/lib/src/endpoints/devices_endpoint.dart` (two public methods)
- Modify: `backend/sinalacs_server/lib/src/application/devices/device_wipe_service.dart` (device-side methods)
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart` (`loginInstitutional` line 78, `refreshSession` line 184)
- Test: `backend/sinalacs_server/test/unit/device_wipe_service_test.dart` (new group), `backend/sinalacs_server/test/integration/device_wipe_endpoint_test.dart`

**Interfaces:**
- Consumes: `DeviceWipeStore.orderFor` / `markDelivered` / `markConfirmed` (Task 1).
- Produces:
  - `DeviceWipeService.pendingOrderId(String deviceId) → Future<String?>`. It returns the `orderId` when an order exists and is not confirmed, and marks the delivery plus the `wipe_delivered` audit line only the first time.
  - `DeviceWipeService.confirm(String deviceId, String orderId) → Future<void>`. On the first valid confirmation it records `wipe_confirmed`. A wrong pair or a repeat is a silent no-op.
  - `DeviceWipeService.ensureDeviceNotMarked(String? deviceId) → Future<void>`. It throws `DeviceWipeRequiredException(orderId: …, message: 'Este aparelho precisa ser limpo a pedido da coordenação.')` whenever **any** order exists for that `deviceId`, confirmed or not: a cleaned device never reuses the old id (D1), so an old id that shows up again is treated as a device to clean. A null or empty `deviceId`, or the sentinel, means no check.
  - Endpoints: `devices.pendingWipe(String deviceId) → String?` and `devices.confirmWipe(String deviceId, String orderId) → void`. Neither one requires a token.

- [ ] **Step 1: Write the failing unit tests:**
  - `pendingOrderId marca entrega e audita só na primeira vez`.
  - `pendingOrderId de aparelho sem pedido, ou já confirmado, devolve null sem auditar`.
  - `confirm com par errado não grava nem audita; com par certo grava uma vez`.
  - `ensureDeviceNotMarked lança com o orderId; sentinela e vazio passam`.
- [ ] **Step 2: Write the failing integration test** `device_wipe_endpoint_test.dart`. ACS fixture with password and a refresh token on device D; order the wipe through `admin.orderDeviceWipe` with the admin session. Then:
  - `refreshSession(refreshToken, deviceId: D)` throws `DeviceWipeRequiredException` with `orderId`. It must **not** be `SessionExpiredException`: the app has to tell "wipe" apart from "session expired".
  - `loginInstitutional(…, deviceId: D)` with the correct password throws `DeviceWipeRequiredException`, and `loginInstitutional(…, deviceId: novo)` returns a session.
  - `devices.pendingWipe(D) == orderId`; `devices.confirmWipe(D, orderId)`; then `devices.pendingWipe(D) == null`, and `loginInstitutional(…, deviceId: D)` throws again (the old id stays marked forever).
  - `audit_logs` has `wipe_ordered`, `wipe_delivered` and `wipe_confirmed` with the same `resourceId`.
- [ ] **Step 3:** Run both. Expected: FAIL.
- [ ] **Step 4:** Implement. In `auth_endpoint.dart`, call `ensureDeviceNotMarked(deviceId)` **before** password verification in `loginInstitutional` and before `RefreshTokenService.refresh` in `refreshSession`. The order revoked the tokens already, so the check comes first so the answer is the wipe, not the generic refusal. Run `serverpod generate`.
- [ ] **Step 5:** Run `dart test`. Expected: PASS, with no regression in `refresh_token_test.dart`, `auth_*` and `upload_token_test.dart`.
- [ ] **Step 6: Commit** `feat(backend): aparelho recebe e confirma a limpeza remota; login e renovação recusam aparelho marcado (#81)`

### Task 3: ACS — destruir banco e chave (rotação) e usar isso no "Limpar este aparelho"

**Files:**
- Modify: `apps/acs/lib/core/database/sqlcipher_visit_store.dart` (`VisitDatabase`, plus the `VisitStorage` implementation at line 237)
- Modify: `apps/acs/lib/core/services/offline_visit_queue.dart` (`VisitStorage` interface, line 270)
- Modify: `apps/acs/lib/app/app.dart` (`wipe` in `_DeviceCare`, lines 287-321)
- Test: `apps/acs/test/device_wipe_test.dart` (extend), `apps/acs/integration_test/encrypted_storage_test.dart` (new case)

**Interfaces:**
- Produces:
  - `VisitDatabase.destroy() → Future<void>`. It closes the connection, waits for an `open()` in flight, calls `EncryptedLocalDatabase.deleteDatabaseFile`, `deleteRecoveryCopy` and `_keyStore.delete()`. The next `open()` creates a new key and an empty database.
  - `VisitStorage.destroyAll() → Future<void>`, which delegates to `destroy()`. It is unconditional: it does **not** check for visits, because that is the caller's job.
- Behavior change: `_DeviceCare.wipe` calls `_storage.destroyAll()` right after a successful `_storage.wipeAllData()`. The local wipe keeps refusing first (`WipeBlocked`) and only then rotates.

- [ ] **Step 1: Write the failing tests** in `test/device_wipe_test.dart`. Use `InMemoryDatabaseKeyStore(initialKey: 'a'*64)` and the FFI path with `allowUnencryptedForTesting: true`:
  - `destroy apaga o arquivo, a cópia recuperada e troca a chave`. Afterwards, `File(path).existsSync() == false`, `.recuperado` is gone, and `await keyStore.readOrCreate() != 'a'*64`.
  - `open depois de destroy devolve banco vazio no schema atual`.
  - `Limpar este aparelho sem visitas troca a chave`.
  - `Limpar este aparelho com visita recusa e mantém arquivo e chave` (regression of `WipeBlocked`).
- [ ] **Step 2:** Run `cd apps/acs && flutter test test/device_wipe_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Add the case `destroy troca a chave no aparelho` to `integration_test/encrypted_storage_test.dart`. On the device: write a visit, `destroy()`, open again with the new key, and check that the raw file does not contain the old visit and that the old key no longer opens the new file.
- [ ] **Step 5:** Run `flutter test test/device_wipe_test.dart` and `flutter analyze`. Expected: PASS. Run `flutter test integration_test/encrypted_storage_test.dart -d emulator-5554` (stack up per the `validacao-e2e` skill). Expected: PASS.
- [ ] **Step 6: Commit** `feat(acs): limpar o aparelho apaga o banco e troca a chave do SQLCipher (#81, CRIPTO-APP-CACHE)`

### Task 4: ACS — `RemoteWipeCoordinator`, diário e cliente

**Files:**
- Create: `apps/acs/lib/core/services/remote_wipe.dart` (`RemoteWipeCoordinator`, `WipeJournal`, `SharedPreferencesWipeJournal`, `MemoryWipeJournal`, `DeviceEraser`)
- Modify: `apps/acs/lib/core/security/session_token_store.dart` (`DeviceIdStore.delete()`; the memory implementation too) and `secure_session_token_store.dart` (`SecureStorageDeviceIdStore.delete()` deletes `acs_device_id` and resets `_pending`)
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`AcsBackend`, `BackendClient`, `MisconfiguredBackend`, and the test fakes that implement `AcsBackend`)
- Test: `apps/acs/test/remote_wipe_test.dart`, `apps/acs/test/backend_client_wipe_test.dart`

**Interfaces:**
- Produces (`AcsBackend`):
  - `Future<String?> pendingDeviceWipe(String deviceId)` → `devices.pendingWipe`. A network failure becomes `BackendFailure` (recoverable).
  - `Future<void> confirmDeviceWipe(String deviceId, String orderId)` → `devices.confirmWipe`.
  - `Future<void> forgetLocalSession()`. It bumps the generation, drops the in-memory session and calls `tokenStore.clear()`, inside `_exclusive` and **without network**.
  - `set onDeviceWipeRequired(void Function(String orderId)? callback)`. `login()` and `renewSession()` map `DeviceWipeRequiredException` to this callback **and** throw `BackendFailure('Este aparelho precisa ser limpo a pedido da coordenação.', isRecoverable: false)`. They never call `onSessionExpired`.
- Produces (`WipeJournal`): `Future<({String orderId, String deviceId, WipePhase phase})?> read()`, `Future<void> write(String orderId, String deviceId, WipePhase phase)`, `Future<void> clear()`, and `enum WipePhase { erasing, erased }`.
- Produces (`DeviceEraser`): typedef `Future<void> Function()`. The app builds it from `VisitStorage.destroyAll` + `UploadTokenStore.clearAll` + `AcsBackend.forgetLocalSession` + `DeviceIdStore.delete` (Task 5).
- Produces (`RemoteWipeCoordinator({required AcsBackend backend, required DeviceIdStore deviceIds, required WipeJournal journal, required DeviceEraser erase, void Function()? onWiped})`):
  - `Future<void> resumePending()`. Call it at startup, **before** any database open. Journal in `erasing`: erase, then `erased`, then confirm. Journal in `erased`: only confirm.
  - `Future<bool> check()`. It asks `pendingDeviceWipe` and applies the wipe when there is an order. A network failure returns `false` and never throws.
  - `Future<void> apply(String orderId)`. Single-flight: concurrent calls share the same `Future`. Order of steps: `journal.write(erasing)` → `erase()` → `journal.write(erased)` → `onWiped()` → `confirmDeviceWipe(oldDeviceId, orderId)` → `journal.clear()`. A confirmation failure keeps `erased`.

- [ ] **Step 1: Write the failing tests** in `test/remote_wipe_test.dart`, with a fake `AcsBackend`, a counting eraser, `MemoryWipeJournal` and `MemoryDeviceIdStore`:
  - `check sem pedido não apaga nada`.
  - `check com pedido apaga, chama onWiped e confirma com o deviceId antigo`. The confirmation must carry the id read **before** `erase`.
  - `gatilhos concorrentes compartilham uma só limpeza`: `check()` + `apply(id)` + `apply(id)` at the same time give `eraseCalls == 1` and `confirmCalls == 1`.
  - `confirmação sem rede fica no diário e é reenviada`: after a failure the phase is `erased`, and `resumePending()` confirms and clears the journal.
  - `diário em erasing termina a limpeza na partida antes de abrir o banco`: `resumePending()` calls `erase` again, then confirms.
  - `falha do erase mantém erasing e não confirma` (the next startup tries again).
- [ ] **Step 2: Write the failing tests** in `test/backend_client_wipe_test.dart`, with a stubbed generated client in the same style as the existing `BackendClient` tests:
  - `renewSession com DeviceWipeRequiredException chama onDeviceWipeRequired e não onSessionExpired`.
  - `login com DeviceWipeRequiredException chama onDeviceWipeRequired e lança BackendFailure não recuperável`.
  - `forgetLocalSession apaga o token e a sessão sem rede`.
- [ ] **Step 3:** Run `flutter test test/remote_wipe_test.dart test/backend_client_wipe_test.dart`. Expected: FAIL.
- [ ] **Step 4:** Implement. `SharedPreferencesWipeJournal` uses the key `acs_remote_wipe_journal`, stored as JSON `{orderId, deviceId, phase}`.
- [ ] **Step 5:** Run `flutter test` (all of it) and `flutter analyze`. Expected: PASS. `test/session_store_wiring_test.dart` must stay green: `remote_wipe.dart` must not bring `dart:ui` into the import path of `backend_client.dart`, so keep `shared_preferences` out of that path (`SharedPreferencesWipeJournal` lives in `remote_wipe.dart`, which `backend_client.dart` does not import).
- [ ] **Step 6: Commit** `feat(acs): coordenador da limpeza remota com diário e confirmação (#81)`

### Task 5: ACS — gatilhos, desmontagem do painel e tela `device_wiped`

**Files:**
- Modify: `apps/acs/lib/app/app.dart` (`SinalAcsApp`: new optional parameter `WipeJournal? wipeJournal`; state: build the `RemoteWipeCoordinator`, call `resumePending()` before the first `VisitStorage` use, and `check()` on startup, on `AppLifecycleState.resumed` and on `connectivityChanges` → `true`; register `backend.onDeviceWipeRequired`)
- Create: `apps/acs/lib/app/device_wiped_screen.dart`
- Modify: `apps/acs/lib/main.dart` (pass `SharedPreferencesWipeJournal()`)
- Test: `apps/acs/test/remote_wipe_ui_test.dart`

**Interfaces:**
- Consumes: `RemoteWipeCoordinator` (Task 4) and `VisitStorage.destroyAll` (Task 3).
- Produces: the `DeviceEraser` built in the state, in this order: discard `_queues`/`_scopes` **without saving** → `backend.forgetLocalSession()` → `_storage.destroyAll()` → `uploadTokens.clearAll(alsoOwners: owners)` (no `revokeUploadToken`: the server already revoked them) → `deviceIds.delete()`. `onWiped` runs `navigatorKey.currentState.pushAndRemoveUntil(DeviceWipedScreen route, (_) => false)`.
- `DeviceWipedScreen`:
  - `Key('device_wiped')`, `Semantics(liveRegion: true)`.
  - Exact copy: title **"Aparelho limpo pela coordenação"**; body **"Os dados do SinalACS deste aparelho foram apagados a pedido da coordenação da UBS, inclusive as visitas que ainda não tinham sido enviadas. Os alertas continuam com a equipe da UBS."**
  - Button `Key('device_wiped_login')` **"Entrar de novo"**, which returns to a fresh `LoginScreen`.
  - With the journal still in `erased` (confirmation pending), show the line `Key('device_wiped_pending_confirm')` **"A confirmação ainda não chegou ao servidor; será enviada quando houver conexão."**
  - The `AppLockGate` does not apply to this screen.

- [ ] **Step 1: Write the failing widget tests** in `test/remote_wipe_ui_test.dart`, with a fake backend that answers `pendingDeviceWipe` with `'ordem-1'` when the test asks for it:
  - `pedido na partida apaga antes do login e mostra device_wiped`: the `LoginScreen` never calls `resumeSession`, and `eraseCalls == 1`.
  - `wipe remoto com painel aberto desmonta o painel e mostra device_wiped`: log in, open the visit screen with a visit typed in, then `tester.binding.handleAppLifecycleStateChanged(paused → resumed)`. Expect `find.byKey(Key('device_wiped'))`, the panel gone, no exception (`tester.takeException() == null`), and the fake feed closed.
  - `renovação com pedido leva à mesma tela, sem tela de reautenticação`.
  - `Entrar de novo abre login com deviceId novo`: the next `login` receives a `deviceId` different from the old one.
  - `conexão que volta pergunta pendingWipe`.
  - `fonte 200% em 320x640 sem estouro na device_wiped` (`test/support/layout_harness.dart`).
- [ ] **Step 2:** Run `flutter test test/remote_wipe_ui_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test`, `flutter analyze` and `flutter test test/text_scale_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(acs): app aplica a limpeza remota na partida, na retomada, na volta da rede e na renovação (#81)`

### Task 6: Admin — aparelhos do ACS e pedido de limpeza

**Files:**
- Modify: `apps/admin/lib/core/data/admin_data_source.dart` (models + 2 methods), `backend_admin_data_source.dart`, `mock_admin_data_source.dart` (or wherever the mock lives)
- Create: `apps/admin/lib/app/acs_devices_dialog.dart`
- Modify: `apps/admin/lib/app/admin_accounts.dart` (button `Key('acs_devices_<acsId>')` labelled **"Aparelhos"** on the ACS card)
- Test: `apps/admin/test/acs_devices_dialog_test.dart`, `apps/admin/test/admin_accounts_data_source_test.dart` (extend), `apps/admin/test/touch_targets_test.dart` (extend)

**Interfaces:**
- Consumes: `admin.acsDevices` and `admin.orderDeviceWipe` (Task 1).
- Produces:
  - `AdminDataSource.fetchAcsDevices(String acsId) → Future<List<AcsDevice>>`
  - `AdminDataSource.orderDeviceWipe({required String acsId, required String deviceId, required DeviceWipeReason reason}) → Future<DeviceWipeOrderResult>`
  - App models that mirror the server and translate **by name**: `AcsDevice { deviceId, label, lastSeenAt, wipeState?, wipeRequestedAt?, wipeConfirmedAt? }`, `DeviceWipeState`, `DeviceWipeReason`, `DeviceWipeOrderResult { orderId, requestedAt, alreadyOrdered }`.
- Copy:
  - One row per device: `label` + "Último acesso em DD/MM às HH:MM".
  - State: "Limpeza pedida às HH:MM" / "Pedido entregue ao aparelho" / "Aparelho limpo às HH:MM". A row with no order shows no state line.
  - Button `Key('wipe_device_<deviceId>')` **"Limpar remotamente"**, hidden when an order already exists.
  - Reason: `Key('wipe_reason')`, with "Perdido", "Roubado" and "Substituído".
  - `confirmarDestrutiva` text: **"Limpar este aparelho remotamente? Ele perde o acesso agora e apaga os dados do SinalACS na próxima vez que se conectar, inclusive as visitas que ainda não foram enviadas. Isso não pode ser desfeito."**, with the confirm button **"Limpar aparelho"**.
  - After the result, `alreadyOrdered` shows **"Este aparelho já tinha um pedido de limpeza."** The list is reloaded from the server.
  - With no device: **"Nenhum aparelho com acesso registrado para este ACS."**

- [ ] **Step 1: Write the failing tests:**
  - `lista aparelhos com estado e último acesso`.
  - `cancelar a confirmação não chama orderDeviceWipe`.
  - `confirmar envia o motivo escolhido e recarrega a lista`.
  - `alreadyOrdered mostra o aviso`.
  - `recusa do servidor mostra texto fixo` (`AdminDataFailure`).
  - `alvos de toque 48x52 no diálogo` (`touch_targets_test.dart`).
  - `fonte 200% sem estouro`.
  - Data source: `orderDeviceWipe traduz o motivo por nome`.
- [ ] **Step 2:** Run `cd apps/admin && flutter test test/acs_devices_dialog_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test` and `flutter analyze`. Expected: PASS, including `contrast_tokens_test.dart`.
- [ ] **Step 5: Commit** `feat(admin): aparelhos do ACS e limpeza remota pelo backoffice (#81)`

### Task 7: Prova no emulador — aparelho limpo com visita não enviada

**Files:**
- Create: `apps/acs/integration_test/remote_wipe_e2e.dart` (`_e2e` suffix so discovery skips it)
- Create: `scripts/qa/acs_remote_wipe_e2e.sh` (same anatomy as `scripts/qa/acs_alert_fallback_e2e.sh`: `lib_rele.sh`, `e2e_stack.sh up`, relay with `E2E_FIXTURES_FILE`, `adb reverse`, cleanup)
- Create: `scripts/qa/acs_remote_wipe_e2e_test.sh` (structure check with no Docker and no device, like `acs_alert_fallback_e2e_test.sh`)
- Test: the two files above

**Interfaces:**
- Consumes: the relay's `/acs` and `/coordenador` routes (`otp_relay.py:76`), `integration_test/support/e2e_acs.dart` and `support/totp.dart`, and the coordinator's MFA activation flow by activation code, the same as `apps/admin/integration_test/admin_acs_gestao_e2e.dart`.

- [ ] **Step 1: Write the integration test.** It runs the real `SinalAcsApp` with the Keystore stores, as in `full_journey_e2e.dart`:
  1. The ACS logs in through the screen.
  2. It records a visit with the offline decorator, so the visit stays pending. It keeps the `deviceId` from `SecureStorageDeviceIdStore`, then taps "Sair e encerrar o turno" (the visit stays on the device).
  3. With its own generated `Client`, the test logs in the coordinator (relay `/coordenador`, MFA activation + TOTP) and calls `admin.orderDeviceWipe(acsId, deviceId, DeviceWipeReason.stolen)`. It prints `E2E_WIPE_PEDIDO order=<id> device=<deviceId>`.
  4. `handleAppLifecycleStateChanged(paused → resumed)`, then wait ≤ 30 s for `Key('device_wiped')`.
  5. Check on the device: the database file does not exist **or** reopens empty with a different key (it reads the key from `SecureStorageDatabaseKeyStore` before and after); `SecureStorageUploadTokenStore.owners()` is empty; the new `deviceId` ≠ the old one.
  6. Tap "Entrar de novo", log in again with the same credential and see the panel. This proves the new id works. Print `E2E_WIPE_OK`.
- [ ] **Step 2: Write the script.** After `E2E_WIPE_OK` it checks with `e2e_stack.sh psql`:
  - `device_wipe_orders` for the device has `deliveredAt` and `confirmedAt` not null and `reason = stolen`;
  - zero live rows in `acs_refresh_tokens`/`acs_upload_tokens` with the old `deviceId`;
  - `audit_logs` has `wipe_ordered`, `wipe_delivered` and `wipe_confirmed` with the same `resourceId`, and the order's `userId` = coordinator;
  - the visit created in step 2 is **not** in `visits` (it was never sent);
  - `audit_chain_check` is green.
  Save the log to `docs/superpowers/plans/2026-10-17-issue-81-e2e.log`.
- [ ] **Step 3:** Run `bash scripts/qa/acs_remote_wipe_e2e_test.sh`. Expected: PASS.
- [ ] **Step 4:** Run `./scripts/qa/acs_remote_wipe_e2e.sh` against `emulator-5554`. Expected: final line `E2E de limpeza remota: OK` and every SQL check green. If it fails, stop and debug (`superpowers:systematic-debugging`); do not loosen any check.
- [ ] **Step 5: Regression:** run `./scripts/qa/acs_full_e2e.sh` and `./scripts/qa/admin_acs_gestao_e2e.sh`. Expected: both green.
- [ ] **Step 6: Commit** `test(acs): e2e no emulador da limpeza remota com visita não enviada (#81)`

### Task 8: Documentação, auditoria do PRD e issue de continuação

**Files:**
- Modify: `PROGRESS.md` (new section "Limpeza remota do aparelho e rotação da chave (#81)": D1–D8, proofs, what stays open)
- Modify: `CLAUDE.md` (root: in "Already delivered" add remote wipe + event-based rotation, and remove "a supervisor-forced device wipe (no supervisor login exists)" from "Still missing"; add `devices.pendingWipe`/`confirmWipe` and `admin.acsDevices`/`orderDeviceWipe` to the endpoint list), `apps/CLAUDE.md` (a paragraph "ACS: limpeza remota (#81)"), `backend/CLAUDE.md` (the new table and the auth check)
- Modify: `spec/lgpd_design.md` §5.1 (D6) and `spec/lgpd_data_audit.md` (table `device_wipe_orders`: `deviceId` is a pseudonymous installation id; retained as audit evidence; re-count the tables in the latest `definition.sql`)
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md`: R3 → **entregue** (except the certificate), CRIPTO-APP-CACHE → **entregue** (event rotation, D6), STRIDE-S stays **parcial**, item 7 of the backlog crossed out with a reference to the new issue
- Modify: `docs/telas-admin.md` and `docs/telas-acs.md` (describe the screens; screenshots named as pending if not captured — never invented)

- [ ] **Step 1:** Write the docs above. In "Aberto", list: offline device never reached (D3); live JWT up to 15 min (D3); per-device certificate (D8); API 24–29 and a physical device unproven.
- [ ] **Step 2:** Create the follow-up issue. **Confirm the text with the owner before running it:** `gh issue create --title "[P1] Certificado de cliente MQTT por aparelho (STRIDE-S)" --body-file <arquivo>`. The body must cover: a CSR generated on the device, signed by a device CA in the backend, revocation by CRL in Mosquitto with a reload check (spike), the dependency choice (pointycastle/basic_utils, which needs an entry in `spec/stack.md`), and production PKI as infra. Put the issue number in the PRD audit and in `PROGRESS.md`.
- [ ] **Step 3:** Run `graphify update .`, `cd backend/sinalacs_server && dart test`, `cd apps/acs && flutter test`, `cd apps/admin && flutter test`, and `./scripts/qa/ci_invariants.sh`. Expected: all green.
- [ ] **Step 4: Commit** `docs: registra a limpeza remota e a rotação da chave do cache (#81)`
