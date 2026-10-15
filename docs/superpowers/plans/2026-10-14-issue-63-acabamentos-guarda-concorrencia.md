# Issue #63 acabamentos da guarda de concorrência — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** fechar os seis minors adiados da revisão final da #23: a guarda `check_concorrencia` passa a exigir `github.event_name` no prefixo do grupo e `github.ref` estrito (sem `ref_name`), com as limitações por substring registradas e fixadas em teste; `scripts/qa/ci_concurrency_act.sh` sai com 2 quando falta pré-requisito, guarda o log do `act` quando falha e não herda gpgsign/hooks do usuário; a mensagem final de `ci_invariants_test.sh` cita #20 e #23.

**Arquitetura:** só scripts de CI e documentação. `check_concorrencia` (Python embutido em `scripts/qa/ci_invariants.sh`) divide o grupo em três partes — prefixo (antes do último `${{`), ramo de PR (esquerda do `||`) e ramo de push/dispatch (direita) — e checa cada substring na parte certa. O `ci_concurrency_act.sh` ganha um teste hermético novo (`ci_concurrency_act_test.sh`) com `act`, `docker` e `python3` falsos no `PATH` e um git global hostil, que entra no passo "Testes dos scripts de CI" do `workflow-lint`.

**Stack:** bash, Python 3 + PyYAML, GitHub Actions, `act` 0.2.89 sobre Docker (só na verificação real), `gh`.

**Spec:** issue #63 (`gh issue view 63`). Origem: `docs/superpowers/plans/2026-10-14-issue-23-concorrencia-push-por-ref.md` (tabela de casos de borda, justificativa de `github.ref` sobre `ref_name`) e `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (FINDING-7).

## Restrições globais

- Branch a partir de `develop`: `fix/issue-63-acabamentos-concorrencia`. PR para `develop` com `Closes #63` no corpo.
- Sem atribuição de IA em commits ou PR (`CLAUDE.md`: nada de "Co-Authored-By" nem "Generated with Claude Code").
- Todo texto (comentários, mensagens, docs) em português, no tom dos scripts vizinhos.
- O grupo real de `.github/workflows/ci.yml:21` **não muda**: `ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || format('{0}-{1}', github.ref, github.sha) }}`. Ele já está na forma canônica; o trabalho é só na guarda.
- Toda checagem nova de `check_concorrencia` tem par positivo (defeito presente, mensagem aparece) e negativo (variação vizinha sem defeito, mensagem não aparece) em `ci_invariants_test.sh` — padrão da #20.
- Mensagens de falha continuam prefixadas por `FINDING-7:`.
- Runner fixo `ubuntu-24.04`; nenhum job novo (um job novo exige mexer em `JOBS_DOCUMENTADOS`, `CLAUDE.md`, `AGENTS.md` e na proteção de branch). O teste novo entra num passo existente.
- `ci_concurrency_act_test.sh` não pode precisar de rede, Docker, `act` real nem de PyYAML ausente/presente na máquina: tudo que ele exercita vem de stubs.

## Sobre o emulador

A #63 não toca app, backend nem o passo do `android-e2e`; nenhum teste no emulador exercita a guarda de concorrência. O que prova cada item é: fixtures do `ci_invariants_test.sh` (itens 1–4, 6), o teste com stubs (item 5), o `act` real (comportamento do grupo) e o run do GitHub na PR. O emulador entra na Tarefa 5 como **regressão**: o smoke local `./scripts/qa/e2e.sh --emulator` e o job `android-e2e` da PR (que sobe um emulador real) confirmam que mexer no `ci.yml` não quebrou o caminho E2E. Não é evidência dos itens da issue, e o relatório final não deve apresentá-lo como tal.

## Review Focus

1. Grupo com `github.event_name` só dentro do ternário (`ci-${{ github.event_name == 'pull_request' && N || format(ref, sha) }}`): push e dispatch no mesmo ref+SHA viram o mesmo grupo e se cancelam — a guarda tem de acusar (Tarefa 1, fixture `evento_so_no_ternario`).
2. Grupo com `github.ref_name` no ramo de push: tag `x` e branch `x` colidem num dispatch — a guarda tem de acusar, e a mensagem tem de dizer por quê (Tarefa 1, fixture `grupo_ref_name`, que vira positiva).
3. `github.ref_type` ou `github.ref_name` não podem satisfazer a exigência de `github.ref` por prefixo de texto (Tarefa 1, fixture `grupo_ref_type`).
4. Máquina do desenvolvedor com `commit.gpgsign=true` e `core.hooksPath` apontando para hooks que falham: o `ci_concurrency_act.sh` tem de criar a sonda mesmo assim, e se o commit falhar por outro motivo tem de sair com 2, não seguir rodando o `act` num repositório sem commit (Tarefa 3, caso "git hostil" e caso "commit impossível").
5. `act` que roda mas não imprime `GRUPO=`: o script tem de sair com 1 **e** deixar o log no disco com o caminho impresso — hoje o log some no `trap` (Tarefa 3, caso "act sem saída útil").

