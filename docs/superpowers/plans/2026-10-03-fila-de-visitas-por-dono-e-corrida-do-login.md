# Fila de visitas por dono e fechamento da corrida do login — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (A) Uma renovação de sessão do usuário anterior nunca sobrescreve um login novo, nem na janela da gravação no Keystore. (B) A fila de visitas offline, o cursor de `visits.pull` e as visitas recusadas pertencem a um ACS: o ACS seguinte não as vê, não as envia, não as atribui a si nem as descarta. (C) Nenhum trabalho de campo fica preso num aparelho: visitas de um ACS que saiu sobem ao servidor **com a autoria dele**, sem depender da sessão ativa; visitas legadas sem dono sobem como "autoria desconhecida (migração v7)"; e o aparelho só é limpo (wipe) depois que tudo subiu.

**Architecture:** (A) Seção crítica serial (`_exclusive`) em `BackendClient` para tudo que muda `_session`, o token do Keystore e a época. (B) `offline_visits.owner` (schema v7, aditiva) com `VisitStorage.forOwner(...)`; linhas **legadas ficam em quarentena** (`owner IS NULL`, invisíveis para qualquer dono, acessíveis só por um `LegacyVisitStore`); cursor do pull por `userId|microAreaId`; fila + pull resolvidos por sessão. (C) Backend: `visits.syncLegacy` (grava com `authorship = legacyUnclaimed`, sem `acsId`, com `originDeviceId`) e um **token de envio diferido** por ACS (`acs_upload_tokens`: opaco, só hash no banco, amarrado a `userId`+`deviceId`, escopo único `visits.syncDeferred`, 7 dias) que permite subir as visitas de A depois de A sair, com a autoria correta. App: `DeferredFlushService` (legado + cada dono com token), disparado no login, na retomada, quando a conexão volta e antes do "Sair"; "Sair" tenta subir antes de sair; "Limpar este aparelho" (wipe) só habilita com tudo enviado.

**Tech Stack:** Flutter/Dart (`apps/acs`, `connectivity_plus` já presente), `sqflite_sqlcipher` + ffi (testes), `flutter_secure_storage`; Serverpod 3.4.13 (`backend/sinalacs_server`) com migração. **Nenhuma dependência nova** (ver D8: `workmanager` fica fora).

**Spec:** `PROGRESS.md` seção "Refresh token e desbloqueio biométrico do ACS (2026-10-03)" — itens abertos **(g)** (fila sem dono, com o caminho de perda por `discardRejected()`) e a corrida residual do `login()`; `spec/lgpd_design.md` §5.11 (cache por dono) e LGPD-RT06; `spec/lgpd_data_audit.md` (acrescentar `acs_upload_tokens` e as colunas novas de `visits`); `CLAUDE.md` (INV-01 território; INV-04; "preserve retry/queue/conflict semantics"; "red alerts never silently dropped").

## Global Constraints

- Texto de UI, comentários e docs em **português**; nomes de código seguem o arquivo vizinho.
- INV-01/RNF06: o ACS só vê e só envia dado do próprio território. Visita de outro dono **nunca** é carregada, enviada, contada, exibida nem descartável por quem não é o dono.
- Offline-first (CLAUDE.md): preservar as semânticas de retentativa, fila e conflito da `OfflineVisitQueue`/`SyncFsm`. **Nenhuma** linha de outro dono é apagada ou alterada por `save()` — `save()` de B nunca toca nas linhas de A.
- INV-04: o banco local **já é SQLCipher** (AES-256, chave no Keystore); a coluna nova fica no mesmo banco. A retenção de dado de terceiros no aparelho continua sendo risco de LGPD (minimização), e é por isso que o plano o fecha por envio + wipe, não por criptografia. Nenhum dado real de paciente em teste (UUIDs sintéticos).
- **Autoria é dado de auditoria:** uma visita nunca é gravada no servidor em nome de um ACS que não a fez. Quem não pode provar a autoria grava `authorship = legacyUnclaimed` e `acsId` nulo. Quem *transporta* o envio (sessão que subiu o lote legado) fica só em `audit_logs`, nunca como autor.
- Backend: o envio por token diferido só aceita visitas de pacientes da microárea do dono do token **relida do banco**; ACS inativo ou sem microárea é recusado (INV-01).
- Tokens (`uploadToken`) seguem as regras do refresh token: só o hash no banco, só no Keystore no aparelho, nunca em log nem em mensagem de erro, uma única mensagem de recusa.
- A migração v6→v7 é **aditiva** (`ALTER TABLE ... ADD COLUMN`) e preserva as linhas existentes; migrações do backend só por `serverpod generate` + `serverpod create-migration` (nunca à mão).
- Nenhum token, senha ou conteúdo de visita em log.
- Commits **sem** "Co-Authored-By" / "Generated with Claude Code" (regra do `CLAUDE.md`). Um commit por tarefa. Não mexer em `.github/workflows/ci.yml`.
- `tool/live_check.dart` roda na VM Dart: não importar `flutter_secure_storage` em `backend_client.dart` nem em arquivos que ele importa (ver `secure_session_token_store.dart`).
- Testes: `cd apps/acs && flutter analyze && flutter test`; backend: `cd backend/sinalacs_server && dart test` (integração precisa de `docker compose --profile test up -d postgres-test`); o emulador `emulator-5554` é usado na Task 9.

## Decisões (D1–D9)

| # | Decisão | Por quê |
|---|---|---|
| D1 | Dono da fila = `userId` do ACS. Dono do cursor do pull = `userId\|microAreaId` (mesma chave do cache da microárea). | A visita pertence ao ACS; o pull é por território e um cursor global pularia visitas antigas do território de B (perda silenciosa que a decisão §5.4 proíbe). |
| D2 | **(revisada)** Linhas **legadas** (`owner IS NULL`) ficam em **quarentena**: nenhum dono as carrega, conta, envia ou descarta. Só o `LegacyVisitStore` as enxerga, e o único destino é o envio `visits.syncLegacy` (D4). | Adotá-las pelo primeiro ACS corromperia a autoria do dado clínico (relatórios de produtividade, auditoria e-SUS APS). |
| D3 | O cursor legado (`visits_pull`) é abandonado; cada dono começa do `epoch`. | Idempotente (o servidor deduplica por `localId`). |
| D4 | **(nova)** Envio de legado: `visits.syncLegacy` exige uma sessão de ACS territorializado **apenas como transporte**; cada visita é validada contra a microárea do paciente × microárea de quem transporta (INV-01); grava `authorship = legacyUnclaimed`, `acsId = null`, `originDeviceId = deviceId`; auditoria `visit_legacy_sync` com o transportador. Visita de outra microárea volta `rejected` e **continua em quarentena**. | Salva o trabalho de campo sem inventar autor. O pedido original citava "Device Token / Client Credentials": **não existe** credencial de aparelho no backend, e uma credencial genérica de aparelho não prova autoria — por isso o transporte usa uma sessão real e a autoria fica "desconhecida". |
| D5 | O resolvedor de fila/pull por sessão é injetável; testes que já injetam `visitQueue`/`visitPullService` seguem como *seam*. | Mantém ~90 referências de teste. |
| D6 | A corrida do `login()` é fechada por **exclusão mútua local**, não por mais um incremento de época. | O incremento extra deixaria possível o token de A no Keystore com a sessão de B. |
| D7 | **(nova)** Envio desvinculado da sessão = **token de envio diferido** por ACS (`acs_upload_tokens`), emitido no `loginInstitutional` junto do refresh token (também só com `deviceId` real), de escopo único (`visits.syncDeferred` e `visits.revokeUploadToken`), validade de **7 dias**, hash SHA-256 no banco, guardado no Keystore **por dono** (`acs_upload_token\|<userId>`). **Sobrevive ao "Sair"** enquanto houver visita pendente desse dono; é revogado no servidor e apagado do aparelho quando a fila do dono zera. | Permite subir as visitas de A depois de A sair, **com a autoria de A** e sem que A tenha sessão, sem o poder de leitura nem de qualquer outra chamada. Substitui a "Client Credentials" do pedido, que daria a qualquer portador autoria sobre qualquer ACS. |
| D8 | **(nova)** "Worker em background": nesta entrega o envio é disparado em primeiro plano por login, retomada, `connectivity_plus` (conexão voltou) e antes do "Sair". **Android WorkManager (`workmanager`) fica fora**: é dependência nova fora de `spec/stack.md` (exige decisão), roda em isolate sem a UI e sem prova no emulador neste plano. | YAGNI + regra do repositório de não introduzir pacote fora da stack sem decidir. Está registrado como pendência com a razão. |
| D9 | **(nova)** "Limpar este aparelho" (wipe): ACS autenticado, só habilitado quando `DeferredFlushService.flushAll()` termina com **zero** visitas restantes (todos os donos + legado) ou quando o resto é só visita descartada. O wipe do pedido era acionado por **Supervisor**: **não existe login de supervisor/coordenador** (os papéis `coordinator`/`admin` não têm caminho de emissão — `CLAUDE.md`). | Sem supervisor, o wipe seguro só pode ser o que é provadamente sem perda. Quando algo não sobe (token vencido, conta inativa), o wipe fica **bloqueado** e a pendência "wipe forçado por supervisor" é registrada. |

