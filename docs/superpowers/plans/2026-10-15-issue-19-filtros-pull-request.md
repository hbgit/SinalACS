# Issue #19 — `check_gatilhos` vigia os filtros de `pull_request` — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** `scripts/qa/ci_invariants.sh` passa a falhar quando o gatilho `pull_request` do `.github/workflows/ci.yml` ganha qualquer filtro (`branches`, `branches-ignore`, `types` ou outra chave), com controles positivo e negativo em `scripts/qa/ci_invariants_test.sh`.

**Arquitetura:** só scripts de CI e documentação. A regra é a "mais simples" da issue: `pull_request` sem filtro nenhum (`pull_request:` nulo ou `{}`), como já é hoje. `check_gatilhos` (Python embutido em `ci_invariants.sh`) acusa cada chave presente em `pull_request`, exceto `paths`/`paths-ignore`, que `check_sem_filtro_de_paths` já acusa (uma mensagem por defeito). Valor que não é dict nem nulo (ex.: `pull_request: [main]`) falha com mensagem de tipo, nunca com traceback.

**Stack:** bash, Python 3 + PyYAML, GitHub Actions, `gh`.

**Spec:** issue #19 (`gh issue view 19`). Origem: minor adiado de `docs/superpowers/plans/2026-09-28-ci-correcoes-avaliacao.md` (PRs #16 e #18); contexto em `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (FINDING-2).

## Verificação já feita (2026-10-15, antes do plano)

A lacuna existe em `develop` (`30c4bc9`). Trocando a linha `  pull_request:` de uma cópia do `ci.yml` real e rodando a guarda contra ela:

```
pull_request: { branches: [main] }            → ok: 9 grupos de invariantes do CI, exit=0
pull_request: { branches-ignore: [develop] }  → ok: 9 grupos de invariantes do CI, exit=0
pull_request: { types: [opened] }             → ok: 9 grupos de invariantes do CI, exit=0
```

Nos três casos, PRs contra `develop` (ou novos pushes numa PR, no caso de `types`) deixariam de rodar o CI; a proteção de `develop` exige 8 checks e a PR ficaria em "Expected — Waiting for status" para sempre, com o `workflow-lint` verde. A Tarefa 1 repete esta prova como passo final.

## Global Constraints

- Branch: `fix/issue-19-gatilho-pull-request`, a partir de `develop`; PR contra `develop`.
- Mensagens, comentários e docs em português, no tom dos já existentes em `ci_invariants.sh`.
- Nenhuma dependência nova: `ci_invariants.sh` e `ci_invariants_test.sh` continuam precisando só de `python3` + PyYAML, sem rede nem stack.
- O `.github/workflows/ci.yml` real tem de continuar passando: `./scripts/qa/ci_invariants.sh` imprime `ok: 9 grupos de invariantes do CI` (o número de grupos não muda — a checagem entra em `check_gatilhos`, que já existe).
- Nenhum job novo, nenhum passo novo: `ci_invariants_test.sh` já roda no `workflow-lint` (`JOBS_DOCUMENTADOS`, `CLAUDE.md`, `AGENTS.md` e a proteção de branch ficam intactos).
- Commits e descrição da PR **sem** atribuição de IA (`Co-Authored-By`, "Generated with Claude Code") — regra do `CLAUDE.md` do projeto.

## Sobre o emulador

A #19 não toca app, backend nem o `android-e2e`. O que prova a correção são as fixtures do `ci_invariants_test.sh`, a prova contra a cópia do `ci.yml` real (Tarefa 1, Passo 6) e o `workflow-lint` verde na PR. Não rode o emulador para esta issue.

## Review Focus

1. `pull_request: { branches: [main] }` (o cenário da issue): PRs contra `develop` nunca reportam → a guarda tem de falhar citando `pull_request.branches` (Tarefa 1, positivo `branches_so_main`).
2. Filtro que hoje é inofensivo — `branches: [main, develop]` ou `types: [opened, synchronize, reopened]` (o padrão escrito à mão): recusado de propósito, porque a regra é "sem filtro nenhum"; a mensagem tem de dizer o que fazer (Tarefa 1, casos "recusa por forma").
3. `on:` em forma de lista (`on: [push, pull_request, workflow_dispatch]`) e `pull_request:` nulo: o `_normaliza_gatilhos` vira `{'pull_request': None}` — não pode acusar filtro nem quebrar com traceback (Tarefa 1, negativos `on_lista` e `pr_nulo`).
4. `pull_request: { paths: [...] }`: já acusado por `check_sem_filtro_de_paths`; a checagem nova não pode duplicar a falha (Tarefa 1, caso `pr_paths`).
5. `pull_request: [main]` (lista no lugar do dict, inválido no Actions): falha com mensagem de tipo, sem `AttributeError` (Tarefa 1, positivo `pr_lista`).

