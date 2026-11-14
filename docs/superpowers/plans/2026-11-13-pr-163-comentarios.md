# PR #163 (#151, `open_failed` ambíguo no ACS): parecer e comentários a publicar

Textos da revisão da PR #163 (`fix/issue-151-open-failed-ambiguo`, autor `vinimartinsufrr`, base `develop`, commit `01985f1`). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/163/comments` (inlines, um por chamada). Plano: `2026-11-13-prs-156-163-revisao.md`, Task 4.

Veredito proposto: **Aprovar com observações** (`gh pr review --approve`). Não há bloqueante. O teste pedido pela revisão sobre o `_persist` (a visita enviada não ressuscita) foi escrito e passa; o único pedido é tirar uma contagem de testes do `PROGRESS.md`.

---

## Parecer

Revisei a PR contra a issue #151, a decisão D2d do app do paciente (`docs/superpowers/plans/2026-11-03-issue-136-cifra-local-paciente.md`) e as decisões D1–D9 da fila por dono (`docs/superpowers/plans/2026-10-03-fila-de-visitas-por-dono-e-corrida-do-login.md`). Como a PR mexe em `offline_visit_queue.dart`, conferi em especial a regra do `CLAUDE.md`: a semântica de retentativa, fila e conflito tem de ser preservada. Ela é preservada. Além disso, a PR fecha uma perda de dado que já existia: com o `restore()` falho, o primeiro `save` apagava do disco as visitas que nunca tinham sido carregadas.

