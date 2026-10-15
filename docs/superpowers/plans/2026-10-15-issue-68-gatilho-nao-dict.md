# Issue #68 — `push`/`pull_request` que não são dict: mensagem de tipo, sem traceback — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** `scripts/qa/ci_invariants.sh` passa a responder a um `push`/`pull_request` que não é dict nem nulo com uma única mensagem `<evento>: tem tipo inesperado (<tipo>): <valor>`, sem traceback e sem `paths`/`paths-ignore` acusados à toa, com controles positivo e negativo em `scripts/qa/ci_invariants_test.sh`.

**Arquitetura:** só scripts de CI e documentação. Duas mudanças no Python embutido em `ci_invariants.sh`: (1) `check_sem_filtro_de_paths` pula `cfg` que não seja dict (o tipo já é acusado em `check_gatilhos`); (2) `check_gatilhos` acusa o tipo de `push` não-dict em vez de chamar `.get()` nele — e, nesse caso, não emite também o FINDING-2 (uma mensagem por defeito, a mesma regra da #19). As fixtures ganham `PUSH_CFG`/`escreve_push`, espelhando o `PULL_REQUEST_CFG`/`escreve_pr` da #19.

**Stack:** bash, Python 3 + PyYAML, GitHub Actions, `gh`.

**Spec:** issue #68 (`gh issue view 68`). Origem: minors adiados da revisão final da PR #67 (issue #19); plano anterior em `docs/superpowers/plans/2026-10-15-issue-19-filtros-pull-request.md`.

## Verificação já feita (2026-10-15, antes do plano)

Reproduzido em `develop` (`5f4afe8`) com a `workflow_base` do `ci_invariants_test.sh`, trocando só o gatilho:

```
pull_request: true            → Traceback … check_sem_filtro_de_paths … TypeError: argument of type 'bool' is not a container or iterable
pull_request: 5               → Traceback … TypeError: argument of type 'int' …
pull_request: "paths-ignore"  → FALHA: pull_request: tem tipo inesperado (str): 'paths-ignore'
                                FALHA: pull_request.paths faria checks obrigatórios nunca reportarem       ← falso
                                FALHA: pull_request.paths-ignore faria checks obrigatórios nunca reportarem ← falso
push: true                    → Traceback … check_gatilhos … AttributeError: 'bool' object has no attribute 'get'
push: "paths"                 → Traceback … AttributeError: 'str' object has no attribute 'get'
push: [main, develop]         → Traceback … AttributeError: 'list' object has no attribute 'get'
```

O corpo da issue só descreve `pull_request`, mas o título cita `push` — e `push` não-dict quebra **antes**, em `check_gatilhos` (linha `push = (gatilhos.get('push') or {}).get('branches')`), então corrigir só `check_sem_filtro_de_paths` não basta para o `push`. Este plano cobre os dois.

O código e os testes deste plano foram prototipados numa cópia dos dois scripts: com os testes novos e sem a correção, `ci_invariants_test.sh` sai com `FALHOU — 10 asserção(ões) não conferem.`; com a correção, sai `OK`; e o `ci.yml` real continua `ok: 9 grupos de invariantes do CI`.

## Global Constraints

- Branch: `fix/issue-68-gatilho-nao-dict`, a partir de `develop`; PR contra `develop`.
- Mensagens, comentários e docs em português, no tom dos já existentes em `ci_invariants.sh`.
- Formato da mensagem de tipo idêntico ao que já existe para `on:` e `pull_request:`: `f'<evento>: tem tipo inesperado ({type(v).__name__}): {v!r}'`.
- Nenhuma dependência nova: os dois scripts continuam precisando só de `python3` + PyYAML, sem rede nem stack.
- O `.github/workflows/ci.yml` real tem de continuar passando: `./scripts/qa/ci_invariants.sh` imprime `ok: 9 grupos de invariantes do CI` (nenhum grupo novo — as mudanças entram em `check_gatilhos` e `check_sem_filtro_de_paths`, que já existem).
- Nenhum job novo, nenhum passo novo no workflow: `ci_invariants_test.sh` já roda no `workflow-lint` (`JOBS_DOCUMENTADOS` e a proteção de branch ficam intactos).
- A fixture base (`workflow_base` sem `PUSH_CFG` nem `PULL_REQUEST_CFG`) tem de sair **byte a byte igual** à de hoje — o caso `on_lista` corta as 5 primeiras linhas dela com `tail -n +6`.
- Commits e descrição da PR **sem** atribuição de IA (`Co-Authored-By`, "Generated with Claude Code") — regra do `CLAUDE.md` do projeto, que prevalece.

## Sobre o emulador

A #68 não toca app, backend nem o `android-e2e`. O que prova a correção são as fixtures do `ci_invariants_test.sh`, o `ci.yml` real ainda verde e o `workflow-lint` verde na PR. Não rode o emulador para esta issue.

## Fora de escopo (anotado, não corrigido)

- `push:` nulo (sem `branches:`) dispara em **todas** as branches, inclusive `develop`, mas o FINDING-2 acusa "push não dispara o CI em develop (branches: [])". É um falso positivo pré-existente e diferente desta issue (é dict/nulo, não tipo errado); o teste novo `push: nulo` só fixa que ele não vira "tipo inesperado" nem traceback. Se valer a pena, abrir issue própria.
- `branches:` como string (`branches: develop`) cai em busca de substring em `'develop' not in push`. Mesmo comentário.

## Review Focus

1. `pull_request: true` (o cenário principal da issue): hoje o traceback aborta o script antes de imprimir **todas** as falhas acumuladas, inclusive a mensagem de tipo correta → tem de sair só com `pull_request: tem tipo inesperado (bool)` e sem `Traceback` (Tarefa 1, casos `pr_true`/`pr_int`).
2. `pull_request: "paths-ignore"`: string é iterável, `in` vira substring e acusa dois filtros inexistentes → só a mensagem de tipo (Tarefa 1, caso `pr_str`).
3. `push` não-dict (`true`, `"paths"`, `[main, develop]`): quebra em `check_gatilhos`, antes da checagem de paths → mensagem de tipo, sem traceback, sem FINDING-2 duplicado e sem `push.paths` falso (Tarefa 1, casos `push_true`/`push_str`/`push_lista`).
4. Desvio largo demais: pular não-dict não pode desligar a checagem de paths num dict real → `push: { branches: [main, develop], paths: [docs/**] }` continua acusado (Tarefa 1, caso `push_paths`; o caso `pr_paths` da #19 cobre o `pull_request`).
5. `push:` nulo e a fixture base: nulo é forma válida, não pode virar "tipo inesperado"; e parametrizar o `push` da fixture não pode mudar a base, senão o controle de base e o `on_lista` mentem (Tarefa 1, caso `push_nulo`, controle de base e Passo 3).

---

### Task 1: Tipo de `push`/`pull_request` em vez de traceback, com fixtures

**Files:**
- Modify: `scripts/qa/ci_invariants.sh` (`check_gatilhos`, hoje linhas 109–112; `check_sem_filtro_de_paths`, hoje linhas 139–146)
- Modify: `scripts/qa/ci_invariants_test.sh` (cabeçalho, `workflow_base`, novo `escreve_push`, nova seção de casos, mensagem final)
- Test: `scripts/qa/ci_invariants_test.sh`

**Interfaces:**
- Consumes: `gatilhos` (dict normalizado por `_normaliza_gatilhos`) e `falhas` (lista global) em `ci_invariants.sh`; `workflow_base`, `escreve_pr`, `rodar`, `espera_falha`, `espera_ok`, `tmp_dir` em `ci_invariants_test.sh`.
- Produces: mensagem `push: tem tipo inesperado (<tipo>): <valor>`; variável de ambiente `PUSH_CFG` lida por `workflow_base` (vazia = bloco `push:` + `branches: [main, develop]` de sempre; qualquer outro valor = `push: <valor>` numa linha); função `escreve_push <nome> <cfg-yaml-flow>` que devolve o caminho da fixture.

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull --ff-only
git switch -c fix/issue-68-gatilho-nao-dict
```

- [ ] **Step 2: Guardar a fixture base de hoje (para provar que não muda)**

```bash
S="${TMPDIR:-/tmp}/issue68"; mkdir -p "$S"
{ grep -m1 '^GRUPO_NOVO=' scripts/qa/ci_invariants_test.sh
  sed -n '/^workflow_base() {/,/^}/p' scripts/qa/ci_invariants_test.sh; } > "$S/antes.sh"
( source "$S/antes.sh"; workflow_base '' ) > "$S/base_antes.yml"
```

(Caminho fixo de propósito: cada comando pode rodar num shell novo, e os Steps 3 e 7 redeclaram o mesmo `S`.)

Expected: `"$S/base_antes.yml"` começa com `on:` / `  push:` / `    branches: [main, develop]` / `  pull_request: {}`.

- [ ] **Step 3: Parametrizar o `push` da fixture base**

Em `scripts/qa/ci_invariants_test.sh`, dentro de `workflow_base`, logo depois da linha `  [[ -n "$pr_cfg" ]] || pr_cfg='{}'`, acrescente:

```bash
  # PUSH_CFG vazio mantém o bloco de sempre (branches: [main, develop]);
  # qualquer outro valor vira `push: <valor>` numa linha só (issue #68).
  local push_bloco=$'push:\n    branches: [main, develop]'
  [[ -z "${PUSH_CFG:-}" ]] || push_bloco="push: ${PUSH_CFG}"
```

E no heredoc, troque:

```yaml
on:
  push:
    branches: [main, develop]
  pull_request: ${pr_cfg}
```

por:

```yaml
on:
  ${push_bloco}
  pull_request: ${pr_cfg}
```

(A segunda linha do bloco padrão já carrega os 4 espaços de indentação dentro de `push_bloco`; a primeira recebe os 2 do heredoc.)

Logo depois da função `escreve_pr`, acrescente:

```bash
# $2 é o valor de `push:` em YAML de uma linha só, como em escreve_pr.
escreve_push() {
  local nome="$1"
  local cfg="$2"
  local caminho="$tmp_dir/$nome.yml"
  PUSH_CFG="$cfg" workflow_base '' > "$caminho"
  printf '%s' "$caminho"
}
```

Prove que a base não mudou:

```bash
S="${TMPDIR:-/tmp}/issue68"
{ grep -m1 '^GRUPO_NOVO=' scripts/qa/ci_invariants_test.sh
  sed -n '/^workflow_base() {/,/^}/p' scripts/qa/ci_invariants_test.sh; } > "$S/depois.sh"
( source "$S/depois.sh"; workflow_base '' ) | diff "$S/base_antes.yml" - && echo IGUAL
```

Expected: `IGUAL`.

- [ ] **Step 4: Escrever os casos (positivos e negativos)**

No cabeçalho de `scripts/qa/ci_invariants_test.sh`, depois do parágrafo da issue #19 (que termina em `types fazem PRs fora do filtro nunca reportarem os checks obrigatórios.`), acrescente:

```bash
# E a de push/pull_request que não são dict (issue #68): mensagem de tipo, sem
# traceback que engula as outras falhas e sem paths acusado por substring.
```

Antes do bloco final (`echo` seguido de `if [[ "$falhas" -eq 0 ]]; then`), acrescente a seção:

```bash
echo '== push/pull_request que não são dict: mensagem de tipo, sem traceback nem paths falso (issue #68) =='
pr_true="$(escreve_pr pr_true 'true')"
espera_falha 'pull_request: true acusa o tipo' "$pr_true" 'pull_request: tem tipo inesperado (bool)'
espera_ok 'pull_request: true sem traceback' "$pr_true" 'Traceback'
pr_int="$(escreve_pr pr_int '5')"
espera_falha 'pull_request: 5 acusa o tipo' "$pr_int" 'pull_request: tem tipo inesperado (int)'
espera_ok 'pull_request: 5 sem traceback' "$pr_int" 'Traceback'
# Uma string é iterável: `'paths' in 'paths-ignore'` é True e acusava paths
# que não existe. O tipo já é a mensagem certa.
pr_str="$(escreve_pr pr_str '"paths-ignore"')"
espera_falha 'pull_request: "paths-ignore" acusa o tipo' "$pr_str" 'pull_request: tem tipo inesperado (str)'
espera_ok 'pull_request: "paths-ignore" não acusa paths' "$pr_str" 'pull_request.paths'

push_true="$(escreve_push push_true 'true')"
espera_falha 'push: true acusa o tipo' "$push_true" 'push: tem tipo inesperado (bool)'
espera_ok 'push: true sem traceback' "$push_true" 'Traceback'
push_str="$(escreve_push push_str '"paths"')"
espera_falha 'push: "paths" acusa o tipo' "$push_str" 'push: tem tipo inesperado (str)'
espera_ok 'push: "paths" não acusa paths' "$push_str" 'push.paths'
# Lista em push é inválida no Actions; uma mensagem por defeito — o tipo, não
# também o FINDING-2.
push_lista="$(escreve_push push_lista '[main, develop]')"
espera_falha 'push: [main, develop] acusa o tipo' "$push_lista" 'push: tem tipo inesperado (list)'
espera_ok 'push: [main, develop] sem traceback' "$push_lista" 'Traceback'
espera_ok 'push: [main, develop] sem FINDING-2 duplicado' "$push_lista" 'push não dispara o CI em develop'

# Controles: o dict com paths continua acusado, e push nulo não é tipo errado.
espera_falha 'push dict com paths continua acusado' \
  "$(escreve_push push_paths '{ branches: [main, develop], paths: [docs/**] }')" \
  'push.paths faria checks obrigatórios nunca reportarem'
push_nulo="$(escreve_push push_nulo 'null')"
espera_ok 'push: nulo não é tipo inesperado' "$push_nulo" 'tem tipo inesperado'
espera_ok 'push: nulo sem traceback' "$push_nulo" 'Traceback'
```

E troque a mensagem final de sucesso:

```bash
  echo 'OK — as checagens de "verde sem rodar" (issue #20), do grupo de concorrência (issues #23, #63 e #24) e dos filtros de pull_request (issue #19) conferem.'
```

por:

```bash
  echo 'OK — as checagens de "verde sem rodar" (issue #20), do grupo de concorrência (issues #23, #63 e #24), dos filtros de pull_request (issue #19) e dos gatilhos que não são dict (issue #68) conferem.'
```

- [ ] **Step 5: Rodar e ver falhar**

Run: `./scripts/qa/ci_invariants_test.sh 2>&1 | grep -E 'FALHA|FALHOU|OK —'`
Expected: exatamente estas 10 falhas e a linha `FALHOU — 10 asserção(ões) não conferem.`:

```
FALHA — pull_request: true acusa o tipo
FALHA — pull_request: true sem traceback
FALHA — pull_request: 5 acusa o tipo
FALHA — pull_request: 5 sem traceback
FALHA — pull_request: "paths-ignore" não acusa paths
FALHA — push: true acusa o tipo
FALHA — push: true sem traceback
FALHA — push: "paths" acusa o tipo
FALHA — push: [main, develop] acusa o tipo
FALHA — push: [main, develop] sem traceback
```

O controle de base, os casos das issues #19/#20/#23/#24/#63 e os controles `push dict com paths` / `push: nulo` têm de estar em `ok`. Se o controle de base falhar, o Step 3 mudou a fixture — volte e compare com `base_antes.yml`.

- [ ] **Step 6: Implementar em `ci_invariants.sh`**

Em `check_gatilhos`, troque:

```python
def check_gatilhos():
    push = (gatilhos.get('push') or {}).get('branches') or []
    if 'develop' not in push:
        falhas.append(f'FINDING-2: push não dispara o CI em develop (branches: {push})')
```

por:

```python
def check_gatilhos():
    # Só dict (ou nulo) carrega `branches:`; `push: true` ou `push: [main]`
    # quebravam com AttributeError no `.get()` em vez de dizer o que está
    # errado. O tipo é a mensagem — o FINDING-2 seria o mesmo defeito
    # contado duas vezes (issue #68).
    cfg_push = gatilhos.get('push')
    if cfg_push is not None and not isinstance(cfg_push, dict):
        falhas.append(f'push: tem tipo inesperado ({type(cfg_push).__name__}): {cfg_push!r}')
    else:
        push = (cfg_push or {}).get('branches') or []
        if 'develop' not in push:
            falhas.append(f'FINDING-2: push não dispara o CI em develop (branches: {push})')
```

(O resto de `check_gatilhos` — `workflow_dispatch` e `pull_request` — fica como está.)

Em `check_sem_filtro_de_paths`, troque:

```python
        cfg = gatilhos.get(evento) or {}
        for chave in ('paths', 'paths-ignore'):
```

por:

```python
        cfg = gatilhos.get(evento)
        # Fora de dict não há filtro a ler, e check_gatilhos já acusa o tipo.
        # Sem este desvio, `in` quebrava com TypeError num bool/int (e o
        # traceback engolia as falhas já acumuladas) ou virava busca de
        # substring numa string: `pull_request: "paths-ignore"` acusava
        # paths e paths-ignore que não existem (issue #68).
        if not isinstance(cfg, dict):
            continue
        for chave in ('paths', 'paths-ignore'):
```

(Nulo também cai no `continue`, o que é o mesmo resultado de antes: `{}` não tinha `paths`.)

- [ ] **Step 7: Rodar e ver passar — fixtures, workflow real e a reprodução**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: exit 0, última linha `OK — … e dos gatilhos que não são dict (issue #68) conferem.`

Run: `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_fcm_test.sh`
Expected: `ok: 9 grupos de invariantes do CI` e o teste do FCM verde (as fixtures dele derivam do `ci.yml` real, cujo `push` é dict).

Repita a reprodução da seção "Verificação já feita" contra o script corrigido:

```bash
S="${TMPDIR:-/tmp}/issue68"
for pr in 'true' '5' '"paths-ignore"'; do
  echo "=== pull_request: $pr"
  ( source "$S/depois.sh"; PULL_REQUEST_CFG="$pr" workflow_base '' ) > "$S/f.yml"
  CI_INVARIANTS_WORKFLOW="$S/f.yml" ./scripts/qa/ci_invariants.sh; echo "exit=$?"
done
for push in 'true' '"paths"' '[main, develop]'; do
  echo "=== push: $push"
  ( source "$S/depois.sh"; PUSH_CFG="$push" workflow_base '' ) > "$S/f.yml"
  CI_INVARIANTS_WORKFLOW="$S/f.yml" ./scripts/qa/ci_invariants.sh; echo "exit=$?"
done
```

Expected: cada caso imprime **uma** linha `FALHA: <evento>: tem tipo inesperado (<tipo>): <valor>` e `exit=1`; nenhum `Traceback`, nenhum `paths`, nenhum `FINDING-2`.

Depois: `rm -rf "${TMPDIR:-/tmp}/issue68"`.

- [ ] **Step 8: Commit**

```bash
git add scripts/qa/ci_invariants.sh scripts/qa/ci_invariants_test.sh
git commit -m "fix(ci): push/pull_request fora de dict viram mensagem de tipo, sem traceback (#68)"
```

---

### Task 2: Documentação e PR

**Files:**
- Modify: `CLAUDE.md` (bullet de proteção de `main`/`develop`, lista de issues corrigidas da guarda)
- Modify: `AGENTS.md` (bullet equivalente, em português)

**Interfaces:**
- Consumes: a mensagem e o comportamento entregues na Task 1.
- Produces: nada que outro código leia.

- [ ] **Step 1: `CLAUDE.md`**

No bullet que começa com `` `main` and `develop` are protected``, troque:

```
#22 fixed — `on:` as a string/list is normalized instead of crashing, and an unrecognized flag exits 2 with a usage message instead of silently exiting 0).
```

por:

```
#22 fixed — `on:` as a string/list is normalized instead of crashing, and an unrecognized flag exits 2 with a usage message instead of silently exiting 0; #68 fixed — a `push`/`pull_request` that is neither a dict nor null yields one "tem tipo inesperado" message instead of a traceback or a false `paths` finding).
```

- [ ] **Step 2: `AGENTS.md`**

No bullet que começa com `- migrar para o Ubuntu 26.04`, troque:

```
#22 corrigida — `on:` como string/lista é normalizado em vez de quebrar, e uma flag não reconhecida sai com 2 e mensagem de uso em vez de sair calada com 0).
```

por:

```
#22 corrigida — `on:` como string/lista é normalizado em vez de quebrar, e uma flag não reconhecida sai com 2 e mensagem de uso em vez de sair calada com 0; #68 corrigida — `push`/`pull_request` que não é dict nem nulo gera uma só mensagem "tem tipo inesperado" em vez de traceback ou de `paths` acusado à toa).
```

- [ ] **Step 3: Conferir que nada quebrou**

Run: `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh && ./scripts/qa/ci_invariants_fcm_test.sh`
Expected: tudo verde.

Run: `grep -c '#68' CLAUDE.md AGENTS.md`
Expected: `CLAUDE.md:1` e `AGENTS.md:1`.

- [ ] **Step 4: Atualizar o grafo e commitar**

```bash
graphify update .
git add CLAUDE.md AGENTS.md
git commit -m "docs(ci): registra a guarda de gatilhos que não são dict (#68)"
```

(Se `graphify update .` alterar arquivos versionados em `graphify-out/`, inclua-os neste commit; se não houver mudança, siga.)

- [ ] **Step 5: PR (confirmar com o usuário antes do push)**

Push e PR são ações visíveis fora da máquina: pergunte antes. Com o ok:

```bash
git push -u origin fix/issue-68-gatilho-nao-dict
gh pr create --base develop --title "fix(ci): push/pull_request fora de dict viram mensagem de tipo (#68)" --body "$(cat <<'EOF'
Closes #68.

- `check_sem_filtro_de_paths` pula `push`/`pull_request` que não são dict: sem `TypeError` em bool/int e sem `paths`/`paths-ignore` falsos por busca de substring numa string.
- `check_gatilhos` acusa `push: tem tipo inesperado (...)` em vez de quebrar com `AttributeError` no `.get()` (o corpo da issue só citava `pull_request`, mas `push` não-dict quebrava antes, aqui); nesse caso não repete o defeito como FINDING-2.
- `ci_invariants_test.sh`: `PUSH_CFG`/`escreve_push` e 15 asserções novas (10 falhavam antes da correção), incluindo os controles `push` dict com `paths` (continua acusado) e `push:` nulo (não é tipo errado).

Fora de escopo, anotado no plano: o FINDING-2 acusa `push:` nulo, que na verdade dispara em todas as branches.

Plano: `docs/superpowers/plans/2026-10-15-issue-68-gatilho-nao-dict.md`.
EOF
)"
```

- [ ] **Step 6: Acompanhar a PR**

Run: `gh pr checks --watch`
Expected: os 8 checks obrigatórios verdes (o `workflow-lint` roda `ci_invariants.sh` e `ci_invariants_test.sh`). O `android-e2e` é informativo.
