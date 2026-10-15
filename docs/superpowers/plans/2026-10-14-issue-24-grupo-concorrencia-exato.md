# Issue #24: `check_concorrencia` por igualdade exata — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `check_concorrencia` (`scripts/qa/ci_invariants.sh`) passa a comparar o `concurrency.group` do `ci.yml` por igualdade exata com uma constante canônica, em vez de buscar substrings, e a issue #24 é fechada como corrigida (não `wontfix`).

**Architecture:** Uma constante `GRUPO_CONCORRENCIA` no Python embutido do `ci_invariants.sh` guarda o texto revisado do grupo; a checagem compara `==` e, se diferir, imprime o esperado e o atual. A semântica desse texto (grupos distintos entre main/develop no mesmo SHA etc.) continua provada pelo `scripts/qa/ci_concurrency_act.sh` (com o `act`); a guarda passa a provar só que o texto é o revisado. As fixtures de `scripts/qa/ci_invariants_test.sh` são reescritas para a nova mensagem e os falsos negativos da issue viram casos positivos.

**Tech Stack:** bash, python3 + PyYAML (embutido via heredoc), GitHub Actions.

**Spec:** issue #24 (`gh issue view 24`). Texto relevante: *"Avaliar se vale mais comparar o `group` com o valor esperado exato (ou com uma pequena lista de formas aceitas) do que procurar por substring. Se não valer, fechar como `wontfix` com esta justificativa."* Contexto: `docs/superpowers/plans/2026-10-14-issue-63-acabamentos-guarda-concorrencia.md` (as limitações da substring foram registradas lá, não corrigidas).

## Verificação feita ao escrever o plano (2026-10-14, `develop` em `64b59ce`)

A issue ainda procede, e o impacto é maior que o "Baixo" escrito nela. Os dois grupos abaixo, colados no lugar do grupo real do `ci.yml`, passam pela guarda atual (`ok: 9 grupos de invariantes do CI`, exit 0):