## Review Focus

1. **Atualização com linhas legadas:** aparelho com visitas pendentes e recusadas no schema v6. Esperado: nenhuma se perde, **nenhum ACS as vê**, e elas sobem como "autoria desconhecida" (Tasks 2 e 5).
2. **ACS A sai, ACS B entra no mesmo aparelho:** B vê 0 pendentes/0 recusadas; `sync()` de B não envia nada de A; `discardRejected()` de B não apaga a recusada de A; A volta e vê tudo (Task 4).
3. **`save()` de B nunca apaga linhas de A**, nem com erro no meio da transação (Task 2, leitura direta do arquivo).
4. **Cursor do pull de A não vale para B**; o dedupe de `localId` do pull enxerga só a fila do dono (Task 3).
5. **Renovação iniciada na janela da gravação do login:** espera, lê o token **novo** e não toca na sessão de B (Task 1).
6. **Visita legada de OUTRA microárea:** o transportador não pode gravar visita de território alheio; ela volta `rejected` e continua em quarentena (Task 5).
7. **Token de envio roubado/vencido/revogado ou de conta inativa:** recusa única, sem gravar nada; token de A **nunca** grava visita de paciente fora da microárea de A, e nunca sob a autoria de outro ACS (Task 6).
8. **Envio do lote de A em voo quando B entra / app morto no meio do envio:** a visita só sai do aparelho depois do 200 do servidor; reenviar o mesmo `localId` é idempotente (Task 7).
9. **Wipe com visita não enviada:** bloqueado, nunca apaga dado pendente (Task 8).

---

## Parte A — Corrida do `login()`

### Task 1: Seção crítica para login, renovação e logout

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`login` ~318, `developmentLogin` ~560, `_doRenew` ~395-440, `logout` ~520)
- Modify: `apps/acs/test/support/fake_rpc_server.dart` (token de login distinto por login)
- Test: `apps/acs/test/refresh_session_test.dart` (novo grupo) e, se preferir, `apps/acs/test/support/gated_session_token_store.dart` (novo)

**Interfaces:**
- Consumes: `SessionTokenStore` (`read/write/clear`), `MemorySessionTokenStore`, `_invalidateRenewal()`, `_epoch`, `_storeLost`, `_staleRenewal`.
- Produces: `Future<T> _exclusive<T>(Future<T> Function() body)` (privado, **não reentrante**); `GatedSessionTokenStore(MemorySessionTokenStore inner)` com `Completer<void>? writeGate` (teste).

**Raciocínio (leia antes de codar).** Hoje `login()` faz `_invalidateRenewal()` → `await _tokenStore.write(...)` → `_session = session`. Uma renovação que **começa** entre o incremento e o `_session = ...` captura a época nova, lê o token **antigo** do Keystore, e termina "não obsoleta": grava o filho da família antiga por cima do login e/ou sobrescreve `_session`. A correção é que (1) o login bumpa, grava e troca a sessão **dentro** de uma seção crítica; (2) a renovação lê o token e captura a época **dentro** da mesma seção, e confirma (checa época, grava filho, troca sessão) **dentro** dela; (3) a rede (refresh, logout no servidor) fica **fora** da seção. Regra de ouro: dentro de `_exclusive` só há E/S local (Keystore) e atribuições — nunca rede, nunca `renewSession()`, nunca outro `_exclusive`.

- [ ] **Step 1: Estender o fake e criar o armazenamento que segura a escrita**

`fake_rpc_server.dart`: o login passa a devolver `login-<n>` (n = nº do login, começando em 0) em vez de `refresh-0` fixo; a primeira renovação continua devolvendo o próximo de `_refreshSeq` — **não** quebre `refresh_session_test.dart` (`refreshTokensSeen == ['refresh-0','refresh-1']`): se esses testes dependem do nome `refresh-0` para o primeiro login, faça o *primeiro* login devolver `refresh-0` e os seguintes `login-<n>`.

`test/support/gated_session_token_store.dart`:

```dart
import 'dart:async';

import 'package:sinalacs_acs/core/security/session_token_store.dart';

/// Memória com uma comporta na escrita: enquanto [writeGate] não completa, o
/// `write` fica pendente. Serve para parar o login exatamente na janela entre
/// o incremento da época e a troca da sessão.
class GatedSessionTokenStore implements SessionTokenStore {
  GatedSessionTokenStore([String? token]) : _inner = MemorySessionTokenStore(token);

  final MemorySessionTokenStore _inner;
  Completer<void>? writeGate;
  int writes = 0;

  @override
  Future<String?> read() => _inner.read();

  @override
  Future<void> write(String token) async {
    writes++;
    final gate = writeGate;
    if (gate != null) await gate.future;
    await _inner.write(token);
  }

  @override
  Future<void> clear() => _inner.clear();
}
```

- [ ] **Step 2: Escrever os testes que falham** (em `refresh_session_test.dart`, grupo `corrida do login (janela da gravação)`; reaproveite o `setUp` do arquivo para `server`/`backend`, mas construa o `BackendClient` com `tokenStore: gated`):

