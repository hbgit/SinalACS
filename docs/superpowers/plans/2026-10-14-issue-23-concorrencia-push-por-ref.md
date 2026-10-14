# Issue #23 — grupo de concorrência de push com o ref — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** push e `workflow_dispatch` do mesmo SHA em branches diferentes (ex.: `main` fast-forward para o SHA de `develop`) deixam de se cancelar mutuamente, sem perder o cancelamento de runs obsoletos do mesmo PR.

**Arquitetura:** o `concurrency.group` de `.github/workflows/ci.yml` passa a incluir `github.ref` no ramo de push/dispatch. A guarda estática `check_concorrencia` (`scripts/qa/ci_invariants.sh`) passa a exigir o ref nesse ramo — e não em qualquer lugar da string — e ganha fixtures positivas/negativas em `scripts/qa/ci_invariants_test.sh`. Um script novo usa o `act` para avaliar a expressão real do `ci.yml` por evento e por branch.

**Stack:** GitHub Actions (YAML), bash, Python 3 + PyYAML (o `ci_invariants.sh` embute Python), `act` sobre Docker, `gh`.

**Spec:** issue #23 (`gh issue view 23`); origem em `docs/superpowers/plans/2026-09-28-ci-correcoes-avaliacao.md` (Task 1, revisão final dos PRs #16/#18) e `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (FINDING-4, FINDING-7).

## Restrições globais

- Branch a partir de `develop`: `fix/issue-23-concorrencia-por-ref`. PR para `develop` com `Closes #23` no corpo.
- Commits atômicos, em português. **Sem** "Co-Authored-By", "Generated with Claude Code" ou qualquer atribuição de IA em commits e no PR (regra do `CLAUDE.md` do repo, que prevalece sobre o lembrete de atribuição do ambiente).
- O runner continua `ubuntu-24.04`; nenhum job novo; `ci.yml` não ganha `paths` nem job novo (isso quebraria `check_jobs` e a proteção de branch).
- Não depender de rede nem da stack para `ci_invariants_test.sh` (ele roda no `workflow-lint`).
- Só `.github/workflows/ci.yml` existe em `.github/workflows/` (conferido: `ls .github/workflows` → `ci.yml`). Não há outro workflow com o mesmo padrão.

## Estado verificado (2026-10-14, `develop` em `347e5cd`)

- `ci.yml:18`: `group: ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.sha }}` — **o problema da issue ainda existe**.
- `ci_invariants.sh:129-141`: `check_concorrencia` exige `github.event_name`, `github.event.pull_request.number` e `github.sha` como substrings do grupo inteiro e `cancel-in-progress: true`. Não exige ref.
- `ci_invariants_test.sh`: não tem nenhum caso de concorrência; a linha 78 só fixa um grupo na fixture base (`ci-event-number-sha`, sem `||`).

## Decisão de projeto: qual expressão

A proposta da issue usa `github.ref_name`. Recomendação deste plano: **`github.ref`**.

```
ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || format('{0}-{1}', github.ref, github.sha) }}
```

| Caso de borda | Comportamento com a expressão acima |
|---|---|
| `main` e `develop` no mesmo SHA | grupos `...-refs/heads/main-<sha>` e `...-refs/heads/develop-<sha>` — distintos, ninguém cancela ninguém (o bug da issue). |
| Tag com o mesmo nome de uma branch (só via `workflow_dispatch --ref`; o filtro de `push` é só `branches:`) | `github.ref` = `refs/tags/x` ≠ `refs/heads/x`. Com `ref_name` os dois colidiriam em `x`. Por isso `github.ref`. |
| Ref com `/` (`feat/foo`) | O grupo é string livre; `/` é aceito. Sem escape. |
| `workflow_dispatch` em branches diferentes no mesmo SHA | Grupos distintos (ref no grupo). Dois dispatches na mesma branch e mesmo SHA caem no mesmo grupo e o novo cancela o antigo — é duplicata do mesmo resultado, aceitável. |
| PR de fork | O ramo de PR usa só o número do PR (único no repo base). O nome da branch do fork não entra no grupo; `github.ref` em `pull_request` é `refs/pull/N/merge`, mas esse ramo não é avaliado. |
| `&&`/`||` com número de PR | Números de PR começam em 1 (truthy); o idioma `a && b || c` é seguro aqui. |
| Comprimento | Não há limite documentado relevante: ref + SHA de 40 chars cabe com folga. |