---

### Task 1: Guarda dos filtros de `pull_request` com fixtures

**Files:**
- Modify: `scripts/qa/ci_invariants_test.sh` (cabeçalho, `workflow_base`, novo `escreve_pr`, nova seção de casos, mensagem final)
- Modify: `scripts/qa/ci_invariants.sh` (`check_gatilhos`, hoje nas linhas ~104–111)
- Test: `scripts/qa/ci_invariants_test.sh`

**Interfaces:**
- Consumes: `gatilhos` (dict normalizado por `_normaliza_gatilhos`), `falhas` (lista global) em `ci_invariants.sh`; `workflow_base`, `rodar`, `espera_falha`, `espera_ok`, `tmp_dir` em `ci_invariants_test.sh`.
- Produces: mensagem de falha `pull_request.<chave> restringe quais PRs disparam o CI — ...` e `pull_request: tem tipo inesperado (<tipo>): <valor>`; variável de ambiente `PULL_REQUEST_CFG` lida por `workflow_base` (vazia = `{}`); função `escreve_pr <nome> <cfg-yaml-flow>` que devolve o caminho da fixture.

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull --ff-only && git switch -c fix/issue-19-gatilho-pull-request
```

- [ ] **Step 2: Parametrizar o `pull_request` da fixture base**

Em `scripts/qa/ci_invariants_test.sh`, dentro de `workflow_base`, logo depois de `local grupo="${GRUPO_CONCORRENCIA:-$GRUPO_NOVO}"`, acrescentar:

```bash
  # PULL_REQUEST_CFG vazio cai no `{}` de sempre — para testar `null` de
  # verdade, passe a string 'null' (issue #19).
  local pr_cfg="${PULL_REQUEST_CFG:-}"
  [[ -n "$pr_cfg" ]] || pr_cfg='{}'
```

E no heredoc trocar a linha

```yaml
  pull_request: {}
```

por

```yaml
  pull_request: ${pr_cfg}
```

Depois de `escreve_grupo`, acrescentar:

```bash
# $2 é o valor de `pull_request:` em YAML de uma linha só (flow style), ex.:
# '{ branches: [main] }'.
escreve_pr() {
  local nome="$1"
  local cfg="$2"
  local caminho="$tmp_dir/$nome.yml"
  PULL_REQUEST_CFG="$cfg" workflow_base '' > "$caminho"
  printf '%s' "$caminho"
}
```

- [ ] **Step 3: Escrever os casos (positivos e negativos)**

Inserir antes do `echo` vazio que precede o resumo final:

```bash
echo '== pull_request sem filtro nenhum: um filtro faz PRs nunca reportarem os checks (issue #19) =='
MSG_PR='restringe quais PRs disparam o CI'

# O cenário da issue: PRs contra develop param de disparar o CI.
espera_falha 'positivo (branches só com main)' \
  "$(escreve_pr branches_so_main '{ branches: [main] }')" \
  "pull_request.branches $MSG_PR"
espera_falha 'positivo (branches-ignore com develop)' \
  "$(escreve_pr branches_ignore '{ branches-ignore: [develop] }')" \
  "pull_request.branches-ignore $MSG_PR"
# Sem synchronize, um push novo na PR não roda o CI e a ponta fica sem check.
espera_falha 'positivo (types só com opened)' \
  "$(escreve_pr types_so_opened '{ types: [opened] }')" \
  "pull_request.types $MSG_PR"
espera_falha 'positivo (pull_request como lista, não dict)' \
  "$(escreve_pr pr_lista '[main]')" \
  'pull_request: tem tipo inesperado (list)'

# Filtros que hoje não excluem nada: recusados de propósito. A regra é "sem
# filtro nenhum" — mais simples de ler e impossível de envelhecer quando uma
# branch protegida nova aparecer.
espera_falha 'recusa por forma (branches com main e develop)' \
  "$(escreve_pr branches_main_develop '{ branches: [main, develop] }')" \
  "pull_request.branches $MSG_PR"
espera_falha 'recusa por forma (types com o padrão escrito à mão)' \
  "$(escreve_pr types_padrao '{ types: [opened, synchronize, reopened] }')" \
  "pull_request.types $MSG_PR"

# paths é de check_sem_filtro_de_paths: uma mensagem por defeito, não duas.
espera_falha 'paths continua acusado pela checagem de paths' \
  "$(escreve_pr pr_paths '{ paths: [docs/**] }')" \
  'pull_request.paths faria checks obrigatórios nunca reportarem'
espera_ok 'paths não é acusado de novo pela checagem de filtros' \
  "$(escreve_pr pr_paths_2 '{ paths: [docs/**] }')" \
  "$MSG_PR"

# Negativos: as formas sem filtro.
espera_ok 'negativo (pull_request: {})' \
  "$(escreve_pr pr_vazio '{}')" 'pull_request'