- **Ramo morto:** `ci-${{ github.event_name }}-${{ false && github.event.pull_request.number || 'x' || format('{0}-{1}', github.ref, github.sha) }}` avalia para `ci-push-x` em **todo** push. Com `cancel-in-progress: true`, cada push em qualquer branch cancelaria o anterior, que é exatamente a regressão para a qual a guarda existe (FINDING-4/#23). A substring aceita porque `rpartition('||')` só olha o último `||`.
- **Ref num literal:** `... || format('{0}-github.ref', github.sha) }}` (o ref vira texto, não entra no grupo; main e develop no mesmo SHA voltam a colidir, #23).

Por que comparação exata em vez de `wontfix` ou de "uma pequena lista de formas aceitas":
- A guarda **já** recusa toda forma não canônica (o comentário do #63 diz "de propósito: a guarda só sabe ler a forma canônica"). A igualdade exata não recusa nada legítimo que hoje passe, salvo uma forma (`format('{0}', github.event_name)` no prefixo) que ninguém usa.
- Uma lista de formas é YAGNI: só há uma forma em uso, e cada forma nova teria de passar pelo `act` de qualquer jeito.
- Custo aceito: mudar o grupo exige mudar no mesmo commit o `ci.yml`, a constante e o `GRUPO_NOVO` da fixture. É o mesmo contrato do `RUNNER` (trocar de imagem "tem de ser um PR, não uma surpresa").

## Global Constraints

- Sem novo job no CI: o teste continua no passo existente do `workflow-lint` (um job novo exige mexer em `JOBS_DOCUMENTADOS`, `CLAUDE.md`, `AGENTS.md` e na proteção de branch).
- Runner fixo `ubuntu-24.04`; nada de `ubuntu-latest`.
- O grupo real do `ci.yml` **não muda**: `ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || format('{0}-{1}', github.ref, github.sha) }}`.
- Mensagens, comentários e commits em português, no estilo dos commits do #63 (`fix(ci): ... (#24)`).
- **Sem** linhas `Co-Authored-By`, "Generated with Claude Code" ou qualquer atribuição a IA em commits e na descrição da PR (regra do `CLAUDE.md`, que vale acima de qualquer lembrete do harness).
- Só python3 + PyYAML; nada de rede no `ci_invariants.sh`.

## Review Focus

1. **O mesmo texto entre aspas duplas no YAML** (`group: "ci-${{ ... }}"`) é o mesmo grupo e tem de passar. Coberto na Tarefa 1 (negativo `grupo_aspas`).
2. **Comentário YAML no fim da linha** (`group: ci-... }} # nota`) é removido pelo parser e tem de passar. Coberto na Tarefa 1 (negativo `grupo_comentario`).
3. **`group:` vazio ou nulo** tem de gerar a falha FINDING-7 legível, não `atual: None` nem traceback. Coberto na Tarefa 1 (positivos `grupo_vazio` e `grupo_nulo`).
4. **O `ci.yml` real** tem de continuar verde depois da troca. Coberto na Tarefa 1, passo 4 (roda `ci_invariants.sh` sem fixture).
5. **Deriva entre as três cópias do texto** (`ci.yml`, `GRUPO_CONCORRENCIA`, `GRUPO_NOVO`): mudar uma sem as outras tem de falhar em algum lugar visível. O `ci_invariants.sh` real pega `ci.yml` ≠ constante; o controle de base do `ci_invariants_test.sh` (fixture com `GRUPO_NOVO` tem de sair limpa) pega constante ≠ `GRUPO_NOVO`. Conferido na Tarefa 1, passo 5.

---

## Estrutura de arquivos

- Modify: `scripts/qa/ci_invariants.sh` — `check_concorrencia` (linhas 129–175 hoje) e uma constante nova logo acima dela.
- Modify: `scripts/qa/ci_invariants_test.sh` — cabeçalho (linhas 3–8), bloco de casos de concorrência (do `echo '== concurrency.group de push/dispatch` até o fim do caso `ref_sobrando`) e a mensagem final.
- Modify: `.github/workflows/ci.yml` — só o comentário acima de `concurrency:` (linhas 13–19).
- Modify: `CLAUDE.md` (linha 109), `AGENTS.md` (linha 151), `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (tabela, depois da linha 274).

---

### Task 1: Igualdade exata no `check_concorrencia`, com as fixtures reescritas

**Files:**
- Modify: `scripts/qa/ci_invariants.sh:129-175`
- Test: `scripts/qa/ci_invariants_test.sh`

**Interfaces:**
- Consumes: as funções de teste existentes `escreve_grupo <nome> <grupo>`, `espera_falha <descrição> <fixture> <trecho>`, `espera_ok <descrição> <fixture> <trecho>` e as variáveis `GRUPO_NOVO`/`GRUPO_ANTIGO` de `ci_invariants_test.sh`. O `workflow_base` escreve o grupo cru como `  group: ${grupo}` (linha 87), então aspas e comentários passados no argumento chegam ao YAML como estão.
- Produces: a constante Python `GRUPO_CONCORRENCIA` (str) e a mensagem de falha que começa por `FINDING-7: concurrency.group difere da forma canônica`. A Tarefa 2 cita os dois nomes na documentação.

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull --ff-only
git switch -c fix/issue-24-grupo-concorrencia-exato
```

- [ ] **Step 2: Reescrever os casos de concorrência do teste (devem falhar)**

Em `scripts/qa/ci_invariants_test.sh`, troque o cabeçalho das linhas 3–8:

```bash
# Controles positivo e negativo de checagens de scripts/qa/ci_invariants.sh:
# as três da issue #20 (um check obrigatório que passa verde sem ter rodado
# por causa de continue-on-error, strategy.matrix ou needs: apontando para um
# job fora de CHECKS_OBRIGATORIOS) e a do concurrency.group (issues #23, #63 e
# #24: o grupo tem de ser exatamente GRUPO_CONCORRENCIA; cada regressão que a
# busca por substring pegava, e as que ela deixava passar, são casos aqui).
```

Depois apague tudo desde a linha `echo '== concurrency.group de push/dispatch precisa conter github.ref (issues #23 e #63) =='` até o fim do caso `espera_ok 'limitação aceita (ref como argumento sobrando de format)' ...` (inclusive as duas linhas de argumento dele) e cole no lugar:

```bash
echo '== concurrency.group tem de ser exatamente a forma canônica (issues #23, #63 e #24) =='
# GRUPO_NOVO é cópia de GRUPO_CONCORRENCIA (ci_invariants.sh) e do group do
# ci.yml; o controle de base acima falha se as cópias divergirem.
MSG_GRUPO='FINDING-7: concurrency.group difere da forma canônica'

# Regressões que a busca por substring já pegava (#23, #63).
espera_falha 'positivo (grupo antigo, só SHA)' \
  "$(escreve_grupo grupo_sem_ref "$GRUPO_ANTIGO")" "$MSG_GRUPO"
espera_falha 'positivo (ref só no lado do PR)' \
  "$(escreve_grupo grupo_ref_no_pr 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && format('"'"'{0}-{1}'"'"', github.ref, github.event.pull_request.number) || github.sha }}')" \
  "$MSG_GRUPO"
espera_falha 'positivo (ref sem SHA no ramo de push)' \
  "$(escreve_grupo grupo_ref_sem_sha 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.ref }}')" \
  "$MSG_GRUPO"
espera_falha 'positivo (sem número do PR à esquerda)' \
  "$(escreve_grupo grupo_sem_pr 'ci-${{ github.event_name }}-${{ format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  "$MSG_GRUPO"
# ref_name colide tag e branch homônimas num dispatch (#63).
espera_falha 'positivo (github.ref_name em vez de github.ref)' \
  "$(escreve_grupo grupo_ref_name 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref_name, github.sha) }}')" \
  "$MSG_GRUPO"
espera_falha 'positivo (github.ref_type não é github.ref)' \
  "$(escreve_grupo grupo_ref_type 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref_type, github.sha) }}')" \
  "$MSG_GRUPO"
# Só no ternário, push e dispatch no mesmo ref+SHA se cancelam (#63).
espera_falha 'positivo (event_name só na condição do ternário)' \
  "$(escreve_grupo evento_so_no_ternario 'ci-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  "$MSG_GRUPO"
espera_falha 'positivo (sem expressão nenhuma)' \
  "$(escreve_grupo grupo_literal 'ci-fixo')" "$MSG_GRUPO"
# '' e null como escalares YAML: um argumento vazio faria o workflow_base cair
# de volta em GRUPO_NOVO (${GRUPO_CONCORRENCIA:-...}).
espera_falha 'positivo (group: vazio)' \
  "$(escreve_grupo grupo_vazio "''")" "$MSG_GRUPO"
espera_falha 'positivo (group: null)' \
  "$(escreve_grupo grupo_nulo 'null')" "$MSG_GRUPO"

# Falsos negativos da substring (#24): os termos aparecem no texto mas não
# entram no grupo resolvido.
espera_falha '#24 (ref como argumento sobrando de format)' \
  "$(escreve_grupo ref_sobrando 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}'"'"', github.sha, github.ref) }}')" \
  "$MSG_GRUPO"
espera_falha '#24 (ref só dentro de um literal)' \
  "$(escreve_grupo ref_em_literal 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-github.ref'"'"', github.sha) }}')" \
  "$MSG_GRUPO"
# Avalia para ci-push-x em todo push: todo push cancelaria o anterior.
espera_falha '#24 (ref e SHA num ramo que nunca é avaliado)' \
  "$(escreve_grupo ramo_morto 'ci-${{ github.event_name }}-${{ false && github.event.pull_request.number || '"'"'x'"'"' || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  "$MSG_GRUPO"

# Formas legítimas não canônicas: recusadas de propósito. Mudar o grupo é
# mudar ci.yml, GRUPO_CONCORRENCIA e GRUPO_NOVO juntos, e provar com o
# ci_concurrency_act.sh o que a forma nova avalia.
espera_falha 'recusa por forma (ref no prefixo, fora do ramo de push)' \
  "$(escreve_grupo ref_no_prefixo 'ci-${{ github.event_name }}-${{ github.ref }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.sha }}')" \
  "$MSG_GRUPO"
espera_falha 'recusa por forma (github['"'"'ref'"'"'] em vez de github.ref)' \
  "$(escreve_grupo ref_indexado 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github['"'"'ref'"'"'], github.sha) }}')" \
  "$MSG_GRUPO"
espera_falha 'recusa por forma (ternário invertido)' \
  "$(escreve_grupo ternario_invertido 'ci-${{ github.event_name }}-${{ github.event_name != '"'"'pull_request'"'"' && format('"'"'{0}-{1}'"'"', github.ref, github.sha) || github.event.pull_request.number }}')" \
  "$MSG_GRUPO"
espera_falha 'recusa por forma (event_name no prefixo dentro de format)' \
  "$(escreve_grupo evento_em_format 'ci-${{ format('"'"'{0}'"'"', github.event_name) }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  "$MSG_GRUPO"

# Negativos: o mesmo texto, escrito de jeitos que o YAML lê igual.
espera_ok 'negativo (forma canônica)' \
  "$(escreve_grupo grupo_novo "$GRUPO_NOVO")" 'FINDING-7'
espera_ok 'negativo (forma canônica entre aspas duplas no YAML)' \
  "$(escreve_grupo grupo_aspas "\"$GRUPO_NOVO\"")" 'FINDING-7'
espera_ok 'negativo (forma canônica com comentário YAML no fim)' \
  "$(escreve_grupo grupo_comentario "$GRUPO_NOVO # mesmo grupo")" 'FINDING-7'
```

E troque a mensagem final de sucesso:

```bash
  echo 'OK — as checagens de "verde sem rodar" (issue #20) e do grupo de concorrência (issues #23, #63 e #24) conferem.'
```

- [ ] **Step 3: Rodar o teste e ver falhar**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: exit 1, `FALHOU — N asserção(ões)`. Todo `espera_falha` de concorrência falha (a mensagem `difere da forma canônica` ainda não existe), inclusive os três `#24`, que hoje passam calados pela guarda. Os três `negativo` passam. Os casos #20 continuam `ok`.

- [ ] **Step 4: Implementar a igualdade exata**

Em `scripts/qa/ci_invariants.sh`, substitua a função `check_concorrencia` inteira (de `def check_concorrencia():` até a linha `falhas.append('FINDING-7: concurrency sem cancel-in-progress: true')`, inclusive) por:

```python
# O concurrency.group revisado, comparado por igualdade exata (issue #24).
# Cada pedaço tem motivo:
# - github.event_name no prefixo, fora do ternário: o ramo da direita não
#   carrega o evento, e sem ele um push e um dispatch no mesmo ref+SHA se
#   cancelariam (issue #63);
# - github.event.pull_request.number no ramo de PR: um run vivo por PR;
# - github.sha no ramo de push/dispatch: dois pushes seguidos na mesma branch
#   não se cancelam (FINDING-4);
# - github.ref (não ref_name, que colide tag e branch homônimas num dispatch)
#   no mesmo ramo: main e develop no mesmo SHA não se cancelam (issue #23).
# Até o #63 isto era busca de substring, que aceitava os termos só citados:
# num literal, como argumento sobrando de format() ou num ramo que nunca é
# avaliado (`false && ... || 'x' || ...` vira ci-push-x em todo push).
# Igualdade exata custa uma coisa: mudar o grupo é mudar no mesmo commit o
# ci.yml, esta constante e GRUPO_NOVO em scripts/qa/ci_invariants_test.sh, e
# provar com scripts/qa/ci_concurrency_act.sh o que a forma nova avalia.
GRUPO_CONCORRENCIA = (
    "ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' "
    "&& github.event.pull_request.number "
    "|| format('{0}-{1}', github.ref, github.sha) }}"
)


def check_concorrencia():
    c = wf.get('concurrency')
    if not isinstance(c, dict):
        falhas.append('FINDING-7: sem bloco concurrency no nível do workflow')
        return
    grupo = str(c.get('group') or '')
    if grupo != GRUPO_CONCORRENCIA:
        falhas.append(
            'FINDING-7: concurrency.group difere da forma canônica '
            '(GRUPO_CONCORRENCIA em scripts/qa/ci_invariants.sh) — '
            f'esperado: {GRUPO_CONCORRENCIA} | atual: {grupo}')
    if c.get('cancel-in-progress') is not True:
        falhas.append('FINDING-7: concurrency sem cancel-in-progress: true')
```

Não remova o `import re`: `check_credenciais_fcm` ainda o usa.

- [ ] **Step 5: Rodar o teste e o `ci.yml` real**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: exit 0, última linha `OK — ... (issues #23, #63 e #24) conferem.`, nenhuma linha `FALHA`.

Run: `./scripts/qa/ci_invariants.sh`
Expected: `ok: 9 grupos de invariantes do CI` (o `ci.yml` real bate com a constante).

- [ ] **Step 6: Commit**

```bash
git add scripts/qa/ci_invariants.sh scripts/qa/ci_invariants_test.sh
git commit -m "fix(ci): check_concorrencia compara o grupo por igualdade exata (#24)

A busca por substring aceitava ref e SHA só citados: num literal, como
argumento sobrando de format() ou num ramo nunca avaliado, que resolve para
ci-push-x em todo push. GRUPO_CONCORRENCIA guarda o texto revisado; as
fixtures passam a cobrir esses três falsos negativos."
```

- [ ] **Step 7: Provar que a deriva entre as cópias falha (Review Focus 5)**

Com a árvore limpa (depois do commit), altere só a constante, confira que os dois scripts acusam e desfaça:

```bash
sed -i 's/github.ref, github.sha) }}"$/github.sha, github.ref) }}"/' scripts/qa/ci_invariants.sh
git diff --stat   # esperado: 1 linha mudada em scripts/qa/ci_invariants.sh; se vazio, o sed não casou — a constante não está como no passo 4
./scripts/qa/ci_invariants.sh; echo "exit=$?"                       # esperado: FALHA ... difere da forma canônica, exit=1
./scripts/qa/ci_invariants_test.sh >/dev/null 2>&1; echo "exit=$?"  # esperado: exit=1 (controle de base sujo)
git checkout -- scripts/qa/ci_invariants.sh
git status --short   # esperado: vazio
```

---

### Task 2: Documentação e o comentário do `ci.yml`

**Files:**
- Modify: `.github/workflows/ci.yml:13-19` (só comentário)
- Modify: `CLAUDE.md:109`, `AGENTS.md:151`
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (nova linha após a 274)

**Interfaces:**
- Consumes: `GRUPO_CONCORRENCIA` e a mensagem `difere da forma canônica` da Tarefa 1.
- Produces: nada que código consuma.

- [ ] **Step 1: Comentário no `ci.yml`**

Logo depois da linha `# branch de mesmo nome num dispatch.` (antes de `concurrency:`), acrescente:

```yaml
# Este texto é comparado por igualdade com GRUPO_CONCORRENCIA em
# scripts/qa/ci_invariants.sh (issue #24): mudou aqui, muda lá e em GRUPO_NOVO
# de scripts/qa/ci_invariants_test.sh no mesmo commit.
```

- [ ] **Step 2: `CLAUDE.md`**

Na linha 109, troque o trecho:

```
known gaps in the guard are issues #19, #21, #24 (#23 fixed — the push/dispatch concurrency group carries `github.ref` and the SHA, and `check_concorrencia` requires `github.ref` (not `ref_name`) on that branch and `github.event_name` in the prefix; its substring limits are recorded in the function's comment (#63);
```

por:

```
known gaps in the guard are issues #19, #21 (#23 fixed — the push/dispatch concurrency group carries `github.ref` and the SHA; #24 fixed — `check_concorrencia` compares the group for exact equality with `GRUPO_CONCORRENCIA` instead of searching substrings, so changing the group means changing `ci.yml`, that constant and `GRUPO_NOVO` in `scripts/qa/ci_invariants_test.sh` in the same commit, and `scripts/qa/ci_concurrency_act.sh` proves with `act` what that text evaluates to (#63);
```

- [ ] **Step 3: `AGENTS.md`**

Na linha 151, troque o trecho:

```
lacunas conhecidas da guarda nas issues #19, #21 e #24 (#23 corrigida — o grupo de concorrência de push/dispatch leva `github.ref` e o SHA, e o `check_concorrencia` exige `github.ref` (não `ref_name`) nesse ramo e `github.event_name` no prefixo; as limitações da busca por substring estão no comentário da função e o `scripts/qa/ci_concurrency_act_test.sh` cobre a sonda do `act` (#63);
```

por:

```
lacunas conhecidas da guarda nas issues #19 e #21 (#23 corrigida — o grupo de concorrência de push/dispatch leva `github.ref` e o SHA; #24 corrigida — o `check_concorrencia` compara o grupo por igualdade exata com `GRUPO_CONCORRENCIA` em vez de buscar substrings, então mudar o grupo é mudar no mesmo commit o `ci.yml`, essa constante e o `GRUPO_NOVO` de `scripts/qa/ci_invariants_test.sh`; o `scripts/qa/ci_concurrency_act.sh` prova com o `act` o que esse texto avalia, e o `scripts/qa/ci_concurrency_act_test.sh` cobre a sonda (#63);
```

- [ ] **Step 4: Tabela da avaliação de CI**

Em `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`, logo depois da linha `| FINDING-7 (acabamentos, issue #63) | Fechado | ...`, insira:

```markdown
| FINDING-7 (igualdade exata, issue #24) | Fechado | `check_concorrencia` compara o `concurrency.group` com `GRUPO_CONCORRENCIA` por igualdade, não por substring; os três falsos negativos da substring (ref num literal, argumento sobrando de `format()`, ramo nunca avaliado que vira `ci-push-x` em todo push) são casos positivos em `ci_invariants_test.sh` |
```

- [ ] **Step 5: Rodar tudo que o `workflow-lint` roda (menos o actionlint)**

```bash
./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh \
  && ./scripts/ci/decode_secret_file_test.sh && ./scripts/qa/ci_push_e2e_test.sh \
  && ./scripts/qa/ci_invariants_fcm_test.sh && ./scripts/qa/ci_concurrency_act_test.sh \
  && ./scripts/dev/sync_dev_ca_test.sh && ./scripts/dev/bootstrap_env_test.sh \
  && ./scripts/dev/run_acs_captura_test.sh && echo TUDO-VERDE
```

Expected: termina em `TUDO-VERDE`. O actionlint não está instalado localmente; ele roda na CI (Tarefa 3). Se `act` e Docker estiverem disponíveis, rode também `./scripts/qa/ci_concurrency_act.sh` (o grupo não mudou, então tem de seguir verde; exit 2 = faltou pré-requisito, registre e siga).

- [ ] **Step 6: Atualizar o graphify e commitar**

```bash
graphify update .
git add .github/workflows/ci.yml CLAUDE.md AGENTS.md docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci): registra a guarda de concorrência por igualdade exata (#24)"
```

Se o `graphify update .` mudar arquivos versionados em `graphify-out/`, confira com `git status` se o projeto costuma commitá-los (`git log --oneline -3 -- graphify-out`); se não costuma, não adicione.

---

### Task 3: PR, CI verde e fechamento da issue

**Files:** nenhum.

- [ ] **Step 1: Push e PR contra `develop`**

```bash
git push -u origin fix/issue-24-grupo-concorrencia-exato
gh pr create --base develop --title "ci: check_concorrencia compara o grupo por igualdade exata (#24)" --body "$(cat <<'EOF'
## O que muda
`check_concorrencia` deixa de buscar substrings no `concurrency.group` e passa a compará-lo por igualdade com `GRUPO_CONCORRENCIA` (`scripts/qa/ci_invariants.sh`). O grupo do `ci.yml` não muda.

## Por que não `wontfix`
A substring aceitava `... false && <PR> || 'x' || format(ref, sha)`, que avalia para `ci-push-x` em todo push: com `cancel-in-progress`, todo push cancelaria o anterior. Também aceitava o ref num literal e como argumento sobrando de `format()`. Os três viraram casos positivos em `scripts/qa/ci_invariants_test.sh`.

## Custo aceito
Mudar o grupo exige mudar no mesmo commit o `ci.yml`, a constante e o `GRUPO_NOVO` da fixture (comentário no `ci.yml` aponta isso). O `scripts/qa/ci_concurrency_act.sh` continua sendo a prova do que o texto avalia.

## Verificação
- `./scripts/qa/ci_invariants_test.sh` verde, incluindo os três casos da #24
- `./scripts/qa/ci_invariants.sh` verde no `ci.yml` real
- prova de deriva: alterar só a constante faz os dois scripts falharem

Resolve #24.
EOF
)"
```

- [ ] **Step 2: Acompanhar a CI**

Run: `gh pr checks --watch`
Expected: os 8 checks obrigatórios verdes (`workflow-lint` inclui o actionlint, que não rodou localmente). `android-e2e` é informativo; se falhar por motivo alheio a este diff (o diff não toca app nem stack), registre o run e não bloqueie.

- [ ] **Step 3: Depois do merge em `develop`, fechar a issue**

`Resolve #24` só fecha sozinho em merge na branch padrão (`main`). Feche à mão:

```bash
gh issue close 24 --reason completed --comment "Corrigida em $(gh pr view --json url -q .url): igualdade exata com GRUPO_CONCORRENCIA em vez de substring. A verificação de 2026-10-14 mostrou que a substring aceitava um ramo morto que resolve para ci-push-x em todo push, então o impacto não era baixo."
```