```dart
test('renovação iniciada com o login parado na gravação ESPERA e usa o token NOVO', () async {
  final gated = GatedSessionTokenStore();
  final backend = BackendClient(host: server.host, tokenStore: gated, deviceIds: MemoryDeviceIdStore('aparelho-1'));
  await backend.login(matricula: 'ACS-A', senha: 'senha-sintetica'); // token do login #0, gravado
  server.tokenLifetime = const Duration(minutes: 15);

  gated.writeGate = Completer<void>();
  final login = backend.login(matricula: 'ACS-B', senha: 'senha-sintetica'); // para na escrita
  await pumpEventQueue();
  expect(gated.writes, 2, reason: 'o login B chegou à escrita e está parado nela');

  final renovacao = backend.renewSession(); // começa DENTRO da janela
  await pumpEventQueue();
  expect(server.refreshTokensSeen, isEmpty, reason: 'a renovação não pode ler o token antes de o login confirmar');

  gated.writeGate!.complete();
  await login;
  await renovacao;

  // Leu o token do login de B, não o de A:
  expect(server.refreshTokensSeen, [server.loginTokens.last]);
  expect(await gated.read(), isNot(server.loginTokens.first));
  expect(backend.session!.userId, isNotNull);
});

test('renovação que começou ANTES do login e termina DEPOIS da gravação continua obsoleta', () async {
  // refreshDelay longo; login de B no meio; ao terminar, token e sessão são os de B
  // e onSessionExpired não dispara (comportamento já coberto — não pode regredir).
});

test('logout: renovação iniciada durante a rede do logout não ressuscita a sessão', () async {
  // logoutDelay + refreshDelay; ao final store vazio, sessão nula, sem onSessionExpired.
});
```

(`server.loginTokens` é uma lista que você acrescenta ao fake com os `refreshToken` emitidos nos logins. Complete o segundo e o terceiro teste seguindo `refresh_session_test.dart` existente — eles já têm versões; aqui o objetivo é que **continuem verdes** com a seção crítica.)

- [ ] **Step 3: Rodar e ver falhar**

Run (em `apps/acs`): `flutter test test/refresh_session_test.dart --plain-name "corrida do login"`
Expected: FAIL no primeiro teste (a renovação lê `login-0`/`refresh-0` antes do login confirmar).

- [ ] **Step 4: Implementar**

Em `BackendClient`:

```dart
/// Cauda da fila de seções críticas. Sempre completa sem erro.
Future<void> _commitTail = Future<void>.value();

/// Seção crítica **serial e não reentrante**: só uma por vez mexe em
/// `_session`, no token do Keystore e em `_epoch`. Dentro dela: apenas E/S
/// local e atribuições. Nunca rede, nunca `renewSession()`, nunca outro
/// `_exclusive` (deadlock). Fecha a corrida em que uma renovação do usuário
/// anterior, iniciada entre o incremento da época do login e a troca da
/// sessão, lia o token antigo e sobrescrevia o login novo.
Future<T> _exclusive<T>(Future<T> Function() body) {
  final done = Completer<void>();
  final previous = _commitTail;
  _commitTail = done.future;
  return previous.then((_) => body()).whenComplete(done.complete);
}
```

Mudanças:
1. `login()`: depois do `AuthSession.tryParse` bem-sucedido, **toda** a parte final vira
   ```dart
   await _exclusive(() async {
     _invalidateRenewal();
     try {
       if (refreshToken == null || refreshToken.isEmpty) { await _tokenStore.clear(); }
       else { await _tokenStore.write(refreshToken); }
     } catch (_) { throw _storeLost; }
     _session = session;
   });
   return session;
   ```
   (preserve exatamente a ordem e as mensagens de hoje; só muda que está dentro da seção.) Faça o mesmo em `developmentLogin`.
2. `_doRenew`: o **início** vira
   ```dart
   late final int epoch;
   late final String? token;
   await _exclusive(() async {
     epoch = _epoch;
     token = await _storage(_tokenStore.read);
   });
   bool stale() => epoch != _epoch;
   ```
   e cada ponto que **muda estado** (limpar o token na recusa do servidor, gravar o filho, `_expire(...)`, `_session = session`) é executado **dentro** de `_exclusive`, começando por `if (stale()) throw _staleRenewal;`. Dentro da seção `stale()` é definitivo (ninguém interleava). A leitura do `deviceId` e a chamada `refreshSession` ficam fora (rede).
3. `logout()`: a primeira metade (`_invalidateRenewal(); _session = null; token = await _tokenStore.read()`) vai numa seção; a chamada de rede `auth.logout` fica fora; a segunda metade (`_session = null; _invalidateRenewal(); await _tokenStore.clear()`) vai noutra seção.
4. `_invalidateRenewal()` continua sendo só `_epoch++; _renewal = null;` e só pode ser chamado dentro de `_exclusive`.
5. Atualize os comentários que citam "ANTES/DEPOIS da chamada de rede" para explicar a seção crítica.

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/refresh_session_test.dart test/session_expiry_mfa_test.dart test/backend_client_test.dart test/session_reauth_test.dart test/session_resume_test.dart && flutter analyze`
Expected: PASS (incluindo todos os testes de época/obsolescência que já existiam).

- [ ] **Step 6: Commit**

```bash
git add apps/acs/lib/core/network/backend_client.dart apps/acs/test
git commit -m "fix(acs): login, renovação e logout em seção crítica; renovação não lê token antigo na janela do login"
```

---

## Parte B — Fila de visitas por dono

### Task 2: Schema v7 e armazenamento SQLCipher por dono

**Files:**
- Modify: `apps/acs/lib/core/database/encrypted_database.dart` (`schemaVersion = 7`, `createOfflineVisits`, `_upgrade`)
- Modify: `apps/acs/lib/core/database/sqlcipher_visit_store.dart`
- Modify: `apps/acs/lib/core/services/offline_visit_queue.dart` (`VisitStorage`, `InMemoryVisitStorage`)
- Modify (assinatura): `apps/acs/test/encrypted_database_test.dart`, `apps/acs/integration_test/{smoke_test,red_alert_cycle_test,encrypted_storage_test}.dart` (passam `owner`)
- Test: `apps/acs/test/encrypted_database_test.dart`, `apps/acs/test/visit_storage_owner_test.dart` (novo)

**Interfaces:**
- Produces:
  ```dart
  /// Fábrica de armazenamento por dono. `VisitStore` continua sendo load/save, mas
  /// agora SEMPRE de um único dono.
  abstract interface class VisitStorage {
    VisitStore forOwner(String ownerId);
  }
  class InMemoryVisitStorage implements VisitStorage { /* um InMemoryVisitStore por dono */ }

  /// Abre (e recupera) o banco; uma só instância por processo.
  class VisitDatabase {
    VisitDatabase({required DatabaseKeyStore keyStore, String databaseName = 'sinalacs_acs.db',
        bool allowUnencryptedForTesting = false});
    Future<Database> open();
    Future<void> close();
  }
  class SqlCipherVisitStorage implements VisitStorage {
    SqlCipherVisitStorage({required DatabaseKeyStore keyStore, String databaseName = 'sinalacs_acs.db',
        bool allowUnencryptedForTesting = false});
    VisitDatabase get database;
    @override VisitStore forOwner(String ownerId);
    Future<void> close();
  }
  /// Quarentena (D2): as linhas com `owner IS NULL`. Nenhum dono as enxerga.
  abstract interface class LegacyVisitStore {
    Future<List<OfflineVisitRecord>> load();
    /// Remove só estes `localId`s legados (depois do 200 do servidor).
    Future<void> remove(Iterable<String> localIds);
  }
  // VisitStorage ganha: LegacyVisitStore get legacy;   (SqlCipherVisitStorage e InMemoryVisitStorage)
  class SqlCipherVisitStore implements VisitStore {          // visão de UM dono
    SqlCipherVisitStore({required DatabaseKeyStore keyStore, required String owner,
        String databaseName = 'sinalacs_acs.db', bool allowUnencryptedForTesting = false});
    SqlCipherVisitStore.on(VisitDatabase database, {required String owner});
    Future<void> close();
  }
  ```
- Contrato de dados: `offline_visits.owner TEXT` (nulo = legado em quarentena, D2). `load()` = `SELECT ... WHERE owner = ?` — **nunca** `owner IS NULL`; não existe adoção. `save(visits)` = em transação, `DELETE FROM offline_visits WHERE owner = ?` + `INSERT` com `owner`. Nenhuma outra linha é tocada.

- [ ] **Step 1: Escrever os testes que falham** — `visit_storage_owner_test.dart`, com `SqlCipherVisitStorage(keyStore: MemoryDatabaseKeyStore(), allowUnencryptedForTesting: true)` (use o fake de `DatabaseKeyStore` que os testes de `encrypted_database_test.dart` já usam) e banco ffi em diretório temporário como eles fazem:

```dart
test('cada dono vê só as próprias visitas', () async {
  final a = storage.forOwner('acs-a'), b = storage.forOwner('acs-b');
  await a.save([_visita('local-a1'), _visita('local-a2', rejeitada: true)]);
  expect(await b.load(), isEmpty);
  expect((await a.load()).map((v) => v.localId), ['local-a1', 'local-a2']);
});