espera_ok 'negativo (pull_request: nulo)' \
  "$(escreve_pr pr_nulo 'null')" 'pull_request'
# `on:` em lista não carrega filtro; FINDING-2 (push sem develop) acende aqui,
# mas nada sobre pull_request nem traceback.
on_lista="$tmp_dir/on_lista.yml"
{ echo 'on: [push, pull_request, workflow_dispatch]'; workflow_base '' | tail -n +6; } > "$on_lista"
espera_ok 'negativo (on: em lista)' "$on_lista" 'pull_request'
espera_ok 'negativo (on: em lista, sem traceback)' "$on_lista" 'Traceback'
```

(As 5 primeiras linhas do `workflow_base` são exatamente `on:`, `push:`, `branches:`, `pull_request:` e `workflow_dispatch:`; o `tail -n +6` começa em `concurrency:`.)

Atualizar a mensagem final de sucesso para:

```bash
  echo 'OK — as checagens de "verde sem rodar" (issue #20), do grupo de concorrência (issues #23, #63 e #24) e dos filtros de pull_request (issue #19) conferem.'
```

E, no cabeçalho, depois de "…são casos aqui)", acrescentar a frase: `E a dos filtros de pull_request (issue #19): branches, branches-ignore ou types fazem PRs fora do filtro nunca reportarem os checks obrigatórios.` (ajustando o ponto final da frase anterior).

- [ ] **Step 4: Rodar e ver falhar**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: exit 1; `FALHA — positivo (branches só com main)`, `branches-ignore`, `types só com opened`, `pull_request como lista` e os dois "recusa por forma" (6 falhas); o controle de base e todos os negativos (inclusive `on: em lista`) em `ok`. Se o controle de base falhar, o Step 2 mudou o YAML da base — corrija antes de seguir.

- [ ] **Step 5: Implementar em `check_gatilhos`**

Em `scripts/qa/ci_invariants.sh`, substituir

```python
    if 'pull_request' not in gatilhos:
        falhas.append('pull_request deixou de disparar o CI')
```

por

```python
    if 'pull_request' not in gatilhos:
        falhas.append('pull_request deixou de disparar o CI')
        return
    # Qualquer filtro em pull_request decide QUAIS PRs rodam o CI: com
    # `branches: [main]`, uma PR contra develop não dispara nada, os 8 checks
    # obrigatórios nunca reportam e ela fica em "Waiting for status" para
    # sempre — com este workflow-lint verde (issue #19). A regra é sem filtro
    # nenhum, até os que hoje não excluem nada: não envelhece quando surgir
    # uma branch protegida nova. paths/paths-ignore ficam com
    # check_sem_filtro_de_paths, para não acusar o mesmo defeito duas vezes.
    cfg_pr = gatilhos['pull_request']
    if cfg_pr is None:
        return
    if not isinstance(cfg_pr, dict):
        falhas.append(f'pull_request: tem tipo inesperado ({type(cfg_pr).__name__}): {cfg_pr!r}')
        return
    for chave in sorted(set(cfg_pr) - {'paths', 'paths-ignore'}):
        falhas.append(
            f'pull_request.{chave} restringe quais PRs disparam o CI — uma PR fora '
            'do filtro nunca reporta os checks obrigatórios e espera para sempre; '
            'deixe pull_request sem filtro (issue #19)'
        )
```

(O `return` logo após "deixou de disparar" é seguro: é a última instrução da função hoje.)

- [ ] **Step 6: Rodar e ver passar — fixtures, workflow real e a prova da lacuna**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: exit 0, última linha `OK — … e dos filtros de pull_request (issue #19) conferem.`

Run: `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_fcm_test.sh`
Expected: `ok: 9 grupos de invariantes do CI` e o teste do FCM verde (as fixtures dele derivam do `ci.yml` real, que não tem filtro em `pull_request`; se acusar, investigue a fixture antes de mexer na guarda).

Repetir a prova contra a cópia do workflow real (agora tem de falhar):

```bash
S="$(mktemp -d)"
for cfg in '{ branches: [main] }' '{ branches-ignore: [develop] }' '{ types: [opened] }'; do
  sed "s/^  pull_request:\$/  pull_request: $cfg/" .github/workflows/ci.yml > "$S/wf.yml"
  CI_WORKFLOW_PATH="$S/wf.yml" ./scripts/qa/ci_invariants.sh; echo "exit=$?"
done
rm -rf "$S"
```

Expected: três `FALHA: pull_request.<chave> restringe quais PRs disparam o CI …` e `exit=1` em cada.

- [ ] **Step 7: Commit**

```bash
git add scripts/qa/ci_invariants.sh scripts/qa/ci_invariants_test.sh
git commit -m "fix(ci): check_gatilhos exige pull_request sem filtro (#19)"
```

---

### Task 2: Documentação, comentário no workflow e PR

**Files:**
- Modify: `.github/workflows/ci.yml` (comentário acima de `  pull_request:`, linha 9)
- Modify: `CLAUDE.md` (bullet do CI e lista de lacunas conhecidas)
- Modify: `AGENTS.md` (os mesmos dois trechos, em português)

**Interfaces:**
- Consumes: a mensagem e a regra da Tarefa 1 (`pull_request` sem filtro nenhum).
- Produces: nada consumido por código.

- [ ] **Step 1: Comentário no `ci.yml`**

Trocar

```yaml
  pull_request:
  # Para gerar o dado sem precisar abrir PR: `gh workflow run CI --ref <branch>`.
```

por

```yaml
  # Sem filtro nenhum (branches, branches-ignore, types, paths): uma PR fora
  # do filtro nunca reporta os checks obrigatórios e espera para sempre.
  # check_gatilhos em scripts/qa/ci_invariants.sh falha se aparecer um (issue #19).
  pull_request:
  # Para gerar o dado sem precisar abrir PR: `gh workflow run CI --ref <branch>`.
```

- [ ] **Step 2: `CLAUDE.md`**

No bullet do CI, trocar `the workflow gains a \`paths\` filter or loses` por:

```
the workflow gains a `paths` filter, `pull_request` gains any filter at all (`branches`, `branches-ignore`, `types` — issue #19), or loses
```

E trocar `known gaps in the guard are issues #19, #21 (` por:

```
known gap in the guard is issue #21 (#19 fixed — `check_gatilhos` requires `pull_request` with no filter at all, so a PR against a protected branch can never be left waiting for checks that never run; 
```

- [ ] **Step 3: `AGENTS.md`**

Trocar `se o workflow ganhar filtro de \`paths\` ou perder` por:

```
se o workflow ganhar filtro de `paths`, se o `pull_request` ganhar qualquer filtro (`branches`, `branches-ignore`, `types` — issue #19) ou perder
```

E trocar `lacunas conhecidas da guarda nas issues #19 e #21 (` por:

```
lacuna conhecida da guarda na issue #21 (#19 corrigida — o `check_gatilhos` exige `pull_request` sem filtro nenhum, para uma PR contra branch protegida nunca ficar esperando checks que não rodam; 
```

- [ ] **Step 4: Conferir que nada quebrou**

Run: `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh && ./scripts/qa/ci_invariants_fcm_test.sh`
Expected: tudo verde (o comentário novo não toca segredo nem estrutura).

Se houver `actionlint` local: `actionlint .github/workflows/ci.yml` → sem saída.

Run: `grep -n '#19' CLAUDE.md AGENTS.md`
Expected: só as menções novas de "corrigida/fixed"; nenhuma lista "#19" como lacuna aberta.

- [ ] **Step 5: Atualizar o grafo e commitar**

```bash
graphify update .
git add .github/workflows/ci.yml CLAUDE.md AGENTS.md
git commit -m "docs(ci): registra a guarda dos filtros de pull_request (#19)"
```

- [ ] **Step 6: PR (confirmar com o usuário antes do push)**

```bash
git push -u origin fix/issue-19-gatilho-pull-request
gh pr create --base develop --title "fix(ci): check_gatilhos exige pull_request sem filtro (#19)" --body "$(cat <<'EOF'
Closes #19

## O que muda
- `check_gatilhos` (`scripts/qa/ci_invariants.sh`) falha quando `pull_request` tem qualquer filtro (`branches`, `branches-ignore`, `types`...). `paths`/`paths-ignore` seguem com `check_sem_filtro_de_paths`.
- `scripts/qa/ci_invariants_test.sh`: positivos (`branches: [main]`, `branches-ignore: [develop]`, `types: [opened]`, valor em lista, e duas recusas por forma) e negativos (`{}`, nulo, `on:` em lista, `paths` sem acusação duplicada).
- Comentário no `ci.yml`, `CLAUDE.md` e `AGENTS.md`.

## Verificação
- Antes: com `branches: [main]`, `branches-ignore: [develop]` ou `types: [opened]` numa cópia do `ci.yml` real, a guarda dizia `ok` (exit 0).
- Depois: os três casos saem com exit 1 e a mensagem da #19; o `ci.yml` real segue `ok: 9 grupos`.
EOF
)"
```

- [ ] **Step 7: Acompanhar a PR**

Run: `gh pr checks --watch`
Expected: os 8 checks obrigatórios verdes (o `workflow-lint` roda `ci_invariants_test.sh` no passo de lint). O `android-e2e` é informativo.

Depois do merge em `develop`, o `Closes #19` só fecha a issue quando chegar a `main` (branch padrão). Se o fluxo for fechar já: `gh issue close 19 --comment "Corrigida em <PR>: check_gatilhos exige pull_request sem filtro."`