| Critério da #151 | Evidência |
|---|---|
| Com a chave presente, um erro de abertura nunca move a fila de lado nem apaga a chave sem um sinal inequívoco | No diff, só três chamadas movem para `.recuperado` ou apagam a chave. (1) `sqlcipher_visit_store.dart:95`, `_moveAside`, guardada por `stored == null && arquivo existe`. Não há `delete` nesse ramo, e a chave nova só é criada depois de mover. (2) e (3) `:156` `_moveAside` e `:157` `_keyStore.delete()`, alcançadas só quando `kind == wrongKey && secondKind == wrongKey`, ou seja, código 26 ou "file is not a database" nas duas tentativas. Se mover falhar, o erro sobe antes do `delete`. O `delete` do `_destroyOnce` (`:241`) não foi alterado e só roda pela limpeza remota (#81) ou pelo "Limpar este aparelho" depois do `WipeBlocked`. |
| Teste que simula `open_failed` por E/S ou permissão e prova que a fila e a chave continuam intactas | `test/open_failed_ambiguity_test.dart`: "open_failed persistente (E/S ou permissão): falha fechada, fila e chave intactas" compara o arquivo byte a byte (`readAsBytes()` antes e depois), confere a chave e a ausência de `.recuperado`. No aparelho, `integration_test/encrypted_storage_test.dart` "#151: arquivo sem permissão…" faz `chmod 000` de verdade (não rodado aqui, ver Registros). |
| Decisão registrada em `apps/CLAUDE.md` e `PROGRESS.md` | O parágrafo do `database_key_store.dart` em `apps/CLAUDE.md` foi reescrito. No `PROGRESS.md` há a seção nova "`open_failed` ambíguo no app do ACS (#151)", e o item aberto da revisão de 2026-10-04 foi riscado. |

**O que rodei em Linux** (Flutter estável, worktree limpo da branch, commit `01985f1`):

- `flutter analyze` (ACS): só o aviso `asset_directory_does_not_exist` de `assets/certs/`, que é o diretório gitignorado; não vem desta PR.
- `flutter test test/open_failed_ambiguity_test.dart test/visit_storage_owner_test.dart`: 42 passam.
- `flutter test` completo (ACS): 822 passam em 8 min 47 s, inclusive `mqtt_tls_refused_test.dart`. Isso confirma que as falhas descritas no corpo da PR são do ambiente Windows.
- `bash scripts/qa/check_documentation_links.sh`: nada novo. O único "ausente" é `graphify-out`, em `AGENTS.md`, que já está assim em `develop`.
- **Teste escrito na revisão** (não commitado; o texto está no Inline 3): "visita enviada e apagada do disco nesta execução não ressuscita no próximo `_persist`". Disco com A e B; o `restore` falha; A entra pela RAM com o mesmo `localId` e nada é gravado; A sobe, e só então o `_persist` lê o disco e junta. Esperado: B volta para a fila, A não volta, e o disco fica só com B. **Passa** (`flutter test test/open_failed_ambiguity_test.dart`: `+11: All tests passed!`).
  - Para conferir que o teste pega o defeito, tirei `_synced` do conjunto `known` em `_readUnreadDisk`: o teste reprova com `Expected ['B'], Actual ['A', 'B']`.
  - Com a `offline_visit_queue.dart` da `develop`, ele reprova com `Expected ['B'], Actual []`, junto com "não grava por cima…" da PR, porque o `save` às cegas apaga B do disco. Isso confirma o "achado no caminho" que a PR descreve.
- CI: 9 de 9 verdes, inclusive `android-e2e`.

**Pontos que conferi no código e aprovo:**

- **Classificação** (`classifyDatabaseOpenError`): código 26 e "file is not a database" contam como `wrongKey`; `isOpenFailedError()` conta como `ambiguousOpenFailure`; todo o resto conta como `other`, que sobe na hora sem nova tentativa. Sinais mistos falham fechado: código 26 seguido de `open_failed` lança `VisitDatabaseOpenFailed`, e `open_failed` seguido de `other` relança o `other`. Há teste para os dois casos.
- **`SQLITE_NOTADB` nas duas tentativas** (ponto (b) do plano): a condição em `:129` exige os dois `wrongKey`, e a mecânica antiga (single-flight, cópia única, falha ao mover) continua exercitada pelo código 26 em `visit_storage_owner_test.dart`.
- **Fusão no `_persist`:**
  - `known` junta pendentes, conflitos, recusadas e `_synced`, e é calculado **depois** do `await load()`, de modo que um `_applyOutcomes` concorrente já está refletido nele.
  - A segunda checagem de `_diskUnread` evita juntar duas vezes.
  - O `_sealed` é conferido de novo depois da leitura, o que preserva a #81.
  - O `_applyOutcomes` refaz `_pending` como `stillPending + arrived`, e as visitas que vieram do disco durante um envio em voo entram em `arrived`; o C-1 de 2026-10-04 continua fechado.
  - Conflitos e recusadas que vêm do disco voltam para as próprias listas, porque a separação é a mesma do `restore`.
- **`storage_error`** (ponto (d)): continua vindo só de `persistenceFailed` (`app.dart:1994`) e tem banner próprio, separado do banner do broker. `login_flow_test.dart` segue verde.
- **`VisitDatabaseOpenFailed` não é tratado como chave errada por ninguém** (ponto (e)):
  - `DeferredFlushService` usa `_safe(...)`, que devolve `null`, e com `null` não revoga o token nem apaga nada.
  - "Limpar este aparelho" (`care.wipe` → `wipeAllData` → `open()`) cai no `catch` genérico e mostra "não limpou". É o comportamento certo, porque o disco não lido pode ter visitas.
  - A limpeza remota (`_eraseDevice` → `destroyAll` → `destroy`) não abre o banco, então é de fato a saída para uma chave presente e errada, como dizem a PR e o `apps/CLAUDE.md`.
- **Asserções alteradas em `visit_storage_owner_test.dart`** (ponto (c)): todas têm motivo no corpo da PR.
  - Chave presente em vez de custódia vazia: com o arquivo existente, chave ausente agora é o sinal 1.
  - Mecânica de recuperação pelo código 26: o `open_failed` não recupera mais.
  - "`open_failed` duas vezes recupera" foi removido do laço e virou o oposto no arquivo novo.
  - "não perde nada" passou a conferir o disco e a ordem `['sobrevive', 'em-campo']`.
  - O laço "UMA vez" continua cobrindo o `open_failed`.
  - Em `visit_pull_service_test.dart`, as duas custódias passaram a ser uma só, com o motivo escrito no comentário.

**Pedidos (pequenos, nesta PR):** tirar a contagem "(10)" do `PROGRESS.md` (Inline 6).

**Sugestões (opcionais):**
- O sinal 1, depois da #162 (Inline 1).
- Ler o disco não lido também no início do `sync` (Inline 3).
- Não deixar o caso `chmod 000` passar em silêncio (Inline 5).

**Registros (só documentam):**
- O caso do emulador (`chmod 000`) não foi rodado nesta revisão: não havia emulador ligado.
- Custódia que devolve string vazia (Inline 4).
- A limpeza local falha fechada com o disco ilegível (Inline 2).

---

## Inline 1 — apps/acs/lib/core/database/sqlcipher_visit_store.dart:94 — sugestão

Sobre o sinal 1 ("chave comprovadamente ausente com o arquivo presente"): a PR #162 (em revisão) passa a excluir o banco e as SharedPreferences do ACS da transferência entre aparelhos e do backup. Depois dela, os cenários que o comentário cita (reinstalação com restauração, transferência entre aparelhos) deixam de trazer o arquivo. Restam casos raros:
- reinstalação com um backup antigo feito antes da #162;
- o Keystore apagado com os dados do app mantidos;
- e o caso que a própria PR lista em "Limites": uma custódia que devolve `null` ou vazio por defeito, sem lançar. Por exemplo, o `flutter_secure_storage` 9.x com `encryptedSharedPreferences`, que eu não verifiquei como se comporta quando a chave-mestra do Keystore some.

Pergunta, não bloqueio: o sinal 1 ainda deve pôr a fila de lado na primeira leitura `null`? Concordo que falhar fechado aqui não ajuda: sem a chave, o arquivo é ilegível de qualquer jeito, e o app ficaria preso em RAM até a limpeza remota. Uma mitigação barata, no espírito da nova tentativa do `open_failed`, é ler a custódia **duas vezes**, com o mesmo `_retryDelay`, antes de mover. Assim, um `null` passageiro não custa a fila. Se ficar como está, sugiro atualizar o comentário e o `apps/CLAUDE.md` com os cenários que restam depois da #162.

---

## Inline 2 — apps/acs/lib/core/database/sqlcipher_visit_store.dart:129 — registro

Conferi as condições de cada chamada que move ou apaga:
- `:95` só roda com chave `null` e arquivo presente;
- `:156` e `:157` só rodam com `wrongKey` nas duas tentativas;
- o `delete` do `_destroyOnce` não foi alterado e só roda por limpeza.

Com a chave presente e um `open_failed`, nenhum caminho toca no arquivo nem na chave. Isso vale também para o "Limpar este aparelho": ele abre o banco primeiro (`wipeAllData` → `open()`), recebe `VisitDatabaseOpenFailed` e mostra "não limpou". É o certo, porque o disco não lido pode ter visitas. A única saída sem reinstalar é mesmo a limpeza remota (`_eraseDevice` → `destroyAll`), que não abre o banco. Vale deixar isso explícito no nome do teste "saída para uma chave de fato perdida", que chama `db.destroy()` direto.

---

## Inline 3 — apps/acs/lib/core/services/offline_visit_queue.dart:527 — sugestão

A fusão está correta. Escrevi na revisão o teste abaixo, para o caso "a visita enviada não ressuscita", e ele passa. Ele reprova se `_synced` sair de `known` (`Expected ['B'], Actual ['A', 'B']`) e reprova com a fila da `develop` (`Expected ['B'], Actual []`). Fica à disposição para entrar em `test/open_failed_ambiguity_test.dart`, se quiser; usa os helpers que o arquivo já tem (`database`, `_openFailed`, `_visit`, `key`, `name`):

```dart
test('visita enviada e apagada do disco nesta execução não ressuscita no próximo _persist', () async {
  // Disco de uma execução anterior com A e B, gravado com a chave presente.
  final storage = SqlCipherVisitStorage(
    keyStore: InMemoryDatabaseKeyStore(initialKey: key),
    databaseName: name,
    allowUnencryptedForTesting: true,
  );
  await storage.forOwner('acs-a').save([_visit('A'), _visit('B')]);
  await storage.close();

  final keys = InMemoryDatabaseKeyStore(initialKey: key);
  // restore (2) + gravação do add (2): o disco segue ilegível até o envio.
  final db = database([for (var i = 0; i < 4; i++) _openFailed()], keys: keys);
  final store = SqlCipherVisitStore.on(db, owner: 'acs-a');
  final queue = OfflineVisitQueue(
    store: store,
    synchronizer: FakeVisitSynchronizer(statusFor: (v) => v.localId == 'A' ? 'synced' : 'error'),
  );

  await queue.restore();
  expect(queue.persistenceFailed, isTrue);
  await queue.add(_visit('A')); // nada gravado: disco não lido
  await queue.sync(); // A sobe; o _persist lê o disco agora e junta

  expect(queue.syncedVisits.map((v) => v.localId), contains('A'));
  expect(queue.pendingVisits.map((v) => v.localId), ['B'], reason: 'B do disco volta; A não');
  expect((await store.load()).map((v) => v.localId), ['B'], reason: 'disco só com B');
  await db.close();
});
```

A sugestão é sobre o momento da leitura. Hoje `_readUnreadDisk` só roda numa **gravação**. Se o `restore` falhou e o ACS não registra nem resolve nada, as visitas que estão só no disco não entram na RAM. Nesse caso o "Sincronizar agora" devolve `empty`, porque `_syncOnce` olha só `_pending`, e o contador mostra 0 pendentes, mesmo depois de o banco voltar a abrir. Nada se perde, e a `develop` era pior: lá essas visitas eram apagadas. Mas o ACS recebe orientações contraditórias: o aviso `storage_error` continua aceso (`persistenceFailed` só apaga num `save` bem-sucedido) e diz "Sincronize antes de fechar o aplicativo", enquanto o "Sincronizar agora" responde que não há nada a enviar. Chamar `_readUnreadDisk()` no começo de `_syncOnce` (ignorando o `false`) faria essas visitas subirem assim que o banco abrir. Se preferir fora desta PR, propus uma issue de continuação.

---

## Inline 4 — apps/acs/lib/core/security/database_key_store.dart:78 — registro

`read()` trata uma string vazia como ausente, e então o sinal 1 põe a fila de lado. É coerente com o `readOrCreate`, que também trata vazio como "criar". O registro serve para lembrar que "ausente" aqui significa "`null` ou vazio, lido sem erro", e não uma prova de que a chave nunca existiu (ver o Inline 1).

---

## Inline 5 — apps/acs/integration_test/encrypted_storage_test.dart:218 — sugestão

Não rodei este caso: não havia emulador ligado. Ele também não entra no `android-e2e` da CI, só no `--full`. Sobre o desenho: se o `chmod` não existir ou for recusado, o teste chama `markTestSkipped` e a bateria `--full` fica verde sem ter provado nada. No Android, o `chmod` do toybox existe e o app é dono do próprio arquivo, então uma recusa aqui indicaria um problema do ambiente, que vale ver vermelho. Sugiro `fail(...)` em vez de pular, ou ao menos um `print` que apareça no relatório do `e2e.sh`.

---

## Inline 6 — PROGRESS.md:1936 — pedido

O `CONTRIBUTING.md` (linha 250) pede para não gravar contagens de testes nos documentos, porque elas envelhecem a cada PR. Peço trocar "`test/open_failed_ambiguity_test.dart` (10):" por "`test/open_failed_ambiguity_test.dart`:" e manter o número só no corpo da PR.

---

## Geral — conferência da semântica da fila

Conferi a regra do `CLAUDE.md` sobre `offline_visit_queue.dart` (retentativa, fila, conflito):
- **Retentativa:** `error` e falha de rede continuam pendentes.
- **Conflito:** sai da retentativa e é persistido com a cópia do servidor; com o disco não lido, um conflito antigo volta para `_conflicts` pela mesma separação do `restore`.
- **Recusada:** continua visível até o descarte explícito.
- **`_sealed`:** é conferido antes e depois da leitura do disco.

A única mudança de comportamento é a pretendida: com o disco ilegível, nada é gravado, e a fila segue em RAM com o `storage_error` aceso. Obrigado também por ter achado e corrigido o `save` às cegas depois de um `restore()` falho. Era perda silenciosa de visita não enviada, e o teste antigo não a via porque olhava só a RAM.

---

## Issues de continuação

### Issue 1 — Fila do ACS: ler o disco não lido também ao sincronizar, não só ao gravar

**Objetivo**

Depois da #151 (PR #163), quando o `restore()` da fila falha, `OfflineVisitQueue` só lê o disco e junta com a RAM (`_readUnreadDisk`) na próxima **gravação**. Se o ACS não registra nem resolve nenhuma visita, as visitas que estão só no disco continuam fora da RAM. Nesse caso o "Sincronizar agora" devolve `empty` e o contador mostra 0 pendentes, mesmo depois de o banco voltar a abrir. Nada se perde (a fila não grava sobre o disco não lido), mas o ACS recebe orientações contraditórias: o aviso `storage_error` continua aceso (`persistenceFailed` só apaga num `save` bem-sucedido, `app.dart:1994`) e diz "Sincronize antes de fechar o aplicativo", enquanto o "Sincronizar agora" responde que não há nada a enviar e o contador mostra 0 pendentes.

**Critério de aceite**

- [ ] `_syncOnce` (ou um gatilho equivalente, como o retorno do app ao primeiro plano) tenta `_readUnreadDisk()` antes de montar o lote; se o disco continuar ilegível, segue como hoje.
- [ ] Teste: `restore` falho com uma visita no disco, o banco volta a abrir, e um `sync()` sem gravação anterior envia essa visita.
- [ ] A semântica de retentativa, fila e conflito continua a mesma (`CLAUDE.md`).

**Referências**

- `apps/acs/lib/core/services/offline_visit_queue.dart` (`_readUnreadDisk`, `_persist`, `_syncOnce`)
- PR #163, comentário inline em `offline_visit_queue.dart:527`