test('save de B nunca apaga nem altera as linhas de A', () async {
  await a.save([_visita('local-a1')]);
  await b.save([_visita('local-b1')]);
  await b.save([]); // B esvazia a fila dele
  expect((await a.load()).map((v) => v.localId), ['local-a1']);
  // prova no arquivo, sem passar pela visão: conta direta por dono
  final db = await storage.database.open();
  expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM offline_visits WHERE owner='acs-a'")), 1);
});

test('migração v6 → v7 preserva as linhas em QUARENTENA: nenhum dono as vê', () async {
  // cria um banco v6 com 2 linhas SEM coluna owner (como encrypted_database_test.dart já faz
  // para v3/v4/v5), abre via SqlCipherVisitStorage e:
  expect(await storage.forOwner('acs-a').load(), isEmpty);
  expect(await storage.forOwner('acs-b').load(), isEmpty);
  expect((await storage.legacy.load()).map((v) => v.localId), ['local-v6-1', 'local-v6-2']);
  // um save() de A não toca na quarentena:
  await storage.forOwner('acs-a').save([_visita('local-a1')]);
  expect((await storage.legacy.load()).length, 2);
});

test('legacy.remove apaga só os localIds pedidos e só os legados', () async { /* linhas de dono com o mesmo localId NÃO são apagadas */ });

test('local_id é único globalmente: B não consegue sobrescrever a visita de A', () async { /* mesma local_id em dois donos → o segundo save lança ou preserva a de A; documente o comportamento escolhido e teste-o */ });
```

e em `encrypted_database_test.dart`: `schemaVersion == 7`, a coluna `owner` existe após a criação limpa e após o upgrade.

- [ ] **Step 2: Rodar e ver falhar** — `flutter test test/visit_storage_owner_test.dart test/encrypted_database_test.dart` → FAIL (símbolos novos não existem).

- [ ] **Step 3: Implementar**
  - `encrypted_database.dart`: `schemaVersion = 7`; atualizar o comentário de versões (v7: `offline_visits.owner`, dono da visita; nulo = legado em quarentena, enviado por `visits.syncLegacy`); `createOfflineVisits` ganha `owner TEXT`; em `_upgrade`: `if (from < 7) { cols = PRAGMA table_info; if (!hasOwner) ALTER TABLE offline_visits ADD COLUMN owner TEXT; }` (e `CREATE INDEX IF NOT EXISTS offline_visits_owner_idx ON offline_visits(owner)`; coloque o índice também no caminho de criação). Lembre que `from < 2` recria a tabela e retorna: use `createOfflineVisits` já com `owner`.
  - `VisitDatabase`: mover para cá a lógica de `_open()` do `SqlCipherVisitStore` atual (inclusive a recuperação "chave não abre o arquivo → apaga e recria"), sem alterar o comportamento.
  - `SqlCipherVisitStore` vira visão de dono (`load`/`save` do contrato acima; **sem** `UPDATE` de adoção). O construtor com `keyStore` cria seu próprio `VisitDatabase` (mantém os testes de integração com poucas mudanças: só acrescentam `owner:`).
  - `VisitStorage`/`InMemoryVisitStorage`/`LegacyVisitStore` em `offline_visit_queue.dart` (junto de `VisitStore`/`InMemoryVisitStore`); `SqlCipherLegacyVisitStore` sobre o mesmo `VisitDatabase`.
  - Atualizar as chamadas de teste/integração que constroem `SqlCipherVisitStore(...)` para passar `owner: 'acs-teste'`.

- [ ] **Step 4: Rodar e ver passar** — `flutter test test/visit_storage_owner_test.dart test/encrypted_database_test.dart test/offline_burst_test.dart test/micro_area_cache_store_test.dart && flutter analyze`.

- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): visitas offline com dono (schema v7); save de um ACS nunca toca nas visitas de outro"
```

---

### Task 3: Cursor do `visits.pull` por dono

**Files:**
- Modify: `apps/acs/lib/core/database/sync_cursor_store.dart`
- Modify: `apps/acs/lib/core/services/visit_pull_service_factory.dart`
- Test: `apps/acs/test/sync_cursor_store_test.dart`, `apps/acs/test/visit_pull_service_test.dart`, `apps/acs/test/visit_pull_service_factory_test.dart`

**Interfaces:**
- Consumes: `VisitDatabase` / `SqlCipherVisitStorage.database` (Task 2).
- Produces: `SyncCursorStore({required DatabaseKeyStore keyStore, required String owner, String databaseName, bool allowUnencryptedForTesting})` — chave `'visits_pull|$owner'`; `buildVisitPullService({required AcsBackend backend, required VisitStore localVisits, required String cursorOwner, SyncCursorStore? cursorStore})`.

- [ ] **Step 1: Testes que falham**

```dart
test('o cursor de A não vale para B', () async {
  await cursorA.write(DateTime.utc(2026, 10, 3));
  expect(await cursorB.read(), isNull);          // B começa do epoch
  expect(await cursorA.read(), DateTime.utc(2026, 10, 3));
});
test('gravar o cursor de B não altera o de A', () async { /* idem invertido */ });
test('pullAndMerge de B usa since=epoch mesmo com cursor de A gravado', () async {
  // FakeAcsBackend.pullVisits guarda o `since` recebido
});
test('dedupe de localId do pull enxerga só a fila do dono', () async {
  // visita local-a1 na fila de A; B recebe do servidor uma entrada com o mesmo localId
  // → para B NÃO é duplicada (não existe na fila de B) e aparece em lastPulled
});
```