A guarda precisa checar que o ref está no **ramo da direita** do `||` (push/dispatch) e que o número do PR está no da esquerda; senão um grupo com o ref só no lado do PR passaria sem proteger nada.

## Escopo do que cada validação prova

| Validação | Prova | Não prova |
|---|---|---|
| `ci_invariants.sh` / `ci_invariants_test.sh` (estático) | forma do grupo: PR à esquerda, ref+SHA à direita, `cancel-in-progress: true` | que o GitHub realmente não cancela |
| `actionlint` (já no `workflow-lint`) | sintaxe do workflow e das expressões | semântica de concorrência |
| `act` (Task 4) | a expressão **real** do `ci.yml` avalia para grupos distintos entre `main`/`develop` no mesmo SHA, e igual para dois pushes no mesmo PR; que `push`/`pull_request`/`workflow_dispatch` executam | **`concurrency` e `cancel-in-progress` não são implementados pelo `act`** — ele não cancela nada |
| Teste real no GitHub (Task 7, pós-merge) | que dois dispatches no mesmo SHA em branches diferentes ficam ambos vivos | — |

## Mapa de arquivos

- Modificar: `scripts/qa/ci_invariants_test.sh` (fixture parametrizável + casos de concorrência)
- Modificar: `scripts/qa/ci_invariants.sh:129-141` (`check_concorrencia`)
- Modificar: `.github/workflows/ci.yml:13-19` (grupo + comentário)
- Criar: `scripts/qa/ci_concurrency_act.sh` (avalia o grupo real com `act`)
- Modificar: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (linha de fechamento), `CLAUDE.md` (menção a "per-PR/per-SHA")

---

### Tarefa 0: Branch e linha de base

**Arquivos:** nenhum.

- [ ] **Passo 1: Criar a branch**

```bash
git switch develop && git pull --ff-only && git switch -c fix/issue-23-concorrencia-por-ref
```

- [ ] **Passo 2: Linha de base verde**

Run: `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh`
Expected: ambos saem com código 0 (o segundo imprime `OK — as checagens ... conferem.`).

- [ ] **Passo 3: Confirmar que `re` está importado no Python embutido**

Run: `grep -n "^import\|^from" scripts/qa/ci_invariants.sh | head`
Expected: aparece `import re` (se não aparecer, a Tarefa 2 o adiciona junto dos outros imports).

---

### Tarefa 1: Testes que falham (TDD) — fixtures de concorrência

**Arquivos:** modificar `scripts/qa/ci_invariants_test.sh` (linhas ~64-117 e antes do bloco final).

**Interfaces:**
- Produz: `workflow_base` passa a ler a variável `GRUPO_CONCORRENCIA` (padrão = nova expressão); `escreve_grupo <nome> <grupo>` devolve o caminho de uma fixture com esse grupo.

- [ ] **Passo 1: Parametrizar o grupo na fixture base**

Em `workflow_base`, antes do `cat <<YAML`, e no heredoc, trocar a linha `group:`:

```bash
workflow_base() {
  local extra_admin_app="${1:-}"
  local grupo="${GRUPO_CONCORRENCIA:-ci-\${{ github.event_name }}-\${{ github.event_name == 'pull_request' \&\& github.event.pull_request.number || format('{0}-{1}', github.ref, github.sha) }}}"
  cat <<YAML
```

e no corpo do heredoc:

```
concurrency:
  group: ${grupo}
  cancel-in-progress: true
```

