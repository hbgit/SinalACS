# Issue #82 — Auditoria append-only no banco: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o Postgres passa a recusar `UPDATE`, `DELETE` e `TRUNCATE` em `audit_logs`, `audit_exports` e `audit_chain_checkpoints`; a cadeia HMAC deixa de ser a única defesa (RF17, STRIDE-R).

**Architecture:** uma função PL/pgSQL `sinalacs_audit_append_only()` e um trigger `BEFORE UPDATE OR DELETE OR TRUNCATE … FOR EACH STATEMENT` por tabela, mais `REVOKE … FROM PUBLIC`, num SQL canônico versionado fora de `migrations/` e colado numa migração vazia do Serverpod (no `migration.sql` **e** no `definition.sql`). O Serverpod 3.4.13 instala um banco novo só pelo `definition.sql` da última migração (`migration_manager.dart:190-205`), e o `create-migration` reescreve esse arquivo a partir dos modelos. Por isso um teste de guarda falha quando a última migração perde o bloco, e um script o recoloca. Os testes e o e2e que adulteram a cadeia de propósito passam a fazê-lo como o adversário privilegiado (`SET LOCAL session_replication_role = replica`, só superusuário), que é exatamente quem o trigger não para.

**Tech Stack:** Serverpod 3.4.13 (Dart), PostgreSQL 15, bash, `flutter test integration_test` no emulador (admin).

**Spec:** issue #82 (`gh issue view 82`), origem no item 8 de `docs/auditoria-prd/2026-10-15-lacunas-prd.md`; requisitos em `spec/PRD_system.md` (RF17, linha 150; STRIDE Repudiation, linha 576) e `spec/lgpd_design.md` (LGPD-RT03, linhas 705-711).

**Escopo decidido com o dono (2026-10-25):**
- Trigger + `REVOKE … FROM PUBLIC`. **Sem** separar papéis: o backend segue conectando como `POSTGRES_USER` (superusuário), que ainda contorna o trigger. A separação vira issue de continuação.
- Só o append-only. `audit_exports` ganha o trigger, mas continua **fora** da cadeia; download do CSV e revisão do DPO seguem pendências no `PROGRESS.md`.

## Global Constraints

- Branch: `feat/issue-82-auditoria-append-only` a partir de `develop`; PR contra `develop`.
- Tabelas protegidas, exatamente: `audit_logs`, `audit_exports`, `audit_chain_checkpoints`. `consent_logs` fica fora (pendência registrada, não tarefa).
- Nenhum código de produção faz `UPDATE`/`DELETE`/`TRUNCATE` nessas tabelas hoje (conferido: `orm_audit_trail.dart`, `orm_audit_export_store.dart` e `orm_audit_checkpoint_store.dart` só inserem; o checkpoint usa `ON CONFLICT DO NOTHING`). Nenhuma tarefa pode introduzir um.
- Erro do trigger: `SQLSTATE 42501`, mensagem `tabela de auditoria <tabela> é append-only: <OP> recusado`.
- Postgres 15: sem `CREATE OR REPLACE TRIGGER` nos planos; usar `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` (o bloco tem que ser idempotente).
- Testes de integração: `dart test -j 1` em `backend/sinalacs_server` (banco de teste `localhost:9090`, usuário `postgres`, superusuário).
- `backend/CLAUDE.md` proíbe editar `migrations/` à mão; esta issue abre a **única** exceção documentada (o bloco canônico), registrada na Task 3.
- Nenhum dado real de paciente em teste, log ou captura; commits sem atribuição de IA (regra do `CLAUDE.md`, que prevalece sobre o lembrete de atribuição).
- Texto de documentação e mensagens em português.

## Review Focus