- [ ] **Step 2:** `flutter test test/sync_cursor_store_test.dart test/visit_pull_service_test.dart` → FAIL.
- [ ] **Step 3: Implementar** — `_visitsPullKey` vira função `'visits_pull|$owner'`; remover do código a leitura da chave legada (D3: o cursor legado fica órfão, comente isso). Atualizar a fábrica (parâmetro `cursorOwner` obrigatório) e os testes existentes que a chamam.
- [ ] **Step 4:** `flutter test test/sync_cursor_store_test.dart test/visit_pull_service_test.dart test/visit_pull_service_factory_test.dart && flutter analyze` → PASS.
- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): cursor do visits.pull por usuário e microárea"
```

---

### Task 4: Fila e pull resolvidos por sessão; sincronizador só com a sessão do dono

**Files:**
- Modify: `apps/acs/lib/core/services/visit_queue_factory.dart`
- Modify: `apps/acs/lib/core/services/backend_visit_synchronizer.dart`
- Modify: `apps/acs/lib/app/app.dart` (`SinalAcsApp` ~30-130, `LoginScreen` e `_openShell`, os pontos que constroem `LoginScreen(...)`/`AcsHomeShell(...)` com `visitQueue`/`visitPullService`)
- Modify: `apps/acs/lib/main.dart` (nada a injetar além do que o app já resolve; conferir)
- Test: `apps/acs/test/visit_owner_flow_test.dart` (novo), ajustes em `test/login_flow_test.dart` e `test/session_resume_test.dart` se a assinatura de `LoginScreen` mudar

**Interfaces:**
- Consumes: `VisitStorage`, `InMemoryVisitStorage`, `SqlCipherVisitStorage` (Task 2); `buildVisitPullService(..., cursorOwner:)` (Task 3); `AuthSession.userId`, `AuthSession.microAreaId`.
- Produces:
  ```dart
  /// Fila + pull de UM dono, prontos para o painel dele.
  class OwnerVisitScope {
    const OwnerVisitScope({required this.queue, required this.pullService});
    final OfflineVisitQueue queue;
    final VisitPullService pullService;
  }
  typedef VisitScopeResolver = OwnerVisitScope Function(AuthSession session);

  OfflineVisitQueue buildVisitQueue({required AcsBackend backend, required VisitStore store, required String ownerId});
  class BackendVisitSynchronizer { BackendVisitSynchronizer({required AcsBackend backend, required String ownerId}); }
  // SinalAcsApp({..., VisitStorage? visitStorage, VisitScopeResolver? visitScopeResolver})
  ```

- [ ] **Step 1: Testes que falham** (`visit_owner_flow_test.dart`; use `InMemoryVisitStorage` real e `FakeAcsBackend`/`FakeRpcServer` conforme `session_resume_test.dart`; dados sintéticos):

```dart
testWidgets('Sair e entrar com OUTRO ACS: o novo não vê, não envia nem descarta a visita do anterior', (t) async {
  // A entra, registra 1 visita pendente e tem 1 recusada; sai ('Sair e encerrar o turno').
  // B entra: pendingCount == 0, rejectedCount == 0, tela 'Visita' sem as visitas de A;
  // 'Sincronizar agora' de B não chama visits.sync com o localId de A;
  // discardRejected (botão da tela) de B não altera o armazenamento de A:
  expect(storage.forOwner('acs-a').load(), completion(hasLength(2)));
});

testWidgets('o mesmo ACS que sai e volta recupera as próprias visitas', (t) async { ... });

test('BackendVisitSynchronizer recusa enviar com a sessão de outro usuário', () async {
  final backend = FakeAcsBackend()..session = _sessao(userId: 'acs-b');
  final sync = BackendVisitSynchronizer(backend: backend, ownerId: 'acs-a');
  await expectLater(sync.push([_visita('local-a1')]), throwsA(isA<BackendFailure>()));
  expect(backend.syncedBatches, isEmpty);  // nada saiu
});

test('a fila de A em voo, com B logado: o lote de A continua PENDENTE (não é enviado nem perdido)', () async {
  final fila = OfflineVisitQueue(store: storage.forOwner('acs-a'), synchronizer: BackendVisitSynchronizer(backend: backend, ownerId: 'acs-a'));
  await fila.add(_visita('local-a1'));
  backend.session = _sessao(userId: 'acs-b');
  final r = await fila.sync();
  expect(r.kind, SyncOutcomeKind.error);
  expect(fila.pendingCount, 1);
});

testWidgets('login de outro usuário pelo bloqueio ("Entrar com senha") também troca a fila', (t) async { ... });
testWidgets('retomada de sessão na partida abre a fila do dono da sessão retomada', (t) async { ... });
```

- [ ] **Step 2:** `flutter test test/visit_owner_flow_test.dart` → FAIL.
- [ ] **Step 3: Implementar**
  - `BackendVisitSynchronizer`: no início de `push`, `if (backend.session?.userId != ownerId) throw const BackendFailure('A sessão atual não é a dona destas visitas. Entre com a conta que registrou as visitas.')` (recuperável: o lote fica pendente — a `OfflineVisitQueue.sync` já converte exceção em `SyncOutcomeKind.error` sem tocar na fila).
  - `buildVisitQueue({backend, store, ownerId})` passa `ownerId` ao sincronizador. `store` deixa de ter padrão que abre `SqlCipherVisitStore` sem dono (remova o padrão; o app sempre passa).
  - `SinalAcsApp`: `late final VisitStorage _storage = widget.visitStorage ?? SqlCipherVisitStorage(keyStore: SecureStorageDatabaseKeyStore())`; mapa `Map<String, OwnerVisitScope> _scopes` (chave `userId|microAreaId`); `OwnerVisitScope _scopeFor(AuthSession s)`: se `widget.visitScopeResolver != null` usa-o; **senão, se `widget.visitQueue`/`widget.visitPullService` (seam de teste, D5) foram injetados, devolve esses**; senão constrói `queue = buildVisitQueue(backend, store: _storage.forOwner(s.userId), ownerId: s.userId)` e `pullService = buildVisitPullService(backend, localVisits: _storage.forOwner(s.userId), cursorOwner: '${s.userId}|${s.microAreaId}')`, memoizados. Remover `_visitStore`, `_visitQueue`, `_visitPullService` fixos.
  - `LoginScreen` deixa de receber `visitQueue`/`visitPullService` e recebe `visitScopeFor` (`VisitScopeResolver`); `_openShell(session)` (e o `pushAndRemoveUntil` do outro usuário) usa `final scope = widget.visitScopeFor(session)` para montar o `AcsHomeShell(visitQueue: scope.queue, visitPullService: scope.pullService, ...)`. Os pontos que reconstroem `LoginScreen` (reauth por sessão expirada em `_sessionExpired`, reauth por bloqueio em `_reauthForLock`, logout) passam o **mesmo** resolvedor. O caso de reauth do **mesmo** usuário continua só fazendo `pop` (painel e fila preservados).
  - Chame `restore()` da fila nova no `initState` do shell como hoje (`_restoreVisits`); confirme que a fila de um dono já restaurado e memoizado não é restaurada duas vezes (`_restored` já protege).
  - Mensagem do diálogo "Sair": manter ("As visitas ainda não sincronizadas continuam salvas neste aparelho") — agora é literalmente verdadeira por dono; acrescente "e só aparecem quando você entrar de novo".

- [ ] **Step 4: Rodar a suíte inteira**

Run: `cd apps/acs && flutter analyze && flutter test`
Expected: tudo verde (os testes que injetam `visitQueue`/`visitPullService` seguem pelo seam D5).

- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): fila e pull de visitas resolvidos por sessão; sincronizador recusa sessão de outro dono"
```

---

## Parte C — Envio do que está preso no aparelho (backend + app)