---

## Mapa de arquivos

| Arquivo | Muda | Responsabilidade |
|---|---|---|
| `scripts/qa/ci_invariants.sh` | `check_concorrencia` (linhas 129–154) | Guarda estática do grupo |
| `scripts/qa/ci_invariants_test.sh` | fixtures de concorrência (189–207), cabeçalho (3–6), mensagem final (209–215) | Pares positivo/negativo |
| `scripts/qa/ci_concurrency_act.sh` | pré-checagens, commit da sonda, log do `act` | Avaliação real do grupo com `act` |
| `scripts/qa/ci_concurrency_act_test.sh` | **novo** | Teste hermético do script acima com stubs |
| `.github/workflows/ci.yml` | passo "Testes dos scripts de CI" (linhas 44–51) | Roda o teste novo na CI |
| `CLAUDE.md`, `AGENTS.md`, `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` | uma frase/linha cada | Documentação do que a guarda exige |

---

### Tarefa 1: `check_concorrencia` exige `event_name` no prefixo e `github.ref` estrito

Cobre os itens 2 e 4 da issue.

**Files:**
- Modify: `scripts/qa/ci_invariants.sh:129-154`
- Test: `scripts/qa/ci_invariants_test.sh:189-207`

**Interfaces:**
- Consumes: `espera_falha <descrição> <fixture> <trecho>`, `espera_ok <descrição> <fixture> <trecho>`, `escreve_grupo <nome> <grupo>` e `GRUPO_NOVO` de `ci_invariants_test.sh`.
- Produces: duas mensagens novas que a Tarefa 2 e os docs citam literalmente:
  - `FINDING-7: concurrency.group sem github.event_name no prefixo (fora do ternário): <grupo>`
  - `FINDING-7: concurrency.group sem github.ref no ramo de push/dispatch (github.ref_name não basta: tag e branch homônimas colidem): <grupo>`
  A mensagem antiga `sem ref (github.ref ou github.ref_name) no ramo de push/dispatch` e `sem github.event_name:` deixam de existir.

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull --ff-only
git switch -c fix/issue-63-acabamentos-concorrencia
```

- [ ] **Step 2: Escrever as fixtures que falham**

Em `scripts/qa/ci_invariants_test.sh`, substitua o bloco inteiro de `echo '== concurrency.group de push/dispatch precisa conter o ref (issue #23) =='` até o `espera_ok 'negativo (variante com github.ref_name)' ... 'FINDING-7'` (linhas 189–207) por:

```bash
echo '== concurrency.group de push/dispatch precisa conter github.ref (issues #23 e #63) =='
espera_falha 'positivo (grupo antigo, só SHA)' \
  "$(escreve_grupo grupo_sem_ref "$GRUPO_ANTIGO")" \
  'sem github.ref no ramo de push/dispatch'
espera_falha 'positivo (ref só no lado do PR)' \
  "$(escreve_grupo grupo_ref_no_pr 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && format('"'"'{0}-{1}'"'"', github.ref, github.event.pull_request.number) || github.sha }}')" \
  'sem github.ref no ramo de push/dispatch'
espera_falha 'positivo (ref sem SHA no ramo de push)' \
  "$(escreve_grupo grupo_ref_sem_sha 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.ref }}')" \
  'sem github.sha no ramo de push/dispatch'
espera_falha 'positivo (sem número do PR à esquerda)' \
  "$(escreve_grupo grupo_sem_pr 'ci-${{ github.event_name }}-${{ format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  'sem github.event.pull_request.number no ramo de PR'
# #63: ref_name colide tag e branch homônimas num dispatch; o ci.yml já
# justifica github.ref, a guarda passa a exigi-lo.
espera_falha 'positivo (github.ref_name em vez de github.ref)' \
  "$(escreve_grupo grupo_ref_name 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref_name, github.sha) }}')" \
  'sem github.ref no ramo de push/dispatch (github.ref_name não basta'
espera_falha 'positivo (github.ref_type não é github.ref)' \
  "$(escreve_grupo grupo_ref_type 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref_type, github.sha) }}')" \
  'sem github.ref no ramo de push/dispatch'
espera_ok 'negativo (nova expressão com github.ref)' \
  "$(escreve_grupo grupo_novo "$GRUPO_NOVO")" \
  'FINDING-7'