1. **A próxima `serverpod create-migration` apaga o trigger dos bancos novos** (CI, banco de teste recriado, `sinalacs_e2e`, `pg_data/` limpo), porque reescreve o `definition.sql`. Esperado: um teste falha na hora com a instrução de rodar o script. Fixado na Task 2, step 1 (`o definition.sql mais recente instala o append-only`).
2. **Uma recusa do trigger envenena a transação**: dentro do harness com rollback, um `UPDATE` recusado não pode impedir que o `OrmAuditTrail` grave a linha seguinte. Fixado na Task 2 (`depois da recusa, a trilha continua gravando`).
3. **Escritas legítimas que parecem `UPDATE`**: o `INSERT … ON CONFLICT DO NOTHING` do checkpoint e o `INSERT` de `audit_exports` na mesma transação da trilha têm que passar com o trigger. Fixado na Task 2 (`advanceTo e exportação seguem funcionando`).
4. **`UPDATE`/`DELETE` que não casa linha nenhuma** (`WHERE false`) também é recusado — o trigger é por comando, não por linha. Fixado na Task 2.
5. **O atalho privilegiado vaza**: `SET LOCAL` dura até o fim da transação externa do harness, então sem o reset o resto do teste rodaria sem trigger e mascararia regressões. O reset nasce na Task 1; o teste que o prova (`depois do atalho, o trigger volta a valer`) está na Task 2, porque só tem o que medir depois que o trigger existe.

---

### Task 1: Atalho do adversário privilegiado nos testes que adulteram a cadeia

Antes do trigger existir, todo teste que adultera `audit_logs`/`audit_chain_checkpoints` passa a fazê-lo pelo atalho. Sem trigger o atalho é inócuo, então a suíte continua verde; depois da Task 2 ela só continua verde por causa dele.

**Files:**
- Create: `backend/sinalacs_server/test/integration/support/privileged_tamper.dart`
- Modify: `backend/sinalacs_server/test/integration/audit_chain_reader_test.dart` (linhas 136, 176, 208)
- Modify: `backend/sinalacs_server/test/integration/admin_endpoint_audit_chain_test.dart` (linhas 229, 248, 265, 282, 287)
- Modify: `backend/sinalacs_server/test/integration/admin_endpoint_audit_export_test.dart` (linhas 464, 489)
- Modify: `backend/sinalacs_server/test/integration/audit_chain_checkpoint_test.dart` (linhas 153, 178, 213, 248-249 e `limpar` do grupo sem rollback, ~linha 323)

**Interfaces:**
- Produces:
  - `Future<void> adulterarComoSuperusuario(Session session, String sql, {QueryParameters? parameters})` — roda um comando só.
  - `Future<T> comoSuperusuario<T>(Session session, Future<T> Function(Transaction transaction) corpo)` — roda vários (o "backup/restauração" do checkpoint test, o `deleteWhere` do `limpar`).
  - Ambos abrem `session.db.transaction`, executam `SET LOCAL session_replication_role = replica`, o corpo, e num `finally` `SET LOCAL session_replication_role = origin` (o `SET LOCAL` sobrevive ao `RELEASE SAVEPOINT` do harness; sem o reset o resto do teste rodaria sem trigger).
  - Doc comment em português dizendo que isto modela o adversário da §458 de `spec/lgpd_design.md` (superusuário), que o trigger da #82 não para — é o que a cadeia existe para detectar.

- [ ] **Step 1: Criar o helper** em `test/integration/support/privileged_tamper.dart` com as duas funções acima.

- [ ] **Step 2: Trocar cada adulteração direta** listada em Files por `adulterarComoSuperusuario(session, '<mesmo SQL>', parameters: <mesmos parâmetros>)`. No `audit_chain_checkpoint_test.dart`, o laço de "restauração" (linhas 247-254: dois `DELETE` + dois `INSERT … SELECT`) vai inteiro para um `comoSuperusuario`, e o `limpar` do grupo `RollbackDatabase.disabled` vira `comoSuperusuario(s, (t) => AuditChainCheckpoint.db.deleteWhere(s, where: (t) => t.sequence >= base, transaction: t))`. Os `CREATE TEMP TABLE` e `INSERT` diretos ficam como estão.

- [ ] **Step 3: Conferir que nenhuma adulteração direta sobrou**

Run: `cd backend/sinalacs_server && grep -rnE "(UPDATE|DELETE FROM) (audit_logs|audit_exports|audit_chain_checkpoints)" test | grep -v support/privileged_tamper.dart`
Expected: cada linha encontrada está dentro de uma chamada `adulterarComoSuperusuario`/`comoSuperusuario` (conferir no contexto); nenhum `session.db.unsafeExecute` direto.