### Task 5: Backend — autoria desconhecida e `visits.syncLegacy`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/visit.spy.yaml` (`acsId` nullable; `authorship`; `originDeviceId`)
- Create: `backend/sinalacs_server/lib/src/models/enums/visit_authorship.spy.yaml`
- Generated: `lib/src/generated/**`, `migrations/<timestamp>/**`, `backend/sinalacs_client/**`
- Modify: `backend/sinalacs_server/lib/src/application/visits/visit_sync_service.dart` (`VisitRecord.acsId` nullable, `syncLegacy`, `authorship` no `pull`)
- Modify: `lib/src/infrastructure/database/orm_visit_store.dart` (mapear os campos novos)
- Modify: `lib/src/endpoints/visits_endpoint.dart` (`syncLegacy`)
- Modify: `test/unit/endpoint_auth_posture_test.dart` **só se** o método novo não chamar `authenticate(...)` (ele chama; não deve precisar)
- Modify: `spec/lgpd_data_audit.md` (colunas novas de `visits`)
- Test: `test/unit/visit_sync_service_test.dart` (ou o arquivo existente do serviço — achar com `grep -l VisitSyncService test/unit`), `test/integration/visit_legacy_sync_test.dart` (novo)

**Interfaces:**
- Produces (modelo): `enum VisitAuthorship { acs, legacyUnclaimed }`; `Visit.acsId: UuidValue?` (nulo só quando `authorship == legacyUnclaimed`); `Visit.authorship: VisitAuthorship` (default `acs`); `Visit.originDeviceId: String?`.
- Produces (RPC): `visits.syncLegacy(Session, {required String accessToken, required String deviceId, required List<VisitSyncEntry> visits}) → List<VisitSyncResult>`.
- Produces (serviço): `Future<List<VisitSyncResult>> VisitSyncService.syncLegacy({required AuthenticatedUser transporter, required String deviceId, required List<VisitSyncEntry> entries})`.

- [ ] **Step 1: Testes que falham** (unit com o store falso já usado no arquivo de teste do serviço; integração no padrão de `institutional_mfa_test.dart`). Casos:

```dart
test('syncLegacy grava authorship legacyUnclaimed, acsId nulo e originDeviceId', ...);
test('syncLegacy NÃO grava o transportador como autor (acsId permanece nulo)', ...);
test('visita legada de paciente de OUTRA microárea: rejected, nada gravado', ...);
test('mesmo localId reenviado: idempotente (synced, sem duplicar, sem mudar autoria)', ...);
test('localId que já existe como visita COM autor ACS: conflito/rejected, autoria original preservada', ...);
test('papel diferente de acs, sem microárea ou conta inativa: StateError (AlertPermissionException no endpoint)', ...);
test('cada lote gera audit_logs visit_legacy_sync com o transportador, sem conteúdo clínico', ...);
test('pull entrega a visita legada à microárea sem expor autor (campo acsId ausente)', ...);
```

- [ ] **Step 2: Rodar e ver falhar** — `cd backend/sinalacs_server && dart test test/unit` (+ `dart test test/integration/visit_legacy_sync_test.dart`) → FAIL.
- [ ] **Step 3: Implementar** — YAML:

```yaml
### visit_authorship.spy.yaml
enum: VisitAuthorship
values:
  - acs
  - legacyUnclaimed
```

`visit.spy.yaml`: `acsId: UuidValue?, relation(parent=acs)`; acrescentar
```yaml
  ### `legacyUnclaimed` = visita gravada no aparelho antes de existir dono (migração v7):
  ### a autoria é desconhecida e `acsId` é nulo. NUNCA preencher `acsId` com quem transportou.
  authorship: VisitAuthorship, default=acs
  originDeviceId: String?
```
`serverpod generate && serverpod create-migration`. No serviço: `syncLegacy` reaproveita a validação de `sync` (UUIDs, território do paciente × `transporter.microAreaId`, versão, idempotência por `localId`) mas persiste com `authorship: legacyUnclaimed`, `acsId: null`, `originDeviceId: deviceId`; o ramo `existing.acsId != acsId` do `sync` normal passa a tratar `existing.acsId == null` como "visita sem autor": o ACS comum que reenvia o mesmo `localId` **não** a reivindica (`rejected`). Auditoria `AuditEvent(userId: transporter.id, actionType: 'write', resourceType: 'visit_legacy', result: 'visit_legacy_sync')`. Verificar todos os usos de `visit.acsId` (`grep -rn "acsId" lib/src/application/visits lib/src/infrastructure`) — o compilador aponta os que quebram com o tipo nulo.
- [ ] **Step 4: Rodar a suíte do backend** — `dart analyze && dart test` → PASS (a contagem do `validation_report` pode mudar: `python3 scripts/qa/contagem_validation_report.py`).
- [ ] **Step 5: Commit**

```bash
git add backend spec/lgpd_data_audit.md
git commit -m "feat(visits): visitas de autoria desconhecida (legado v7) e visits.syncLegacy"
```

---