echo '== github.event_name tem de estar no prefixo, fora do ternário (issue #63) =='
# Só no ternário, push e dispatch no mesmo ref+SHA resolvem para o mesmo
# grupo (o ramo da direita não carrega o evento) e um cancela o outro.
espera_falha 'positivo (event_name só na condição do ternário)' \
  "$(escreve_grupo evento_so_no_ternario 'ci-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  'sem github.event_name no prefixo'
espera_falha 'positivo (sem expressão nenhuma)' \
  "$(escreve_grupo grupo_literal 'ci-fixo')" \
  'sem github.event_name no prefixo'
espera_ok 'negativo (event_name no prefixo dentro de format)' \
  "$(escreve_grupo evento_em_format 'ci-${{ format('"'"'{0}'"'"', github.event_name) }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}')" \
  'FINDING-7'
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `./scripts/qa/ci_invariants_test.sh`
Expected: exit 1. Falham ao menos: os três positivos que esperam `sem github.ref no ramo de push/dispatch` (a mensagem atual é `sem ref (github.ref ou github.ref_name)...`), `github.ref_name em vez de github.ref`, `github.ref_type não é github.ref` e os dois positivos de `sem github.event_name no prefixo`. Os negativos passam.

- [ ] **Step 4: Implementar**

Em `scripts/qa/ci_invariants.sh`, troque o corpo de `check_concorrencia` (da linha `grupo = str(c.get('group', ''))` até antes de `if c.get('cancel-in-progress') is not True:`) por:

```python
    grupo = str(c.get('group', ''))
    # Forma canônica: "<prefixo com github.event_name>${{ PR && número ||
    # format(ref, sha) }}". O prefixo (tudo antes do último `${{`) separa push
    # de dispatch: o ramo da direita não carrega o evento, então sem
    # event_name no prefixo um push e um dispatch no mesmo ref+SHA se
    # cancelariam (issue #63). O SHA no ramo da direita evita que dois pushes
    # seguidos na mesma branch se cancelem (FINDING-4); o ref evita que main e
    # develop, no mesmo SHA, se cancelem (issue #23). Checar a string inteira
    # aceitaria o ref só no lado do PR, onde ele não protege nada.
    #
    # Limitações conhecidas (issue #63), aceitas porque isto é busca de
    # substring, não um avaliador de expressão:
    # - Aceita o ref citado sem entrar no grupo: argumento sobrando em
    #   `format('{0}', github.sha, github.ref)` ou `github.ref` dentro de um
    #   literal. Quem pega é scripts/qa/ci_concurrency_act.sh, que avalia a
    #   expressão com o act — mas ele precisa de Docker e não roda na CI.
    # - Rejeita formas legítimas não canônicas: ref no prefixo, `github['ref']`,
    #   ternário invertido (`!= 'pull_request' && ref-e-sha || número`). De
    #   propósito: a guarda só sabe ler a forma canônica.
    prefixo, _, expressao = grupo.rpartition('${{')
    esquerda, _, direita = expressao.rpartition('||')
    if 'github.event_name' not in prefixo:
        falhas.append(
            f'FINDING-7: concurrency.group sem github.event_name no prefixo (fora do ternário): {grupo}')
    if 'github.event.pull_request.number' not in esquerda:
        falhas.append(
            f'FINDING-7: concurrency.group sem github.event.pull_request.number no ramo de PR: {grupo}')
    if 'github.sha' not in direita:
        falhas.append(f'FINDING-7: concurrency.group sem github.sha no ramo de push/dispatch: {grupo}')
    # github.ref estrito: ref_name colide tag e branch homônimas num dispatch
    # (justificativa no comentário do ci.yml). `\b` depois de `ref` recusa
    # github.ref_name e github.ref_type, porque `_` é caractere de palavra.
    if not re.search(r'github\.ref\b', direita):
        falhas.append(
            'FINDING-7: concurrency.group sem github.ref no ramo de push/dispatch '
            f'(github.ref_name não basta: tag e branch homônimas colidem): {grupo}')
```

Atenção: `rpartition('${{')` num grupo sem `${{` devolve `('', '', grupo)` — o prefixo fica vazio e a checagem de `event_name` acusa, que é o esperado para `ci-fixo`.

- [ ] **Step 5: Rodar e ver passar, e conferir o ci.yml real**

Run: `./scripts/qa/ci_invariants_test.sh && ./scripts/qa/ci_invariants.sh`
Expected: exit 0 nos dois; nenhuma linha `FALHA`.

- [ ] **Step 6: Commit**

```bash
git add scripts/qa/ci_invariants.sh scripts/qa/ci_invariants_test.sh
git commit -m "fix(ci): guarda exige event_name no prefixo e github.ref estrito (#63)"
```

---

### Tarefa 2: limitações por substring fixadas em teste, e mensagem final do teste

Cobre os itens 1, 3 e 6. O comentário já entrou na Tarefa 1; aqui os casos que ele descreve viram fixtures, para o comentário não mentir quando alguém mudar a guarda.

**Files:**
- Modify: `scripts/qa/ci_invariants_test.sh:3-6` (cabeçalho), bloco novo depois da seção de `event_name`, `:209-215` (mensagem final)

**Interfaces:**
- Consumes: mensagens da Tarefa 1 (`sem github.ref no ramo de push/dispatch`, `sem github.sha no ramo de push/dispatch`).
- Produces: nada consumido por outras tarefas.

- [ ] **Step 1: Escrever as fixtures das limitações**

Logo depois do último `espera_ok` da seção `github.event_name tem de estar no prefixo`, acrescente:

```bash
echo '== limitações conhecidas da guarda por substring (issue #63) =='
# Formas legítimas não canônicas são RECUSADAS de propósito: a guarda só lê
# a forma canônica. Se uma destas passar a ser aceita, atualize o comentário
# de check_concorrencia no ci_invariants.sh.
espera_falha 'recusa por forma (ref no prefixo, fora do ramo de push)' \
  "$(escreve_grupo ref_no_prefixo 'ci-${{ github.event_name }}-${{ github.ref }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.sha }}')" \
  'sem github.ref no ramo de push/dispatch'
espera_falha 'recusa por forma (github['"'"'ref'"'"'] em vez de github.ref)' \
  "$(escreve_grupo ref_indexado 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github['"'"'ref'"'"'], github.sha) }}')" \
  'sem github.ref no ramo de push/dispatch'
espera_falha 'recusa por forma (ternário invertido)' \
  "$(escreve_grupo ternario_invertido 'ci-${{ github.event_name }}-${{ github.event_name != '"'"'pull_request'"'"' && format('"'"'{0}-{1}'"'"', github.ref, github.sha) || github.event.pull_request.number }}')" \
  'sem github.sha no ramo de push/dispatch'
# Falso negativo ACEITO: o ref só citado, sem entrar no grupo resolvido. Só o
# ci_concurrency_act.sh pega. Este caso existe para que, se a guarda um dia
# passar a pegá-lo, o comentário e esta fixture mudem juntos.
espera_ok 'limitação aceita (ref como argumento sobrando de format)' \
  "$(escreve_grupo ref_sobrando 'ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}'"'"', github.sha, github.ref) }}')" \
  'FINDING-7'
```

- [ ] **Step 2: Atualizar cabeçalho e mensagem final**

Cabeçalho (linhas 3–6), troque:

```bash
# Controles positivo e negativo das três checagens que a issue #20 pediu para
# scripts/qa/ci_invariants.sh: um check obrigatório que passa verde sem ter
# rodado por causa de continue-on-error, strategy.matrix ou needs: apontando
# para um job fora de CHECKS_OBRIGATORIOS.
```

por:

```bash
# Controles positivo e negativo de checagens de scripts/qa/ci_invariants.sh:
# as três da issue #20 (um check obrigatório que passa verde sem ter rodado
# por causa de continue-on-error, strategy.matrix ou needs: apontando para um
# job fora de CHECKS_OBRIGATORIOS) e as do concurrency.group das issues #23 e
# #63 (ref e SHA no ramo de push/dispatch, número do PR no outro, evento no
# prefixo, e as limitações conhecidas da guarda por substring).
```

Mensagem final: troque a linha

```bash
  echo 'OK — as checagens de check obrigatório "verde sem rodar" (issue #20) conferem.'
```

por

```bash
  echo 'OK — as checagens de "verde sem rodar" (issue #20) e do grupo de concorrência (issues #23 e #63) conferem.'
```

Leia as linhas logo abaixo (ramo `else`) e, se a mensagem de falha também citar só a #20, aplique a mesma troca de texto nela.

- [ ] **Step 3: Rodar**

Run: `./scripts/qa/ci_invariants_test.sh; echo "exit=$?"`
Expected: `exit=0`, as quatro linhas novas com `ok`, última linha cita #20, #23 e #63. Se `recusa por forma (ternário invertido)` não acusar `sem github.sha`, pare: confira à mão com `python3` onde o `rpartition('||')` cortou antes de mexer no esperado.

- [ ] **Step 4: Commit**

```bash
git add scripts/qa/ci_invariants_test.sh
git commit -m "test(ci): fixa as limitações da guarda de concorrência e cita #23/#63 (#63)"
```

---

### Tarefa 3: `ci_concurrency_act.sh` — exit 2, log preservado, sonda imune ao git do usuário

Cobre o item 5.

**Files:**
- Create: `scripts/qa/ci_concurrency_act_test.sh`
- Modify: `scripts/qa/ci_concurrency_act.sh:18-77,107-113`

**Interfaces:**
- Consumes: nada das tarefas anteriores (o grupo é lido do `ci.yml` real, que não muda).
- Produces: contrato de saída do `ci_concurrency_act.sh` que a Tarefa 5 usa:
  - exit 0: todas as asserções conferem;
  - exit 1: alguma asserção falhou ou o `act` não imprimiu `GRUPO=`; stderr tem `logs do act mantidos em <dir>` e `<dir>` tem um `.log` por chamada do `act` (7);
  - exit 2: falta `act`, `docker`, `git`, `python3`, PyYAML, Docker acessível, a imagem `catthehacker/ubuntu:act-24.04`, ou o commit da sonda falhou.

- [ ] **Step 1: Escrever o teste com stubs**

Crie `scripts/qa/ci_concurrency_act_test.sh` e `chmod +x`:

```bash
#!/usr/bin/env bash
#
# Teste hermético de scripts/qa/ci_concurrency_act.sh (issue #63): sem
# Docker, sem act real e sem rede. act, docker e python3 são stubs no início
# do PATH; o git é o real, mas com uma configuração global hostil (assinatura
# obrigatória com um gpg que falha e um hook pre-commit que recusa tudo),
# para provar que a sonda não herda a configuração de quem roda.
#
#   ./scripts/qa/ci_concurrency_act_test.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
alvo="$repo_root/scripts/qa/ci_concurrency_act.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

falhas=0
ok()    { echo "  ok    — $1"; }
falha() { echo "  FALHA — $1" >&2; falhas=$((falhas + 1)); }

python_real="$(command -v python3)"
stubs="$tmp_dir/bin"
mkdir -p "$stubs" "$tmp_dir/hooks"

# act falso: devolve um grupo coerente com o evento e o payload, imitando a
# expressão real; ACT_STUB_MODO=mudo não imprime GRUPO= (act quebrado).
cat > "$stubs/act" <<'SH'
#!/usr/bin/env bash
evento="$1"; payload=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --eventpath ]]; then payload="$2"; fi
  shift
done
echo "[act-stub] evento=$evento payload=$payload"
if [[ "${ACT_STUB_MODO:-}" == mudo ]]; then exit 0; fi
num="$(sed -n 's/.*"number":\([0-9]*\).*/\1/p' "$payload")"
ref="$(sed -n 's/.*"ref":"\([^"]*\)".*/\1/p' "$payload")"
if [[ -n "$num" ]]; then
  echo "[sonda/sonda]   | GRUPO=ci-$evento-$num"
else
  echo "[sonda/sonda]   | GRUPO=ci-$evento-$ref-abc123"
fi
SH

# docker falso: `info` responde; `image inspect` falha com DOCKER_STUB_SEM_IMAGEM=1.
cat > "$stubs/docker" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == image && "${DOCKER_STUB_SEM_IMAGEM:-0}" == 1 ]]; then exit 1; fi
exit 0
SH

# python3 falso: com PY_STUB_SEM_YAML=1 qualquer `import yaml` falha.
cat > "$stubs/python3" <<SH
#!/usr/bin/env bash
if [[ "\${PY_STUB_SEM_YAML:-0}" == 1 ]]; then
  echo "ModuleNotFoundError: No module named 'yaml'" >&2; exit 1
fi
exec "$python_real" "\$@"
SH

printf '#!/bin/sh\necho "hook do usuário recusou" >&2\nexit 1\n' > "$tmp_dir/hooks/pre-commit"
chmod +x "$stubs"/* "$tmp_dir/hooks/pre-commit"

cat > "$tmp_dir/gitconfig-hostil" <<CFG
[commit]
	gpgsign = true
[gpg]
	program = false
[core]
	hooksPath = $tmp_dir/hooks
CFG

# roda [VAR=valor ...] → preenche $saida (stdout+stderr) e $codigo.
roda() {
  saida="$(env PATH="$stubs:$PATH" GIT_CONFIG_GLOBAL="$tmp_dir/gitconfig-hostil" \
    GIT_CONFIG_NOSYSTEM=1 "$@" "$alvo" 2>&1)"
  codigo=$?
}

echo '== caminho feliz com git hostil: a sonda ignora gpgsign e hooks do usuário =='
roda
if [[ "$codigo" == 0 ]] && grep -qF 'OK —' <<<"$saida"; then
  ok 'exit 0 e as cinco asserções conferem'
else
  falha "esperava exit 0 — exit=$codigo, saída: $saida"
fi
if grep -qE 'hook do usuário recusou|gpg failed' <<<"$saida"; then
  falha "a sonda herdou a configuração do usuário — saída: $saida"
else
  ok 'nenhum hook nem gpg do usuário rodou'
fi

echo '== sem PyYAML: falta de pré-requisito é exit 2 =='
roda PY_STUB_SEM_YAML=1
if [[ "$codigo" == 2 ]] && grep -qF 'PyYAML' <<<"$saida"; then
  ok 'exit 2 e a mensagem cita PyYAML'
else
  falha "esperava exit 2 citando PyYAML — exit=$codigo, saída: $saida"
fi

echo '== sem a imagem do runner: exit 2, com o comando para baixá-la =='
roda DOCKER_STUB_SEM_IMAGEM=1
if [[ "$codigo" == 2 ]] && grep -qF 'docker pull catthehacker/ubuntu:act-24.04' <<<"$saida"; then
  ok 'exit 2 e a mensagem diz como baixar a imagem'
else
  falha "esperava exit 2 com 'docker pull' — exit=$codigo, saída: $saida"
fi

echo '== commit da sonda impossível: exit 2, sem seguir para o act =='
# Sem user.name/email resolvível e com a identidade bloqueada, o commit falha
# por um motivo que a sonda não neutraliza; o script tem de parar.
roda GIT_AUTHOR_DATE='data inválida'
if [[ "$codigo" == 2 ]] && grep -qF 'commit da sonda' <<<"$saida" && ! grep -qF '[act-stub]' <<<"$saida"; then
  ok 'exit 2 e o act não foi chamado'
else
  falha "esperava exit 2 antes do act — exit=$codigo, saída: $saida"
fi

echo '== act sem saída útil: exit 1 e o log fica no disco =='
roda ACT_STUB_MODO=mudo
dir_logs="$(sed -n 's/.*logs do act mantidos em \(.*\)$/\1/p' <<<"$saida" | tail -1)"
if [[ "$codigo" == 1 && -n "$dir_logs" && -d "$dir_logs" ]]; then
  n="$(find "$dir_logs" -name '*.log' | wc -l)"
  if [[ "$n" == 7 ]] && grep -qF '[act-stub]' "$dir_logs"/*.log; then
    ok 'exit 1, 7 logs preservados com a saída do act'
  else
    falha "esperava 7 logs com a saída do act em $dir_logs, achei $n"
  fi
  rm -rf "$(dirname "$dir_logs")"
else
  falha "esperava exit 1 e um diretório de logs — exit=$codigo, saída: $saida"
fi

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — ci_concurrency_act.sh sai com o código certo, guarda o log e ignora o git do usuário (issue #63).'
else
  echo "FALHOU — $falhas caso(s)." >&2
fi
[[ "$falhas" -eq 0 ]]
```

Nota sobre o caso "commit impossível": `GIT_AUTHOR_DATE='data inválida'` faz **só** o `git commit` falhar (`fatal: invalid date format`, exit 128), independentemente de gpg e hooks; `init` e `add` passam. Conferido em 2026-10-14 no git local.

- [ ] **Step 2: Rodar e ver falhar**

Run: `./scripts/qa/ci_concurrency_act_test.sh; echo "exit=$?"`
Expected: `exit=1`. Hoje: o caminho feliz falha (o hook hostil recusa o commit; o script segue sem commit e o `act` stub ainda roda, mas o `git branch develop`/`switch` falha e os grupos de main/develop saem iguais) **ou** acusa o hook na saída; PyYAML sai com 1, não 2; sem imagem o script nem checa e segue; o commit impossível não para o script; o caso mudo não imprime `logs do act mantidos`.

- [ ] **Step 3: Implementar no `ci_concurrency_act.sh`**

3a. Cabeçalho: troque a linha `# Precisa de act, docker, git e python3 com PyYAML. Sai com 2 se faltar algo.` por:

```bash
# Precisa de act, docker, git, python3 com PyYAML e da imagem do runner já
# baixada (o act roda com --pull=false). Sai com 2 se faltar algo, 1 se uma
# asserção não conferir — nesse caso os logs do act ficam no disco e o
# caminho é impresso. Testado sem Docker por ci_concurrency_act_test.sh.
```

3b. Troque o bloco do `trap` (linhas 24–25) por:

```bash
tmp_dir="$(mktemp -d)"
manter_logs=0
limpa() {
  if [[ "$manter_logs" == 1 ]]; then
    echo "logs do act mantidos em $tmp_dir/logs" >&2
  else
    rm -rf "$tmp_dir"
  fi
}
trap limpa EXIT
mkdir -p "$tmp_dir/logs"
```

3c. Depois de `docker info ... exit 2; }` (linha 30), acrescente:

```bash
python3 -I -c 'import yaml' 2>/dev/null || {
  echo 'faltando: PyYAML (python3-yaml no apt, ou pip install pyyaml)' >&2; exit 2; }
imagem="${IMAGEM_RUNNER#*=}"
docker image inspect "$imagem" >/dev/null 2>&1 || {
  echo "faltando a imagem do runner: docker pull $imagem" >&2; exit 2; }
```

3d. Troque as três linhas de git (52–55) por:

```bash
git -C "$sonda" init -q -b main
# A sonda não herda assinatura nem hooks de quem roda: um gpgsign=true global
# ou um core.hooksPath com pre-commit derrubaria o commit, e um post-checkout
# rodaria a cada `switch`. Config local vence a global.
git -C "$sonda" config commit.gpgsign false
git -C "$sonda" config core.hooksPath /dev/null
git -C "$sonda" add -A
git -C "$sonda" -c user.name=t -c user.email=t@t commit -q -m sonda || {
  echo 'não consegui criar o commit da sonda' >&2; exit 2; }
git -C "$sonda" branch develop
```

3e. Troque `roda_act` (linhas 71–77) por:

```bash
# roda_act <branch> <evento> <payload>  → imprime o grupo resolvido. A saída
# inteira do act vai para um log por chamada, mantido se algo falhar.
roda_act() {
  local log="$tmp_dir/logs/$1-$2-$(basename "$3" .json).log"
  git -C "$sonda" switch -q "$1"
  ( cd "$sonda" && act "$2" -W .github/workflows/sonda.yml --eventpath "$3" \
      -P "$IMAGEM_RUNNER" --pull=false ) > "$log" 2>&1
  sed -n 's/.*| GRUPO=\(.*\)$/\1/p' "$log" | tail -1
}
```

3f. No fim (linhas 107–113), troque o `else` para marcar os logs:

```bash
echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — o grupo real do ci.yml se comporta como a issue #23 pede.'
else
  manter_logs=1
  echo "FALHOU — $falhas asserção(ões) não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
```

Confira: são 7 chamadas de `roda_act` com nomes de log distintos (`main-push-ref-main`, `develop-push-ref-develop`, `main-workflow_dispatch-ref-main`, `develop-workflow_dispatch-ref-develop`, `develop-pull_request-pr7`, `main-pull_request-pr7`, `develop-pull_request-pr8`) — 7 arquivos, como o teste espera.

- [ ] **Step 4: Rodar e ver passar**

Run: `./scripts/qa/ci_concurrency_act_test.sh; echo "exit=$?"`
Expected: `exit=0`, cinco seções com `ok`.

- [ ] **Step 5: Rodar o script real (act + Docker)**

Run: `./scripts/qa/ci_concurrency_act.sh; echo "exit=$?"`
Expected: `exit=0`, cinco linhas `ok` com grupos como `ci-push-refs/heads/main-<sha>`. Guarde a saída para o corpo da PR. Se sair 2, leia a mensagem (é pré-requisito), não altere o script.

- [ ] **Step 6: Commit**

```bash
git add scripts/qa/ci_concurrency_act.sh scripts/qa/ci_concurrency_act_test.sh
git commit -m "fix(ci): sonda do act sai com 2 sem pré-requisito, guarda o log e ignora o git do usuário (#63)"
```

---

### Tarefa 4: teste novo na CI e documentação

**Files:**
- Modify: `.github/workflows/ci.yml:44-51`
- Modify: `CLAUDE.md` (bullet do CI, linha ~108), `AGENTS.md` (~148), `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (tabela, linha ~273)

**Interfaces:**
- Consumes: `scripts/qa/ci_concurrency_act_test.sh` (Tarefa 3); mensagens da Tarefa 1.
- Produces: nada.

- [ ] **Step 1: Pôr o teste no `workflow-lint`**

Em `.github/workflows/ci.yml`, no passo `Testes dos scripts de CI`, acrescente depois de `./scripts/qa/ci_invariants_fcm_test.sh`:

```yaml
          ./scripts/qa/ci_concurrency_act_test.sh
```

O passo anterior (`Invariantes do CI`) já instala `python3-yaml`; o teste usa o `python3` real do runner via stub e não precisa de Docker.

- [ ] **Step 2: Rodar as guardas e o actionlint**

Run:
```bash
./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants_test.sh \
  && docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color
```
Expected: exit 0, sem saída do actionlint.

- [ ] **Step 3: Documentação**

Antes de editar, `grep -n "#23\|ci_invariants_fcm_test\|ref_name" CLAUDE.md AGENTS.md` para achar as frases exatas.

- `CLAUDE.md`: na frase do `workflow-lint` que lista `scripts/ci/decode_secret_file_test.sh`, `scripts/qa/ci_push_e2e_test.sh` e `scripts/qa/ci_invariants_fcm_test.sh`, acrescente `scripts/qa/ci_concurrency_act_test.sh`. Na menção `#23 fixed — the push/dispatch concurrency group carries the ref and \`check_concorrencia\` requires it`, troque por `#23 fixed — the push/dispatch concurrency group carries \`github.ref\` and the SHA, and \`check_concorrencia\` requires \`github.ref\` (not \`ref_name\`) on that branch and \`github.event_name\` in the prefix; its substring limits are recorded in the function's comment (#63)`.
- `AGENTS.md`: mesma informação, em português, no item equivalente (lista de testes do `workflow-lint` e a frase da #23, se existir).
- `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`: logo abaixo da linha `| FINDING-7 (refinamento, issue #23) | ...`, acrescente:

```markdown
| FINDING-7 (acabamentos, issue #63) | Fechado | `check_concorrencia` exige `github.event_name` no prefixo e `github.ref` estrito (recusa `ref_name`); limitações por substring registradas no comentário e fixadas em `ci_invariants_test.sh`; `ci_concurrency_act.sh` sai com 2 sem pré-requisito e guarda o log do `act`, com teste hermético `ci_concurrency_act_test.sh` no `workflow-lint` |
```

Confira o número de colunas da tabela antes de colar; se forem mais de três, preencha as demais no padrão das linhas vizinhas.

- [ ] **Step 4: Links da documentação**

Run: `./scripts/qa/check_documentation_links.sh`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml CLAUDE.md AGENTS.md docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "ci: roda o teste da sonda do act no workflow-lint e documenta a guarda (#63)"
```

---

### Tarefa 5: verificação ponta a ponta (act, emulador, GitHub) e PR

**Files:** nenhum código. Evidências vão no corpo da PR.

**Interfaces:**
- Consumes: contrato de saída do `ci_concurrency_act.sh` (Tarefa 3).

- [ ] **Step 1: Suíte local de scripts de CI**

Run:
```bash
for t in ./scripts/qa/ci_invariants.sh ./scripts/qa/ci_invariants_test.sh \
         ./scripts/qa/ci_concurrency_act_test.sh ./scripts/ci/decode_secret_file_test.sh \
         ./scripts/qa/ci_push_e2e_test.sh ./scripts/qa/ci_invariants_fcm_test.sh; do
  "$t" >/dev/null 2>&1 && echo "ok   $t" || echo "FALHA $t"
done
./scripts/qa/ci_concurrency_act.sh
```
Expected: seis `ok` e o `act` real com exit 0.

- [ ] **Step 2: Regressão no emulador (não é evidência da #63)**

Carregue a skill `validacao-e2e` e siga o que ela manda para subir a stack e o emulador. Depois:

Run: `adb devices` (precisa listar um `emulator-55xx  device`) e `./scripts/qa/e2e.sh --emulator`
Expected: smoke do paciente 1/1 e do ACS 1/1. Se o emulador não subir, registre isso no corpo da PR como "regressão local no emulador não rodada: <motivo>" e siga — o `android-e2e` da PR cobre o mesmo smoke.

- [ ] **Step 3: Push e PR**

```bash
git push -u origin fix/issue-63-acabamentos-concorrencia
gh pr create --base develop --title "ci: acabamentos da guarda de concorrência (#63)" --body "$(cat <<'EOF'
Closes #63

- `check_concorrencia` exige `github.event_name` no prefixo (push e dispatch no mesmo ref+SHA não se cancelam) e `github.ref` estrito (`ref_name` colide tag e branch homônimas).
- Limitações da guarda por substring registradas no comentário e fixadas em `ci_invariants_test.sh` (formas não canônicas recusadas; ref citado sem entrar no grupo aceito — só o `act` pega).
- `ci_concurrency_act.sh`: exit 2 sem PyYAML ou sem a imagem; log do `act` mantido quando falha; a sonda não herda `commit.gpgsign`/`core.hooksPath`. Teste hermético novo `ci_concurrency_act_test.sh` no `workflow-lint`.
- Mensagem final de `ci_invariants_test.sh` cita #20, #23 e #63.

O grupo real do `ci.yml` não mudou.

## Evidências
- `ci_concurrency_act.sh` real: <colar as cinco linhas ok>
- Smoke no emulador local: <resultado ou motivo de não ter rodado>
EOF
)"
```

- [ ] **Step 4: Conferir o run da PR**

Run: `gh pr checks --watch`
Expected: 9/9 verdes, incluindo `workflow-lint` (que agora roda `ci_concurrency_act_test.sh`) e `android-e2e` (emulador real). Abra o log do `workflow-lint` e confirme a linha `OK — ci_concurrency_act.sh sai com o código certo...`. Se o `android-e2e` falhar, abra o log antes de concluir qualquer coisa: a #63 não toca esse job, então a falha provavelmente é pré-existente ou de infraestrutura — diga isso com o trecho do log, não tente consertar nesta PR.

- [ ] **Step 5: Marcar a issue**

Depois do merge, `gh issue view 63` deve mostrar fechada pelo `Closes #63`. Se algum item da checklist ficou de fora, comente na issue qual e por quê em vez de fechá-la.