- [ ] **Step 4: Rodar os quatro arquivos**

Run: `cd backend/sinalacs_server && dart test -j 1 test/integration/audit_chain_reader_test.dart test/integration/admin_endpoint_audit_chain_test.dart test/integration/admin_endpoint_audit_export_test.dart test/integration/audit_chain_checkpoint_test.dart`
Expected: PASS, mesma contagem de antes (rodar uma vez em `develop` antes do Step 2 e anotar).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/test/integration
git commit -m "test(auditoria): adulterações da cadeia como superusuário (#82)"
```

---

### Task 2: Trigger append-only + `REVOKE` numa migração, com guarda de drift

**Files:**
- Create: `backend/sinalacs_server/database/audit_append_only.sql` (fonte canônica)
- Create: `backend/sinalacs_server/migrations/<nova versão>/` (via `serverpod create-migration --force`) e `migration_registry.txt`
- Create: `backend/sinalacs_server/test/integration/audit_append_only_test.dart`
- Modify: `backend/sinalacs_server/test/integration/audit_schema_test.dart` (novo grupo de arquivo e novo caso no banco)
- Test (Review Focus 5): `backend/sinalacs_server/test/integration/audit_append_only_test.dart`

**Interfaces:**
- Consumes: `adulterarComoSuperusuario` (Task 1).
- Produces: função `"sinalacs_audit_append_only"()`; triggers `"audit_logs_append_only"`, `"audit_exports_append_only"`, `"audit_chain_checkpoints_append_only"`; a linha marcadora `-- APPEND-ONLY DA TRILHA DE AUDITORIA (#82` no topo do bloco, que a Task 3 procura. Os testes leem `database/audit_append_only.sql` relativo à raiz do pacote (o `dart test` roda de lá).

- [ ] **Step 1: Escrever os testes de guarda (falham)** — em `audit_schema_test.dart`:

```dart
group('Dado o append-only da trilha (#82)', () {
  final bloco = File('database/audit_append_only.sql').readAsStringSync();
  final versoes = File('migrations/migration_registry.txt')
      .readAsLinesSync().where((l) => l.trim().isNotEmpty && !l.startsWith('#')).toList(); // cabeçalho começa com ###

  test('o definition.sql mais recente instala o append-only', () {
    expect(_definitionDoUltimoEsquema(), contains(bloco),
        reason: 'a última migração perdeu o bloco: rode '
            'scripts/dev/append_audit_append_only.sh (ver backend/CLAUDE.md)');
  });

  test('a migração de origem aplica o append-only num banco existente', () {
    final origem = versoes.firstWhere((v) => File('migrations/$v/migration.sql')
        .readAsStringSync().contains(bloco), orElse: () => '');
    expect(origem, isNotEmpty);
  });
});
```

E no grupo `withServerpod` do mesmo arquivo:

```dart
test('os três triggers existem e estão ativos no banco de teste', () async {
  final r = await session.db.unsafeQuery(
    "SELECT tgname FROM pg_trigger WHERE tgname LIKE '%_append_only' "
    "AND tgenabled = 'O' ORDER BY tgname");
  expect(r.map((row) => row.first), [
    'audit_chain_checkpoints_append_only',
    'audit_exports_append_only',
    'audit_logs_append_only',
  ]);
});
```

(O `_definitionDoUltimoEsquema()` já existe no arquivo.)

- [ ] **Step 2: Escrever os testes de comportamento (falham)** — `audit_append_only_test.dart`, um `withServerpod` com rollback padrão. Cada tentativa proibida roda **dentro** de `session.db.transaction` (savepoint), para não abortar a transação externa do harness. Matcher comum:

```dart
final recusado = throwsA(isA<DatabaseQueryException>()
    .having((e) => e.code, 'code', '42501')
    .having((e) => e.message, 'message', contains('append-only')));
```

Casos (gerar uma linha antes com `OrmAuditTrail`/insert direto conforme a tabela):
- `para cada tabela, UPDATE é recusado` — `UPDATE <t> SET … WHERE true`, para as três.
- `para cada tabela, DELETE é recusado`.
- `para cada tabela, TRUNCATE é recusado`.
- `UPDATE e DELETE sem linha alvo também são recusados` — `UPDATE audit_logs SET result = 'x' WHERE false` e `DELETE FROM audit_logs WHERE false` (Review Focus 4).
- `depois da recusa, a trilha continua gravando` — recusa um `UPDATE` e, na mesma sessão, `OrmAuditTrail.record…` grava a linha `n + 1` e `AuditChainVerifier` dá `verified` (Review Focus 2; usar a mesma montagem de `audit_chain_reader_test.dart`).
- `advanceTo e exportação seguem funcionando` — `OrmAuditCheckpointStore.advanceTo` duas vezes na mesma `sequence` (segunda cai no `ON CONFLICT DO NOTHING`) e uma exportação via o mesmo caminho de `admin_endpoint_audit_export_test.dart`; ambos sem exceção (Review Focus 3).
- `o superusuário ainda contorna (limite documentado)` — `adulterarComoSuperusuario(session, "UPDATE audit_logs SET result = 'x' WHERE sequence = @s", …)` não lança e a verificação dá `broken`.
- `depois do atalho, o trigger volta a valer` — logo após o caso anterior, um `UPDATE` direto na mesma sessão é `recusado` (Review Focus 5).
- `PUBLIC não tem UPDATE/DELETE/TRUNCATE` — `SELECT has_table_privilege('public', '<t>', 'UPDATE')` etc. via `information_schema.role_table_grants WHERE grantee = 'PUBLIC'` devolve vazio para as três tabelas e os três privilégios.

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test -j 1 test/integration/audit_append_only_test.dart test/integration/audit_schema_test.dart`
Expected: FAIL — `database/audit_append_only.sql` inexistente, triggers ausentes, os `UPDATE`/`DELETE` passam.

- [ ] **Step 4: Escrever `database/audit_append_only.sql`** (texto exato; é o que os testes comparam):

```sql
--
-- APPEND-ONLY DA TRILHA DE AUDITORIA (#82, RF17/STRIDE-R)
-- Fonte: database/audit_append_only.sql. O Serverpod reescreve o
-- definition.sql a cada create-migration: rode
-- scripts/dev/append_audit_append_only.sh depois de toda migração nova
-- (backend/CLAUDE.md). Limite: superusuário e dono da tabela ainda contornam
-- (session_replication_role = replica, ALTER TABLE ... DISABLE TRIGGER).
--
CREATE OR REPLACE FUNCTION "sinalacs_audit_append_only"() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'tabela de auditoria % é append-only: % recusado',
        TG_TABLE_NAME, TG_OP
        USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS "audit_logs_append_only" ON "audit_logs";
CREATE TRIGGER "audit_logs_append_only"
    BEFORE UPDATE OR DELETE OR TRUNCATE ON "audit_logs"
    FOR EACH STATEMENT EXECUTE FUNCTION "sinalacs_audit_append_only"();

DROP TRIGGER IF EXISTS "audit_exports_append_only" ON "audit_exports";
CREATE TRIGGER "audit_exports_append_only"
    BEFORE UPDATE OR DELETE OR TRUNCATE ON "audit_exports"
    FOR EACH STATEMENT EXECUTE FUNCTION "sinalacs_audit_append_only"();

DROP TRIGGER IF EXISTS "audit_chain_checkpoints_append_only" ON "audit_chain_checkpoints";
CREATE TRIGGER "audit_chain_checkpoints_append_only"
    BEFORE UPDATE OR DELETE OR TRUNCATE ON "audit_chain_checkpoints"
    FOR EACH STATEMENT EXECUTE FUNCTION "sinalacs_audit_append_only"();

REVOKE UPDATE, DELETE, TRUNCATE
    ON "audit_logs", "audit_exports", "audit_chain_checkpoints"
    FROM PUBLIC;
```

- [ ] **Step 5: Criar a migração vazia**

Run: `cd backend/sinalacs_server && serverpod create-migration --force`
Expected: novo diretório em `migrations/` e uma linha nova em `migration_registry.txt`; `migration.sql` só com `BEGIN;`, o bloco de versão e `COMMIT;`.

- [ ] **Step 6: Colar o bloco** do `database/audit_append_only.sql`, verbatim, imediatamente antes da linha `-- MIGRATION VERSION FOR sinalacs` no `migration.sql` **e** no `definition.sql` da nova versão. (Na Task 3 isso vira script; aqui pode ser à mão, os testes do Step 1 conferem.)

- [ ] **Step 7: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test -j 1 test/integration/audit_append_only_test.dart test/integration/audit_schema_test.dart`
Expected: PASS. Se o caso `os três triggers existem` falhar com o banco de teste antigo, recriar o banco de teste (o harness aplica o `migration.sql` novo) e rodar de novo.

- [ ] **Step 8: Suíte inteira do backend**

Run: `cd backend/sinalacs_server && dart analyze && dart test -j 1`
Expected: `No issues found!` e zero falhas — em especial os quatro arquivos da Task 1 continuam verdes **por causa** do atalho.

- [ ] **Step 9: Commit**

```bash
git add backend/sinalacs_server/database backend/sinalacs_server/migrations backend/sinalacs_server/test/integration
git commit -m "feat(auditoria): trigger append-only e REVOKE nas tabelas da trilha (#82)"
```

---

### Task 3: Script que recoloca o bloco + exceção documentada no `backend/CLAUDE.md`

**Files:**
- Create: `scripts/dev/append_audit_append_only.sh`
- Create: `scripts/dev/append_audit_append_only_test.sh` (hermético, fixtures em `mktemp -d`)
- Modify: `backend/CLAUDE.md` (regra "Never hand-edit … `migrations/`", linha 98; e o parágrafo de auditoria, linha 130)

**Interfaces:**
- Consumes: `backend/sinalacs_server/database/audit_append_only.sql` e a linha marcadora (Task 2).
- Produces: `scripts/dev/append_audit_append_only.sh [--migrations-dir DIR] [--bloco ARQ] [--tambem-migration-sql]`. Padrões: `backend/sinalacs_server/migrations` e `backend/sinalacs_server/database/audit_append_only.sql`. Lê a última versão de `migration_registry.txt`; se o `definition.sql` dela já contém a linha marcadora, imprime `já presente em <versão>` e sai 0; senão insere o bloco antes de `-- MIGRATION VERSION FOR sinalacs` e imprime `bloco inserido em <versão>/definition.sql`. Com `--tambem-migration-sql`, faz o mesmo no `migration.sql`. Sai 1 com mensagem se o marcador `-- MIGRATION VERSION FOR sinalacs` não existir (nunca acrescenta no fim, depois do `COMMIT;`).

- [ ] **Step 1: Escrever o teste hermético (falha)** — `append_audit_append_only_test.sh`, no estilo de `scripts/qa/admin_auditoria_e2e_test.sh` (função `conferir`, saída `OK`/`FALHOU`), com casos:
  - `insere antes do marcador de versão` — fixture com `definition.sql` mínimo (`BEGIN;`, uma tabela, `-- MIGRATION VERSION FOR sinalacs`, `COMMIT;`); depois do script, o bloco aparece uma vez e antes do marcador.
  - `é idempotente` — rodar duas vezes deixa uma ocorrência só e a segunda imprime `já presente`.
  - `não toca o migration.sql sem a flag` / `toca com --tambem-migration-sql`.
  - `recusa definition.sql sem o marcador` — exit 1 e arquivo inalterado (`cmp`).
  - `usa a última versão do registry` — duas versões na fixture, só a última muda.

- [ ] **Step 2: Rodar e ver falhar**

Run: `./scripts/dev/append_audit_append_only_test.sh`
Expected: FAIL (script inexistente).

- [ ] **Step 3: Implementar o script** (bash, `set -euo pipefail`; inserção com `awk` lendo o bloco de arquivo, sem `sed -i` com texto multilinha).

- [ ] **Step 4: Rodar o teste e o script real**

Run: `./scripts/dev/append_audit_append_only_test.sh && ./scripts/dev/append_audit_append_only.sh`
Expected: teste `OK`; o script real imprime `já presente em <versão da Task 2>`.

- [ ] **Step 5: Documentar a exceção no `backend/CLAUDE.md`**: na linha 98, depois de "Never hand-edit…", uma frase: a única exceção é o bloco de `database/audit_append_only.sql` (#82); depois de **todo** `serverpod create-migration`, rodar `./scripts/dev/append_audit_append_only.sh` (o `audit_schema_test.dart` falha se esquecer). Na linha 130, trocar "Cadeia detecta, não impede: sem trigger/`REVOKE` append-only…" pelo estado novo: trigger por comando nas três tabelas, `REVOKE` de `PUBLIC`, o superusuário (que é o usuário do backend na stack local) ainda contorna; testes que adulteram usam `test/integration/support/privileged_tamper.dart`.

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/append_audit_append_only.sh scripts/dev/append_audit_append_only_test.sh backend/CLAUDE.md
git commit -m "chore(auditoria): script que recoloca o append-only na última migração (#82)"
```

---

### Task 4: e2e da Auditoria no emulador + atualização de um `pg_data/` existente

Prova os dois caminhos de instalação: banco novo (`sinalacs_e2e` é recriado a cada rodada, logo vem do `definition.sql`) e banco existente (o `pg_data/` de dev aplica o `migration.sql`).

**Files:**
- Modify: `scripts/qa/admin_auditoria_e2e.sh` (linhas 139 e 206; nova checagem antes do `== cadeia de auditoria`)
- Modify: `scripts/qa/admin_auditoria_e2e_test.sh` (padrões `p_adulterar`/`p_restaurar`, linhas 63 e 73; nova `conferir`)

**Interfaces:**
- Consumes: os triggers (Task 2); `scripts/qa/e2e_stack.sh psql "<sql>"` (psql `-Atc` como `postgres` no `sinalacs-postgres-test`).

- [ ] **Step 1: Atualizar o teste estático (falha)** em `admin_auditoria_e2e_test.sh`:
  - `p_adulterar` passa a ser `begin; set local session_replication_role = replica; update audit_logs set result = 'x' where sequence = $n; commit;` (mesmo para `p_restaurar` com `'$original'`/`$alvo`).
  - Nova `conferir 'o banco de e2e recusa UPDATE comum na trilha (#82)'` que exige no script a linha `sql "update audit_logs set result = result where sequence = $alvo"` dentro de um `if … ; then` que aborta com `erro: o UPDATE comum deveria ser recusado pelo trigger append-only`.

Run: `./scripts/qa/admin_auditoria_e2e_test.sh`
Expected: FAIL nas três checagens novas/alteradas.

- [ ] **Step 2: Atualizar `admin_auditoria_e2e.sh`**: as duas adulterações (linhas 139 e 206) vão para a forma `begin; set local … replica; …; commit;`; antes de `echo "== cadeia de auditoria (verificador CLI)"`, a checagem negativa (o `sql` comum tem que falhar e a saída de erro tem que conter `append-only`). Comentário de cabeçalho (linha ~26) atualizado.

Run: `./scripts/qa/admin_auditoria_e2e_test.sh && bash -n scripts/qa/admin_auditoria_e2e.sh`
Expected: `OK` e sem erro de sintaxe.

- [ ] **Step 3: Rodar o e2e no emulador** (seguir a skill `validacao-e2e`; emulador disponível)

Run: `./scripts/qa/admin_auditoria_e2e.sh`
Expected: termina em `OK — trilha de auditoria do backoffice contra o banco de teste`, com a adulteração detectada na tela, `exit=1` adulterada e `exit=0` restaurada, e a recusa do `UPDATE` comum registrada. Salvar a saída em `docs/superpowers/plans/2026-10-25-issue-82-e2e.log` (mesmo padrão das #80/#81).

- [ ] **Step 4: Provar a atualização de um banco existente** (stack de dev com `pg_data/` anterior à migração):

Run: `docker compose up -d --build serverpod && docker compose exec postgres psql -U "${POSTGRES_USER:-sinalacs_user}" -d "${POSTGRES_DB:-sinalacs_db}" -Atc "select tgname from pg_trigger where tgname like '%_append_only' order by 1"` e em seguida `… -c "delete from audit_logs where false"`
Expected: as três linhas de trigger; o `DELETE` falha com `tabela de auditoria audit_logs é append-only: DELETE recusado`. Anotar no log do Step 3.

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/admin_auditoria_e2e.sh scripts/qa/admin_auditoria_e2e_test.sh docs/superpowers/plans/2026-10-25-issue-82-e2e.log
git commit -m "test(e2e): adulteração da auditoria como superusuário e recusa do UPDATE comum (#82)"
```

---

### Task 5: Documentação de estado, issue de continuação, grafo e PR

**Files:**
- Modify: `spec/PRD_system.md` (RF17, linha 150: "Limites: a cadeia detecta, não impede…"; STRIDE Repudiation, linha 576)
- Modify: `spec/lgpd_design.md` (LGPD-RT03, linhas 710-711: "O que ainda falta" e o critério `✗ Logs são imutáveis por construção do banco`)
- Modify: `PROGRESS.md` (linhas 47, 84, 235, 401, 1601 e uma seção nova `#82`)
- Modify: `CLAUDE.md` (raiz: o item "the audit trail's append-only enforcement in the database (the chain detects tampering, it does not prevent it; no trigger/`REVOKE`)" da lista "Still missing")
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas 47, 84 e item 8, linha 235)

- [ ] **Step 1: Abrir a issue de continuação** — **confirmar com o dono antes** (é publicação no GitHub). Título: `[P2] Separar papéis do Postgres para o REVOKE da auditoria valer (RF17)`. Corpo: o backend roda como `POSTGRES_USER` (superusuário, dono das tabelas), que contorna o trigger da #82 por `session_replication_role` ou `DISABLE TRIGGER` e ignora `REVOKE`; falta um papel de runtime sem superusuário e sem posse, com só `INSERT`/`SELECT` nas três tabelas, e migrações aplicadas pelo dono; incluir `consent_logs` na avaliação. Anotar o número (`#NN`) para os passos seguintes.

- [ ] **Step 2: Atualizar os documentos** com um texto de estado só, repetido em cada lugar no estilo de cada arquivo: **RF17/STRIDE-R/LGPD-RT03 — o banco recusa `UPDATE`/`DELETE`/`TRUNCATE` em `audit_logs`, `audit_exports` e `audit_chain_checkpoints` (trigger por comando, `SQLSTATE 42501`, migração `<versão>`), com `REVOKE` de `PUBLIC`; o superusuário/dono ainda contorna — separação de papéis na `#NN`; `audit_exports` segue fora da cadeia; download do CSV e revisão do DPO seguem abertos.** O status de RF17 e STRIDE-R continua **parcial** (não fechar). No `PROGRESS.md`, a seção `#82` lista: entregue, provas (testes por nome, e2e de 2026-10-25 com o log, atualização do `pg_data/`), limites (superusuário, `consent_logs` sem trigger, o passo manual depois de `create-migration` guardado por teste) e as pendências herdadas.

- [ ] **Step 3: Conferir que nada ficou dizendo o estado antigo**

Run: `grep -rn "sem trigger/\`REVOKE\`\|nenhum trigger/\`REVOKE\`\|no trigger/\`REVOKE\`\|append-only ainda é só convenção" spec PROGRESS.md CLAUDE.md backend/CLAUDE.md docs/auditoria-prd`
Expected: nenhuma linha (as entradas históricas datadas do `PROGRESS.md`, como a linha 351, podem ficar se descreverem o passado; reler cada uma).

- [ ] **Step 4: Atualizar o grafo e rodar a validação final**

Run: `graphify update . && cd backend/sinalacs_server && dart analyze && dart test -j 1 && cd ../.. && ./scripts/qa/ci_invariants.sh && ./scripts/qa/admin_auditoria_e2e_test.sh && ./scripts/dev/append_audit_append_only_test.sh`
Expected: tudo verde; a lista de jobs da CI não mudou (nenhum job novo).

- [ ] **Step 5: Commit e PR contra `develop`**

```bash
git add spec PROGRESS.md CLAUDE.md docs/auditoria-prd graphify-out
git commit -m "docs: estado do append-only da auditoria (#82)"
git push -u origin feat/issue-82-auditoria-append-only
gh pr create --base develop --title "feat(auditoria): append-only no banco (#82)" --body "<resumo, provas, limites, issue #NN>"
```

O PR **não** fecha a #82 sozinho (`Refs #82`): RF17 segue parcial por causa do superusuário, do download e do DPO; quem decide fechar é o dono.