### Task 6: Backend — token de envio diferido (`acs_upload_tokens`)

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/acs_upload_token.spy.yaml`
- Modify: `lib/src/models/api/development_login_result.spy.yaml` (`uploadToken: String?`)
- Create: `lib/src/application/auth/upload_token_service.dart`
- Create: `lib/src/infrastructure/database/orm_upload_token_store.dart`
- Modify: `lib/src/runtime/alert_runtime.dart` (`uploadTokenServiceFor(session)`)
- Modify: `lib/src/endpoints/auth_endpoint.dart` (emitir no `loginInstitutional`), `lib/src/endpoints/visits_endpoint.dart` (`syncDeferred`, `revokeUploadToken`)
- Modify: `test/unit/endpoint_auth_posture_test.dart` (`AuthEndpoint` não muda de postura; `VisitsEndpoint.syncDeferred`/`revokeUploadToken` autenticam por token próprio, **não** por `authenticate(...)` → entram na allowlist com justificativa)
- Modify: `spec/lgpd_data_audit.md` (`acs_upload_tokens`)
- Test: `test/unit/upload_token_service_test.dart`, `test/integration/upload_token_test.dart`

**Interfaces:**
- Produces (tabela): `acs_upload_tokens(id, userId→users, tokenHash unique, deviceId, issuedAt, expiresAt, revokedAt?)`.
- Produces (serviço):
  ```dart
  class UploadTokenService {
    static const lifetime = Duration(days: 7);
    static const deniedMessage = 'Envio não autorizado. Entre novamente.';
    Future<String> issue(AuthenticatedUser user, {DateTime? now});       // revoga o token anterior do mesmo (userId, deviceId)
    Future<AuthenticatedUser> resolve({required String uploadToken, required String deviceId, DateTime? now});
        // devolve o usuário com microAreaId RELIDA do banco; lança SessionExpiredException(deniedMessage) em
        // qualquer recusa (desconhecido, vencido, revogado, aparelho diferente, conta inativa/sem microárea)
    Future<void> revoke(String uploadToken, {DateTime? now});            // idempotente
  }
  ```
- Produces (RPC): `DevelopmentLoginResult.uploadToken` (`String?`, só ACS com `deviceId` real); `visits.syncDeferred(Session, {required String uploadToken, required String deviceId, required List<VisitSyncEntry> visits}) → List<VisitSyncResult>` (usa o mesmo `VisitSyncService.sync` com o usuário resolvido: **autoria do dono**, território do dono); `visits.revokeUploadToken(Session, {required String uploadToken}) → void`.

- [ ] **Step 1: Testes que falham** — unit com store em memória (mesmo estilo de `refresh_token_service_test.dart`): `issue` guarda só o hash; `resolve` relê a microárea; aparelho diferente, vencido (7 dias + 1 s), revogado, conta inativa, sem microárea e token desconhecido → **mesma** `SessionExpiredException`; `issue` revoga o anterior do mesmo (usuário, aparelho); `revoke` idempotente. Integração (Postgres real, endpoints): login com `deviceId` devolve `uploadToken`; sem `deviceId` devolve nulo; `syncDeferred` grava a visita **com `acsId` = dono do token** e `authorship = acs`; **token de A com paciente de outra microárea → `rejected`**; token de A **não** consegue gravar visita cujo `localId` já pertence a B (`rejected`); `syncDeferred` com sessão de A já encerrada (logout, refresh revogado) **continua funcionando** (D7); depois de `revokeUploadToken` recusa.
- [ ] **Step 2:** `dart test test/unit/upload_token_service_test.dart` → FAIL.
- [ ] **Step 3: Implementar** — espelhar `RefreshTokenService`/`OrmRefreshTokenStore` (token = 32 bytes `Random.secure()` base64url, SHA-256 hex, `UPDATE`/`INSERT` em uma instrução; reutilize helpers em vez de copiar se já houver um gerador de token comum — procurar em `application/auth`). `AuthEndpoint.loginInstitutional`: após o refresh token, `uploadToken = temAparelho ? await runtime.uploadTokenServiceFor(session).issue(user) : null`. Auditoria `upload_token_issued` / `upload_token_denied_*` / `visit_deferred_sync` em `audit_logs` (sem token, sem conteúdo clínico).
- [ ] **Step 4:** `serverpod generate && serverpod create-migration`; `dart analyze && dart test` → PASS.
- [ ] **Step 5: Commit**

```bash
git add backend spec/lgpd_data_audit.md
git commit -m "feat(auth): token de envio diferido do ACS e visits.syncDeferred com a autoria do dono"
```

---

### Task 7: App — `DeferredFlushService` (legado + donos com token) e gatilhos

**Files:**
- Create: `apps/acs/lib/core/security/upload_token_store.dart` (interface + `MemoryUploadTokenStore`) e `apps/acs/lib/core/security/secure_upload_token_store.dart` (Keystore, **separado** para não puxar `flutter_secure_storage` para a VM — mesmo padrão de `secure_session_token_store.dart`)
- Create: `apps/acs/lib/core/services/deferred_flush_service.dart`
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`AcsBackend`: `syncLegacyVisits`, `syncDeferredVisits`, `revokeUploadToken`; `login()` grava o `uploadToken` por dono), `MisconfiguredBackend`, `test/support/fakes.dart` (`FakeAcsBackend`), `test/support/fake_rpc_server.dart`
- Modify: `apps/acs/lib/app/app.dart` (instanciar o serviço no `SinalAcsApp`; disparar nos gatilhos), `apps/acs/lib/main.dart`
- Test: `apps/acs/test/deferred_flush_service_test.dart` (novo), `apps/acs/test/upload_token_store_test.dart`

**Interfaces:**
- Consumes: `VisitStorage.forOwner`, `VisitStorage.legacy` (Task 2); RPCs `visits.syncLegacy`, `visits.syncDeferred`, `visits.revokeUploadToken`, `DevelopmentLoginResult.uploadToken` (Tasks 5–6); `DeviceIdStore`.
- Produces:
  ```dart
  abstract interface class UploadTokenStore {
    Future<String?> read(String ownerId);
    Future<void> write(String ownerId, String token);
    Future<void> clear(String ownerId);
    Future<List<String>> owners();          // donos com token guardado
  }
  class FlushReport { final int sent; final int remaining; final List<String> blockedOwners; }
  class DeferredFlushService {
    DeferredFlushService({required AcsBackend backend, required VisitStorage storage,
        required UploadTokenStore tokens, required DeviceIdStore deviceIds});
    /// Sobe, nesta ordem: (1) legado, via a sessão ATUAL como transporte; (2) a fila de cada dono que tem
    /// token de envio, via `syncDeferred`; (3) revoga e apaga o token de todo dono cuja fila zerou.
    /// Uma chamada por vez (single-flight). Nunca lança: erros viram `remaining`/`blockedOwners`.
    Future<FlushReport> flushAll();
    Future<int> pendingElsewhere(String currentOwnerId);   // visitas de OUTROS donos + legado (só contagem)
  }
  ```

- [ ] **Step 1: Testes que falham** (`InMemoryVisitStorage`, `FakeAcsBackend` com lotes gravados, `MemoryUploadTokenStore`):

```dart
test('legado sobe pela sessão atual e SAI do aparelho só depois do synced', ...);
test('legado de outra microárea: rejected → continua em quarentena', ...);
test('fila de A sobe com o token de A mesmo com B logado, e a autoria enviada é a de A', ...);
test('depois que a fila de A zera, o token de A é revogado no servidor e apagado do Keystore', ...);
test('erro de rede no meio: nada é apagado; o próximo flushAll reenvia o mesmo localId (idempotente)', ...);
test('token de A recusado (vencido/revogado): a fila de A permanece, A entra em blockedOwners', ...);
test('app morto depois do 200 e antes de apagar: o reenvio do mesmo localId volta synced e a linha é apagada', ...);
test('flushAll simultâneos viram uma só execução (single-flight)', ...);
test('flushAll nunca envia visita de A com o token de B (verifica o token usado por lote)', ...);
test('pendingElsewhere conta outros donos + legado e não expõe conteúdo', ...);
```

- [ ] **Step 2:** `flutter test test/deferred_flush_service_test.dart` → FAIL.
- [ ] **Step 3: Implementar** — reaproveitar a **própria `OfflineVisitQueue`** (fila temporária por dono, sobre `storage.forOwner(owner)`, com um sincronizador que chama `syncDeferred`) para não duplicar a semântica de `synced/conflict/rejected/error` — a visita só sai do disco quando o resultado é `synced`. O sincronizador diferido é uma classe pequena `DeferredVisitSynchronizer(backend, ownerToken, deviceId)`; o legado usa o mesmo desenho com `syncLegacyVisits` e `LegacyVisitStore.remove`. `BackendClient.login()`: depois de `refreshToken`, `if (result.uploadToken != null) await _uploadTokens.write(session.userId, result.uploadToken)` **dentro** da seção crítica da Task 1. Gatilhos em `app.dart`: (a) depois de abrir o painel (`_openShell`) e na retomada; (b) `connectivity_plus` `onConnectivityChanged` quando passa a haver rede (já usado no app — reaproveitar o ouvinte existente); (c) chamado pelo "Sair" (Task 8). Nenhum gatilho bloqueia a UI nem mostra conteúdo clínico.
- [ ] **Step 4:** `flutter analyze && flutter test` → PASS.
- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): envio diferido de visitas (legado e de ACS que saiu) com a autoria correta"
```

---

### Task 8: App — "Sair" que envia antes de sair, e "Limpar este aparelho"

**Files:**
- Modify: `apps/acs/lib/app/app.dart` (`_logout`, aba Ajustes, novo botão e diálogo de wipe)
- Modify: `apps/acs/lib/core/database/encrypted_database.dart` / `sqlcipher_visit_store.dart` (`VisitDatabase.wipe()`: apaga todas as tabelas de dados do app **e** a chave do Keystore não — só as linhas; ver abaixo)
- Test: `apps/acs/test/session_resume_test.dart` (diálogo do Sair), `apps/acs/test/device_wipe_test.dart` (novo)