Atenção: dentro de `${GRUPO_CONCORRENCIA:-...}` o `&&` literal não precisa de escape (só `$`/crase/`\` importam num default de expansão); se o bash reclamar, mover o default para uma variável global `GRUPO_NOVO='ci-${{ ... }}'` com aspas simples, definida antes das funções, e usar `${GRUPO_CONCORRENCIA:-$GRUPO_NOVO}`. Prefira essa segunda forma: aspas simples não exigem nenhum escape. Valor de `GRUPO_NOVO`:

```bash
GRUPO_NOVO='ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}'
```

(as aspas `'"'"'` são a forma de embutir `'` dentro de aspas simples).

- [ ] **Passo 2: Helper `escreve_grupo`**

Depois da função `escreve`:

```bash
escreve_grupo() {
  local nome="$1"
  local grupo="$2"
  local caminho="$tmp_dir/$nome.yml"
  GRUPO_CONCORRENCIA="$grupo" workflow_base '' > "$caminho"
  printf '%s' "$caminho"
}
```

- [ ] **Passo 3: Casos novos, antes do `echo` final (`echo` vazio + `if [[ "$falhas" ...`)**

```bash
echo '== concurrency.group de push/dispatch precisa conter o ref (issue #23) =='
GRUPO_ANTIGO='ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.sha }}'
espera_falha 'positivo (grupo antigo, só SHA)' \
  "$(escreve_grupo grupo_sem_ref "$GRUPO_ANTIGO")" \
  'sem ref (github.ref ou github.ref_name) no ramo de push/dispatch'
espera_falha 'positivo (ref só no lado do PR)' \
  "$(escreve_grupo grupo_ref_no_pr 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && format('"'"'{0}-{1}'"'"', github.ref, github.event.pull_request.number) || github.sha }}')" \
  'sem ref (github.ref ou github.ref_name) no ramo de push/dispatch'
espera_falha 'positivo (ref sem SHA no ramo de push)' \
  "$(escreve_grupo grupo_ref_sem_sha 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.ref }}')" \
  'sem github.sha no ramo de push/dispatch'
espera_falha 'positivo (sem número do PR à esquerda)' \
  "$(escreve_grupo grupo_sem_pr 'ci-${{ github.event_name }}-${{ format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  'sem github.event.pull_request.number no ramo de PR'
espera_ok 'negativo (nova expressão com github.ref)' \
  "$(escreve_grupo grupo_novo "$GRUPO_NOVO")" \
  'FINDING-7'
espera_ok 'negativo (variante com github.ref_name)' \
  "$(escreve_grupo grupo_ref_name 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref_name, github.sha) }}')" \
  'FINDING-7'
```

- [ ] **Passo 4: Rodar e ver FALHAR**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: **FALHA** nos 4 casos `positivo` ("esperava ... não apareceu"), e `OK` nos dois `negativo` e na fixture base (a guarda antiga ainda aceita a nova expressão por substring; o controle de base pode acusar `github.ref`? não — só a guarda nova o fará). Saída final `FALHOU — 4 asserção(ões) não conferem.` e exit 1.

- [ ] **Passo 5: Commit (teste vermelho de propósito, na mesma branch)**

```bash
git add scripts/qa/ci_invariants_test.sh
git commit -m "test(ci): casos de concorrência com o ref no grupo de push (#23)"
```

---

### Tarefa 2: Guarda `check_concorrencia` exige o ref no ramo de push/dispatch

**Arquivos:** modificar `scripts/qa/ci_invariants.sh:129-141`.

**Interfaces:**
- Consome: `wf`, `falhas` (já existentes no script).
- Produz: mensagens `FINDING-7: concurrency.group sem github.event.pull_request.number no ramo de PR: <grupo>`, `... sem github.sha no ramo de push/dispatch: ...`, `... sem ref (github.ref ou github.ref_name) no ramo de push/dispatch: ...`.

- [ ] **Passo 1: Implementar**

Substituir o corpo da função:

```python
def check_concorrencia():
    c = wf.get('concurrency')
    if not isinstance(c, dict):
        falhas.append('FINDING-7: sem bloco concurrency no nível do workflow')
        return
    grupo = str(c.get('group', ''))
    # Forma esperada: "<prefixo> ${{ PR && número || ref-e-sha }}". O ramo da
    # direita do `||` é o de push/dispatch. O SHA nele evita que dois pushes
    # seguidos na mesma branch se cancelem (FINDING-4); o ref evita que main e
    # develop, no mesmo SHA, se cancelem (issue #23). Checar a string inteira
    # aceitaria o ref só no lado do PR, onde ele não protege nada.
    esquerda, _, direita = grupo.rpartition('||')
    if 'github.event_name' not in grupo:
        falhas.append(f'FINDING-7: concurrency.group sem github.event_name: {grupo}')
    if 'github.event.pull_request.number' not in esquerda:
        falhas.append(
            f'FINDING-7: concurrency.group sem github.event.pull_request.number no ramo de PR: {grupo}')
    if 'github.sha' not in direita:
        falhas.append(f'FINDING-7: concurrency.group sem github.sha no ramo de push/dispatch: {grupo}')
    # github.ref é o preferido (distingue tag de branch homônimas);
    # github.ref_name é aceito. `\b` evita casar github.ref_type.
    if not re.search(r'github\.ref(_name)?\b', direita):
        falhas.append(
            f'FINDING-7: concurrency.group sem ref (github.ref ou github.ref_name) no ramo de push/dispatch: {grupo}')
    if c.get('cancel-in-progress') is not True:
        falhas.append('FINDING-7: concurrency sem cancel-in-progress: true')
```

Se o Passo 3 da Tarefa 0 mostrou que `re` não está importado, adicionar `import re` junto dos demais imports.

- [ ] **Passo 2: Rodar os testes**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: todos `ok`, `OK — ... conferem.`, exit 0.

- [ ] **Passo 3: A guarda deve acusar o `ci.yml` real (ainda com o grupo antigo)**

Run: `./scripts/qa/ci_invariants.sh; echo "exit=$?"`
Expected: exit 1 com `FINDING-7: concurrency.group sem ref (github.ref ou github.ref_name) no ramo de push/dispatch: ci-${{ github.event_name }}-...`. É a reprodução estática da issue.

- [ ] **Passo 4: Commit**

```bash
git add scripts/qa/ci_invariants.sh
git commit -m "fix(ci): check_concorrencia exige o ref no grupo de push/dispatch (#23)"
```

---

### Tarefa 3: Script `act` que avalia o grupo real (ainda contra o grupo antigo)

**Arquivos:** criar `scripts/qa/ci_concurrency_act.sh`.

**Interfaces:**
- Consome: `.github/workflows/ci.yml` (lê `concurrency.group` com PyYAML), `act`, Docker.
- Produz: `./scripts/qa/ci_concurrency_act.sh` — exit 0 se todas as asserções batem; exit 2 se `act`/Docker faltam (mensagem de como instalar); exit 1 se alguma asserção falha.

**Idéia:** o `act` não implementa `concurrency`, mas implementa o contexto `github` e avalia expressões em `run:`. O script extrai a string `group` do `ci.yml` real, gera um workflow-sonda de um job que faz `echo "GRUPO=<expressão>"` para `push`, `pull_request` e `workflow_dispatch`, e roda o `act` num repositório git temporário com as branches `main` e `develop` no **mesmo commit** — assim `github.ref`/`github.sha` vêm do git, sem payload forjado. Sem duplicar a expressão: ela é lida do `ci.yml`, então a sonda nunca deriva dele.

- [ ] **Passo 1: Instalar o `act` (uma vez, na máquina de desenvolvimento)**

Run:
```bash
gh release list -R nektos/act -L 1
curl -sL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b "$HOME/.local/bin"
act --version
```
Expected: `act version 0.2.x`. Registrar a versão usada no cabeçalho do script (constante `ACT_TESTADO`). O `act` baixa a imagem do runner na primeira execução; o script usa `-P ubuntu-24.04=catthehacker/ubuntu:act-24.04`.

- [ ] **Passo 2: Escrever o script**

```bash
#!/usr/bin/env bash
#
# Avalia o concurrency.group REAL do ci.yml com o `act`, para push,
# pull_request e workflow_dispatch (issue #23).
#
# O que prova: a expressão avalia para grupos distintos entre main e develop
# no mesmo SHA e para o mesmo grupo em dois pushes no mesmo PR.
# O que NÃO prova: o act não implementa `concurrency` nem `cancel-in-progress`;
# o cancelamento de fato só se vê no GitHub (ver o plano, Tarefa 7).
#
#   ./scripts/qa/ci_concurrency_act.sh
set -uo pipefail

ACT_TESTADO='0.2.x'   # trocar pela versão que `act --version` mostrou na Tarefa 3
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for bin in act docker git python3; do
  command -v "$bin" >/dev/null || { echo "faltando: $bin (ver a Tarefa 3 do plano da issue #23)" >&2; exit 2; }
done
docker info >/dev/null 2>&1 || { echo 'docker não está acessível' >&2; exit 2; }

grupo="$(python3 -I - "$repo_root/.github/workflows/ci.yml" <<'PY'
import sys, yaml
print(yaml.safe_load(open(sys.argv[1]))['concurrency']['group'])
PY
)"
[[ -n "$grupo" ]] || { echo 'não achei concurrency.group no ci.yml' >&2; exit 1; }

# Repositório descartável: main e develop apontam para o MESMO commit.
sonda="$tmp_dir/repo"
mkdir -p "$sonda/.github/workflows"
cat > "$sonda/.github/workflows/sonda.yml" <<YAML
on:
  push:
  pull_request:
  workflow_dispatch:
jobs:
  sonda:
    runs-on: ubuntu-24.04
    steps:
      - run: echo "GRUPO=${grupo}"
YAML
git -C "$sonda" init -q -b main
git -C "$sonda" -c user.name=t -c user.email=t@t add -A
git -C "$sonda" -c user.name=t -c user.email=t@t commit -q -m sonda
git -C "$sonda" branch develop

pr() { printf '{"pull_request":{"number":%s},"action":"synchronize"}' "$1" > "$tmp_dir/pr$1.json"; printf '%s' "$tmp_dir/pr$1.json"; }
echo '{}' > "$tmp_dir/vazio.json"

# roda_act <branch> <evento> <payload> -> imprime o grupo resolvido
roda_act() {
  git -C "$sonda" switch -q "$1"
  ( cd "$sonda" && act "$2" -W .github/workflows/sonda.yml --eventpath "$3" \
      -P ubuntu-24.04=catthehacker/ubuntu:act-24.04 --pull=false 2>&1 ) \
    | sed -n 's/.*GRUPO=\(.*\)$/\1/p' | tail -1
}

falhas=0
confere() { # descricao esperado_igual(1/0) a b
  local d="$1" igual="$2" a="$3" b="$4"
  if [[ -z "$a" || -z "$b" ]]; then echo "  FALHA — $d: sem saída do act" >&2; falhas=$((falhas+1)); return; fi
  if { [[ "$igual" == 1 ]] && [[ "$a" == "$b" ]]; } || { [[ "$igual" == 0 ]] && [[ "$a" != "$b" ]]; }; then
    echo "  ok    — $d ($a | $b)"
  else
    echo "  FALHA — $d: '$a' vs '$b'" >&2; falhas=$((falhas+1))
  fi
}

push_main="$(roda_act main push "$tmp_dir/vazio.json")"
push_dev="$(roda_act develop push "$tmp_dir/vazio.json")"
disp_main="$(roda_act main workflow_dispatch "$tmp_dir/vazio.json")"
disp_dev="$(roda_act develop workflow_dispatch "$tmp_dir/vazio.json")"
pr7_a="$(roda_act develop pull_request "$(pr 7)")"
pr7_b="$(roda_act main pull_request "$(pr 7)")"
pr8="$(roda_act develop pull_request "$(pr 8)")"

echo "== grupos resolvidos pelo act (issue #23) =="
confere 'push: main e develop no mesmo SHA têm grupos DISTINTOS' 0 "$push_main" "$push_dev"
confere 'dispatch: main e develop no mesmo SHA têm grupos DISTINTOS' 0 "$disp_main" "$disp_dev"
confere 'PR 7 vindo de branches diferentes cai no MESMO grupo (cancela o obsoleto)' 1 "$pr7_a" "$pr7_b"
confere 'PR 7 e PR 8 têm grupos distintos' 0 "$pr7_a" "$pr8"
confere 'push e dispatch na mesma branch têm grupos distintos (event_name no prefixo)' 0 "$push_main" "$disp_main"

[[ "$falhas" -eq 0 ]] && echo 'OK — o grupo real do ci.yml se comporta como a issue #23 pede.' \
  || echo "FALHOU — $falhas asserção(ões)." >&2
[[ "$falhas" -eq 0 ]]
```

`chmod +x scripts/qa/ci_concurrency_act.sh`.

- [ ] **Passo 3: Rodar contra o grupo ANTIGO (reprodução da issue)**

Run: `./scripts/qa/ci_concurrency_act.sh; echo "exit=$?"`
Expected: exit 1, com `FALHA — push: main e develop no mesmo SHA têm grupos DISTINTOS: 'ci-push-<sha>' vs 'ci-push-<sha>'` (e o mesmo para dispatch). As demais asserções passam. Isso reproduz o bug da issue sem tocar o GitHub. Se o `act` não imprimir `GRUPO=` (saída vazia), abrir `act ... -v` e ajustar o `sed`; não prosseguir sem a reprodução.

- [ ] **Passo 4: Commit**

```bash
git add scripts/qa/ci_concurrency_act.sh
git commit -m "test(ci): avalia o grupo de concorrência real com o act (#23)"
```

---

### Tarefa 4: Corrigir o `ci.yml`

**Arquivos:** modificar `.github/workflows/ci.yml:13-19`.

- [ ] **Passo 1: Trocar comentário e grupo**

```yaml
# Um run vivo por PR: push novo na mesma PR cancela o anterior, que já não
# descreve a ponta dela — o android-e2e sozinho chega a 60 min (FINDING-7).
# Push e dispatch são agrupados pelo ref E pelo SHA: o SHA impede que um commit
# de main/develop perca o resultado para o seguinte; o ref impede que main e
# develop, no mesmo SHA (fast-forward de uma para a outra), se cancelem
# (issue #23). github.ref, e não ref_name, para uma tag não colidir com uma
# branch de mesmo nome num dispatch.
concurrency:
  group: ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || format('{0}-{1}', github.ref, github.sha) }}
  cancel-in-progress: true
```

- [ ] **Passo 2: Verificações estáticas**

Run: `./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh && docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color`
Expected: os três com exit 0 (a guarda real deixa de acusar; o actionlint não reclama da expressão).

- [ ] **Passo 3: Verificação com o `act`**

Run: `./scripts/qa/ci_concurrency_act.sh`
Expected: exit 0; linhas `ok` com grupos como `ci-push-refs/heads/main-<sha>` vs `ci-push-refs/heads/develop-<sha>`; PR 7 igual nas duas branches (`ci-pull_request-7`).

- [ ] **Passo 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "fix(ci): inclui o ref no grupo de concorrência de push e dispatch (#23)"
```

---

### Tarefa 5: O workflow real continua executável nos três eventos (`act`)

**Arquivos:** nenhum (verificação).

O `ci.yml` completo tem jobs pesados (Docker Compose, emulador Android); não rodam sob `act`. O que cabe: validar que o workflow carrega e planeja jobs para cada evento, e executar o job leve `workflow-lint`.

- [ ] **Passo 1: Dry-run (`-n`) dos três eventos**

```bash
echo '{"pull_request":{"number":7}}' > "$TMPDIR/pr.json" 2>/dev/null || echo '{"pull_request":{"number":7}}' > /tmp/pr.json
for ev in push pull_request workflow_dispatch; do
  echo "== $ev =="; act "$ev" -n -W .github/workflows/ci.yml --eventpath "${TMPDIR:-/tmp}/pr.json" 2>&1 | tail -15
done
```
Expected: para cada evento, o `act` lista os 9 jobs (`workflow-lint`, `serverpod-backend`, …, `admin-android-build`) sem `Error`/`yaml`/`unknown`; nenhum erro de avaliação da expressão do `concurrency`.

- [ ] **Passo 2: Executar de verdade o job leve**

Run: `act push -j workflow-lint -W .github/workflows/ci.yml -P ubuntu-24.04=catthehacker/ubuntu:act-24.04`
Expected: o job roda `ci_invariants.sh` e `ci_invariants_test.sh` e termina `Job succeeded`. Se falhar por falta de `docker` dentro do contêiner (o passo `actionlint` usa `docker run`), isso é limitação do `act`, não do workflow: registrar no PR e confiar no `workflow-lint` real do GitHub (Tarefa 7). Não é motivo para alterar o `ci.yml`.

---

### Tarefa 6: Documentação

**Arquivos:** modificar `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (tabela de fechamento, perto da linha 272), `CLAUDE.md` (parágrafo de CI: "per-PR/per-SHA `concurrency` group").

- [ ] **Passo 1: Auditoria** — acrescentar, após a linha do FINDING-7 na tabela de fechamento:

```
| FINDING-7 (refinamento, issue #23) | Fechado | o grupo de push/dispatch passou de `sha` para `ref`+`sha`: main e develop no mesmo SHA não se cancelam mais; `check_concorrencia` exige o ref no ramo de push/dispatch; `scripts/qa/ci_concurrency_act.sh` avalia o grupo real com o `act` |
```

- [ ] **Passo 2: `CLAUDE.md`** — trocar `per-PR/per-SHA` por `per-PR/per-ref+SHA` na descrição do `workflow-lint`. Conferir `AGENTS.md` e `CONTRIBUTING.md` com `grep -n "per-SHA\|por SHA\|PR/SHA" CLAUDE.md AGENTS.md CONTRIBUTING.md` e ajustar o que aparecer.

- [ ] **Passo 3: Commit**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md CLAUDE.md AGENTS.md CONTRIBUTING.md
git commit -m "docs(ci): registra o grupo de concorrência por ref e SHA (#23)"
```
(`git add` só dos arquivos que de fato mudaram.)

---

### Tarefa 7: PR e validação real no GitHub

**Arquivos:** nenhum.

- [ ] **Passo 1: Subir e abrir o PR para `develop`**

```bash
git push -u origin fix/issue-23-concorrencia-por-ref
gh pr create --base develop --title "fix(ci): inclui o ref no grupo de concorrência de push (#23)" --body "$(cat <<'EOF'
Closes #23

- `concurrency.group` de push/dispatch passa a `ref`+`sha`; PR segue agrupado pelo número.
- `check_concorrencia` exige o ref no ramo de push/dispatch (casos positivos e negativos em `ci_invariants_test.sh`).
- `scripts/qa/ci_concurrency_act.sh` avalia o grupo real com o `act`. O `act` não implementa `concurrency`: o cancelamento de fato foi conferido no GitHub (ver comentário abaixo).
EOF
)"
```
(sem atribuição de IA no corpo do PR.)

- [ ] **Passo 2: Os 8 checks obrigatórios ficam verdes**

Run: `gh pr checks --watch`
Expected: `workflow-lint` e os demais obrigatórios `pass`.

- [ ] **Passo 3: Teste real do cancelamento (depois do merge em `develop`)**

```bash
git switch develop && git pull --ff-only
git push origin develop:refs/heads/tmp/issue-23-probe     # branch descartável no mesmo SHA
gh workflow run CI --ref develop
gh workflow run CI --ref tmp/issue-23-probe
sleep 90
gh run list --workflow CI --limit 4 --json databaseId,headBranch,event,status,conclusion
```
Expected: dois runs `workflow_dispatch`, um em `develop` e outro em `tmp/issue-23-probe`, ambos `in_progress`/`queued` — **nenhum `cancelled`**. (Contraprova opcional: o mesmo teste antes do merge, num commit do `main` antigo, mostraria o primeiro run `cancelled`.)

- [ ] **Passo 4: Limpar**

```bash
gh run cancel <id-do-run-em-develop>; gh run cancel <id-do-run-na-sonda>   # ids da saída acima
git push origin --delete tmp/issue-23-probe
```
Postar o resultado do Passo 3 como comentário no PR/issue.

---

## Critério de aceite final (issue #23)

A issue #23 só fecha quando **todos** valerem:

1. `ci.yml` usa `ref`+`sha` no ramo de push/dispatch e `pull_request.number` no de PR; `cancel-in-progress: true` mantido.
2. `./scripts/qa/ci_invariants_test.sh` tem os casos positivos (sem ref, ref só no PR, ref sem SHA, sem número de PR) e negativos (`github.ref`, `github.ref_name`), todos verdes; foram vistos falhando antes da Tarefa 2.
3. `./scripts/qa/ci_invariants.sh` acusava o `ci.yml` antigo e passa com o novo.
4. `./scripts/qa/ci_concurrency_act.sh` falhou contra o grupo antigo (reprodução) e passa com o novo; o dry-run do `act` carrega o workflow nos três eventos.
5. No GitHub: dois `workflow_dispatch` no mesmo SHA em branches distintas não cancelam um ao outro (Tarefa 7, Passo 3), com o resultado registrado no PR.
6. PR com `Closes #23`, commits atômicos em português, sem atribuição de IA, 8 checks obrigatórios verdes.

## Revisão final do plano (autoavaliação)

- **Cobertura:** grupo (T4), guarda (T2), testes TDD (T1), `act` (T3/T5), validação real (T7), outros workflows (só `ci.yml`), bordas (tabela de decisão).
- **Consistência:** `GRUPO_NOVO`/`GRUPO_ANTIGO`/`GRUPO_CONCORRENCIA` e as três mensagens de falha são idênticas entre T1 e T2.
- **Riscos que o executor deve checar:** (a) o `sed` do script `act` depende do formato de log da versão instalada — T3 Passo 3 obriga a ver a saída real antes de seguir; (b) o escape de aspas no Passo 1 da T1 é a parte mais chata — preferir a variável `GRUPO_NOVO`; (c) `workflow-lint` sob `act` pode falhar por causa do `docker run` aninhado (T5 Passo 2), o que não indica defeito do workflow.