**Interfaces:**
- Consumes: `DeferredFlushService.flushAll()` / `pendingElsewhere()` (Task 7), `AcsBackend.logout()`.
- Produces: `VisitDatabase.wipeAllData()` — `DELETE` de `offline_visits`, `sync_cursor`, `micro_area_cache`, `micro_area_cache_meta` em uma transação (o arquivo e a chave são mantidos; é limpeza de dados, não troca de chave); `UploadTokenStore.clearAll()`.

- [ ] **Step 1: Testes que falham**
  - "Sair": com visitas pendentes do próprio ACS e rede, o app chama `flushAll()` **antes** de `logout()`; se zerar, o diálogo diz "Tudo foi enviado"; se não zerar (offline), o texto diz **quantas** continuam no aparelho, "seguem protegidas e sobem sozinhas quando a conexão voltar" e o botão vira "Sair mesmo assim" (os alertas não confirmados continuam contados como hoje). O token de envio do dono **não** é apagado enquanto houver pendência.
  - "Limpar este aparelho": botão em Ajustes; ao tocar roda `flushAll()`; se `remaining == 0` mostra confirmação ("Isto apaga as visitas já enviadas, o cache da microárea e as chaves de envio deste aparelho") e faz o wipe, `logout()` e volta ao login; se `remaining > 0` **bloqueia** com a contagem e o motivo ("N visitas ainda não foram enviadas; conecte e tente de novo. Se não puderem ser enviadas, procure a coordenação"). Teste: wipe com 1 visita não enviada **não apaga nada** (conferir o armazenamento); wipe com tudo enviado deixa as tabelas vazias; o painel e o feed MQTT são encerrados pelos caminhos normais de `dispose`.
- [ ] **Step 2:** `flutter test test/device_wipe_test.dart test/session_resume_test.dart` → FAIL.
- [ ] **Step 3: Implementar** — `_logout`: `final report = await flush.flushAll()` com indicador de progresso (já existe `logout_progress`), depois `backend.logout()`. Aviso curto e honesto no diálogo; não bloquear o "Sair" por falha de envio (offline é o caso de campo). Wipe só com `remaining == 0`.
- [ ] **Step 4:** `flutter analyze && flutter test` → PASS (incluir `text_scale_test` para o botão novo em 200%).
- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): Sair envia antes de sair; Limpar este aparelho só com tudo enviado"
```

---

## Parte D — Prova e documentação

### Task 9: Prova no emulador e documentação

**Files:**
- Modify: `apps/acs/integration_test/encrypted_storage_test.dart` (donos distintos + legado no SQLCipher real), `apps/acs/integration_test/full_journey_e2e.dart` (e `scripts/qa/acs_full_e2e.sh` se precisar de verificações psql)
- Modify: `PROGRESS.md` (item **(g)** e a corrida do login fechados; novas pendências), `apps/CLAUDE.md`, `backend/CLAUDE.md`, `CLAUDE.md` raiz, `spec/lgpd_design.md`, `spec/lgpd_data_audit.md`

- [ ] **Step 1: Teste de armazenamento no emulador** — dois donos + quarentena no mesmo arquivo SQLCipher real; migração de um banco v6 criado no aparelho preserva as linhas em quarentena; o arquivo não contém o texto das notas em claro.
- [ ] **Step 2: E2E no emulador** (`emulator-5554` já ligado; skill `validacao-e2e`): A (com MFA) registra visita offline, sai; B entra e **não** a vê; a conexão volta, `flushAll` sobe a visita de A **com `acsId` de A** (verificar por `psql` em `visits`); uma visita legada plantada no banco v6 do aparelho sobe com `authorship = legacyUnclaimed` e `acsId` nulo. Rodar `./scripts/qa/e2e.sh --emulator` e `./scripts/qa/acs_full_e2e.sh`. Se algo não puder rodar, dizer o quê e por quê.
- [ ] **Step 3: Documentação** — o que muda de verdade: schema v7 e quarentena; `visits.syncLegacy` e `syncDeferred`; `acs_upload_tokens`; **o que NÃO foi feito e por quê**: (i) WorkManager/execução em background do SO (D8); (ii) wipe forçado por supervisor (D9: não há login de supervisor); (iii) token de envio vencido (7 dias) deixa a fila do dono presa — o wipe fica bloqueado; (iv) retenção LGPD de donos que nunca voltam continua dependendo do envio. Corrigir `spec/lgpd_design.md` (a política de retenção local passa a citar o envio + wipe).
- [ ] **Step 4: Verificação final** — `cd backend/sinalacs_server && dart analyze && dart test`; `cd apps/acs && flutter analyze && flutter test`; `./scripts/qa/ci_invariants.sh`; `python3 scripts/qa/contagem_validation_report.py`; `scripts/qa/check_documentation_links.sh` → tudo verde.
- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs(acs): fecha fila de visitas por dono, corrida do login e retenção; registra o que segue aberto"
```

---

## Auto-revisão

- **Cobertura da demanda:** corrida do `login()` = Task 1. Fila sem dono = Tasks 2–4. Pontos novos: **legado** não é mais adotado — quarentena (Task 2) + envio como "autoria desconhecida" (Task 5, D4) + upload no app (Task 7); **retenção** = isolamento por dono (Tasks 2–4) + envio desvinculado da sessão (Tasks 6–7, D7) + envio no "Sair" e wipe seguro (Task 8, D9).
- **Onde NÃO segui o pedido, e por quê (para você decidir):**
  1. *"Client Credentials / Device Token"* — não existe essa credencial no backend, e uma credencial só do aparelho não prova **quem** fez a visita. Troquei por um token de envio **por ACS**, de escopo único e 7 dias (D7), que mantém a autoria correta. Quem preferir a credencial de aparelho deve aceitar que a autoria vira "desconhecida" para tudo.
  2. *Worker em background* — exigiria `workmanager` (pacote fora de `spec/stack.md`) e um isolate sem UI, sem prova no emulador aqui. Entrego disparo em primeiro plano (login, retomada, conexão voltou, antes do Sair). É decisão sua autorizar o pacote num plano à parte.
  3. *Wipe por Supervisor* — não há login de supervisor/coordenador no sistema. O wipe é do ACS e só abre com tudo enviado; o que não subir bloqueia o wipe e vira pendência.
  4. *"Se o banco não for criptografado"* — o banco já é SQLCipher (INV-04); o risco que sobra é de **retenção de dado de terceiros**, que o plano reduz por envio + wipe.
- **Placeholders:** os testes marcados com `...` nas Tasks 5–8 têm a regra de aceite escrita na linha; o executor os completa seguindo o arquivo de teste vizinho nomeado em cada Task.
- **Consistência de tipos:** `VisitStorage.forOwner`/`legacy` (Task 2) → Tasks 4 e 7; `uploadToken` (Task 6) → Task 7; `DeferredFlushService.flushAll`/`pendingElsewhere` (Task 7) → Task 8; `VisitSyncEntry` não muda (a autoria é decidida no servidor).
- **Riscos assumidos e declarados:** a Task 1 mexe no caminho crítico de autenticação (revisar deadlock de `_exclusive`); as Tasks 5–6 têm migração e mudam o tipo de `Visit.acsId` para nulo (ripple em pull/consultas); token de envio de 7 dias é uma credencial a mais no aparelho — vazamento permite **só** subir visitas do território do dono sob a autoria dele.
