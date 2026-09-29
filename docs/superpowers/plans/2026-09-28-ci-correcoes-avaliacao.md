# Correções do CI apontadas na avaliação de 2026-09-28 — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os achados abertos da avaliação de CI: obter o dado que falta sobre o `android-e2e` (FINDING-4), fazer o CI rodar em `develop` e cancelar runs obsoletos (FINDING-2/7), atualizar ações e fixar a imagem do runner antes de 2026-10-19 (FINDING-6), e transformar o CI em gate com branch protection (FINDING-5/3). Tudo isso com uma guarda que impede a mesma deriva de voltar.

**Architecture:** Todas as mudanças de código ficam em um único arquivo, `.github/workflows/ci.yml`, e em um script novo, `scripts/qa/ci_invariants.sh`. O script lê o workflow com PyYAML e falha, com o número do FINDING, quando uma invariante é quebrada. Ele roda num job novo, `workflow-lint`, junto com o actionlint. Cada task acrescenta ao script a sua asserção antes de mudar o workflow (primeiro vermelho, depois verde). O trabalho vai numa única branch e numa única PR para `develop`, com um push por task. O primeiro run dessa PR é o dado do FINDING-4. A branch protection é configuração do GitHub, aplicada por `gh api` depois do merge e alimentada pela lista de checks que o próprio script publica.

**Tech Stack:** GitHub Actions, `gh` CLI, actionlint 1.7.12 (imagem Docker `rhysd/actionlint:1.7.12`), bash + python3/PyYAML.

**Spec:** [docs/ci-audit/2026-09-28-avaliacao-ci-develop.md](../../ci-audit/2026-09-28-avaliacao-ci-develop.md). A tabela da Seção 5 é o backlog que este plano executa.

## Estado dos achados no início do plano (medido em 2026-09-28)

| Achado | Estado | Onde é tratado |
|---|---|---|
| FINDING-1 (docs com 6 jobs) | **Fechado** em `32ddad5` (CLAUDE.md/AGENTS.md listam os 8 jobs) | Task 1 impede a deriva de voltar |
| FINDING-2 (push em develop não dispara CI) | Aberto: `on.push.branches: [main, master]` | Task 1 |
| FINDING-7 (sem `concurrency`) | Aberto | Task 1 |
| FINDING-4 (`74d89c0` nunca rodou no CI) | Aberto: nenhum run desde `36179475405`; `origin/develop` em `32ddad5` | Task 2 |
| FINDING-6 (ações depreciadas + `ubuntu-latest` → 26 em 2026-10-19) | Aberto: `checkout@v4`, `setup-java@v4`, `cache@v4`, `upload-artifact@v4`; 9 × `ubuntu-latest` | Tasks 3, 4 e 5 |
| FINDING-5 (sem branch protection) | Aberto: `GET .../branches/{develop,main}/protection` → 404 | Task 6 |
| FINDING-3 (CI vermelho como norma) | Prática de time; depende do FINDING-5 | Task 6 (CONTRIBUTING.md) |

Versões mais novas publicadas, conferidas com `gh api repos/<ação>/releases/latest` em 2026-09-28 (todas com `runs.using: node24`): `actions/checkout` v7.0.1, `actions/setup-java` v6.0.1, `actions/cache` v6.1.0, `actions/upload-artifact` v7.0.1. `subosito/flutter-action@v2` (composite), `dart-lang/setup-dart@v1` e `reactivecircus/android-emulator-runner@v2` já estão em node24 e não mudam.

## Global Constraints

- Comentários de workflow e de script, mensagens de commit e documentação em **português**, no tom dos comentários que já existem em `ci.yml` (explicar o *porquê* medido, não o óbvio).
- Branch de trabalho: `ci/correcoes-avaliacao-2026-09-28`, criada a partir de `develop`. Uma PR para `develop`. Merge com `gh pr merge --merge`, como nas PRs anteriores.
- Não alterar o corpo de nenhum job existente além do pedido em cada task (em especial `android-e2e`: o objetivo da Task 2 é medir **o que `74d89c0` deixou**, não uma versão nova).
- actionlint fixado em `rhysd/actionlint:1.7.12`. Deve sair limpo em toda task.
- Imagem do runner: `ubuntu-24.04` em todos os jobs (Task 4). Versões mínimas das ações: `checkout@v7`, `setup-java@v6`, `cache@v6`, `upload-artifact@v7` (Task 3).
- Checks obrigatórios: todos os jobs **exceto `android-e2e`**, amarrados ao app GitHub Actions (`app_id` 15368, conferido na Task 6).
- `enforce_admins: false`: o dono do repositório continua podendo fazer push direto em `develop`, e demais colaboradores passam a precisar de PR.
- Nunca esperar CI com `sleep` em loop: usar `gh run watch <id> --exit-status` (bloqueia até o fim do run).
- Mensagens de commit terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Nada de segredo em log, script ou doc. O único segredo do workflow continua sendo `secrets.GOOGLE_MAPS_API_KEY`.

## Review Focus

1. **Push em `main`/`develop` cancelado por outro push.** Com `cancel-in-progress: true`, um grupo de concorrência por branch faria dois merges seguidos apagarem o resultado do primeiro, recriando o FINDING-4. Esperado: todo commit de `main`/`develop` guarda o próprio run. Coberto por `check_concorrencia` (Task 1), que exige `github.sha` e `github.event_name` no `group`.
2. **Check obrigatório que nunca reporta.** Se um job for renomeado, ganhar `name:` diferente do id ou `if:`, ou se o workflow ganhar `paths-ignore`, a proteção fica esperando um check que não vem e a PR trava sem erro. Esperado: a quebra aparece no `workflow-lint` da própria PR. Coberto por `check_sem_filtro_de_paths` (Task 1) e `check_checks_obrigatorios` (Task 6).
3. **`android-e2e` obrigatório por engano.** Ele travaria toda PR num job sabidamente instável. Esperado: fica fora da lista. Coberto por `check_checks_obrigatorios` (Task 6).
4. **Um job novo com `ubuntu-latest` ou ação antiga.** A deriva de imagem ou de Node voltaria em silêncio. Esperado: `workflow-lint` vermelho. Coberto por `check_runner` (Task 4) e `check_versoes_de_acoes` (Task 3).
5. **Snapshot de AVD de uma imagem reaproveitado em outra.** No ensaio do Ubuntu 26.04, o cache `avd-36-x86_64-pixel_7` criado no 24.04 pode quebrar o emulador e se passar por incompatibilidade da imagem nova. Esperado: o ensaio usa uma chave própria. Coberto pelo Step 2 da Task 5.

---

### Task 1: Guarda do workflow, gatilho em `develop` e concorrência (FINDING-2, FINDING-7, e FINDING-1 sem regressão)

**Files:**
- Create: `scripts/qa/ci_invariants.sh`
- Modify: `.github/workflows/ci.yml:1-8` (gatilhos, `concurrency`, job `workflow-lint` novo antes de `serverpod-backend`)
- Modify: `CLAUDE.md:108`, `AGENTS.md:147` (8 → 9 jobs, gatilhos)

**Interfaces:**
- Produces: `./scripts/qa/ci_invariants.sh` (sai 0/1; imprime `FALHA: ...` no stderr). Dentro do python: lista `falhas`, dicionários `wf`/`gatilhos`/`jobs`, conjunto `JOBS_DOCUMENTADOS`, lista `CHECKS` (cada check é uma função sem argumento que acrescenta a `falhas`). Os argumentos extras do script chegam em `sys.argv[2:]`. As Tasks 3, 4 e 6 acrescentam funções a `CHECKS`.
- Produces: job `workflow-lint` no `ci.yml`.

- [ ] **Step 1: Criar a branch**

```bash
git switch develop && git pull --ff-only
git switch -c ci/correcoes-avaliacao-2026-09-28
```

- [ ] **Step 2: Escrever a guarda (o teste que falha)**

Criar `scripts/qa/ci_invariants.sh`:

```bash
#!/usr/bin/env bash
#
# Invariantes do próprio workflow de CI (.github/workflows/ci.yml).
#
# Por que existe: a avaliação de 2026-09-28
# (docs/ci-audit/2026-09-28-avaliacao-ci-develop.md) achou derivas que ninguém
# viu acontecer — a documentação contava seis jobs com oito no arquivo, push em
# develop não disparava nada, não havia concorrência, as ações ficaram em
# versões depreciadas e a imagem do runner mudaria sozinha. Cada uma vira aqui
# uma asserção que falha com o número do achado.
#
#   ./scripts/qa/ci_invariants.sh
#
# Não precisa de rede nem da stack; só python3 com PyYAML. Roda no job
# workflow-lint do próprio CI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec python3 - "$repo_root/.github/workflows/ci.yml" "$@" <<'PY'
import sys

import yaml

caminho = sys.argv[1]
with open(caminho, encoding='utf-8') as f:
    wf = yaml.safe_load(f)

# PyYAML segue o YAML 1.1, em que a chave `on` é lida como o booleano True.
gatilhos = wf.get('on', wf.get(True)) or {}
jobs = wf.get('jobs') or {}
falhas = []

# Os jobs que CLAUDE.md e AGENTS.md enumeram. Mudou aqui, muda lá no mesmo
# commit — foi exatamente essa enumeração que envelheceu (FINDING-1).
JOBS_DOCUMENTADOS = {
    'workflow-lint',
    'serverpod-backend',
    'backend-docker-build',
    'patient-app',
    'acs-app',
    'admin-app',
    'coverage-report',
    'android-e2e',
    'admin-android-build',
}


def check_jobs():
    atuais = set(jobs)
    if atuais != JOBS_DOCUMENTADOS:
        falhas.append(
            'FINDING-1: jobs do workflow divergem da lista documentada — '
            f'a mais: {sorted(atuais - JOBS_DOCUMENTADOS)}, '
            f'faltando: {sorted(JOBS_DOCUMENTADOS - atuais)}. '
            'Atualize CLAUDE.md, AGENTS.md e JOBS_DOCUMENTADOS juntos.'
        )


def check_gatilhos():
    push = (gatilhos.get('push') or {}).get('branches') or []
    if 'develop' not in push:
        falhas.append(f'FINDING-2: push não dispara o CI em develop (branches: {push})')
    if 'workflow_dispatch' not in gatilhos:
        falhas.append('FINDING-2: sem workflow_dispatch, não há como disparar o CI à mão')
    if 'pull_request' not in gatilhos:
        falhas.append('pull_request deixou de disparar o CI')


def check_sem_filtro_de_paths():
    # Um check obrigatório que não roda nunca reporta, e a PR fica esperando
    # para sempre. Filtro de paths faria isso com toda PR só de documentação.
    for evento in ('push', 'pull_request'):
        cfg = gatilhos.get(evento) or {}
        for chave in ('paths', 'paths-ignore'):
            if chave in cfg:
                falhas.append(f'{evento}.{chave} faria checks obrigatórios nunca reportarem')


def check_concorrencia():
    c = wf.get('concurrency')
    if not isinstance(c, dict):
        falhas.append('FINDING-7: sem bloco concurrency no nível do workflow')
        return
    grupo = str(c.get('group', ''))
    # Sem o SHA, dois pushes seguidos em develop cairiam no mesmo grupo e o
    # segundo apagaria o resultado do primeiro — o FINDING-4 de novo.
    for termo in ('github.event_name', 'github.event.pull_request.number', 'github.sha'):
        if termo not in grupo:
            falhas.append(f'FINDING-7: concurrency.group sem {termo}: {grupo}')
    if c.get('cancel-in-progress') is not True:
        falhas.append('FINDING-7: concurrency sem cancel-in-progress: true')


CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia]

for check in CHECKS:
    check()

if falhas:
    for falha in falhas:
        print(f'FALHA: {falha}', file=sys.stderr)
    sys.exit(1)
print(f'ok: {len(CHECKS)} grupos de invariantes do CI')
PY
```

```bash
chmod +x scripts/qa/ci_invariants.sh
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `./scripts/qa/ci_invariants.sh; echo rc=$?`
Expected: `rc=1` e exatamente estas quatro linhas (a ordem importa: prova que cada check enxerga o defeito que nomeia):
```
FALHA: FINDING-1: jobs do workflow divergem da lista documentada — a mais: [], faltando: ['workflow-lint']. Atualize CLAUDE.md, AGENTS.md e JOBS_DOCUMENTADOS juntos.
FALHA: FINDING-2: push não dispara o CI em develop (branches: ['main', 'master'])
FALHA: FINDING-2: sem workflow_dispatch, não há como disparar o CI à mão
FALHA: FINDING-7: sem bloco concurrency no nível do workflow
```
Se aparecer `ModuleNotFoundError: No module named 'yaml'`, instale `python3-pyyaml` (Fedora) ou `python3-yaml` (Ubuntu) e rode de novo.

- [ ] **Step 4: Gatilhos e concorrência no `ci.yml`**

Substituir as linhas 1-8 (`name: CI` até `jobs:`) por:

```yaml
name: CI

on:
  push:
    # develop entra aqui porque, sem PR develop → main aberta, commit nenhum
    # de develop rodava CI — foi assim que 74d89c0 ficou sem um run sequer
    # (FINDING-2/FINDING-4 da avaliação de 2026-09-28).
    branches: [main, master, develop]
  pull_request:
  # Para gerar o dado sem precisar abrir PR: `gh workflow run CI --ref <branch>`.
  workflow_dispatch:

# Um run vivo por PR: push novo na mesma PR cancela o anterior, que já não
# descreve a ponta dela — o android-e2e sozinho chega a 60 min (FINDING-7).
# Push e dispatch são agrupados pelo SHA, então nenhum commit de main/develop
# perde o próprio resultado para o commit seguinte.
concurrency:
  group: ci-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.sha }}
  cancel-in-progress: true

jobs:
  # Guarda do próprio workflow: actionlint e as invariantes que a avaliação de
  # 2026-09-28 mostrou derivarem sem ninguém ver (jobs × documentação,
  # gatilhos, concorrência, versões de ações, imagem do runner).
  workflow-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: actionlint
        run: docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color
      - name: Invariantes do CI
        run: |
          python3 -c 'import yaml' 2>/dev/null || { sudo apt-get update && sudo apt-get install -y python3-yaml; }
          ./scripts/qa/ci_invariants.sh
```

(`ubuntu-latest` e `checkout@v4` aqui são intencionais: as Tasks 3 e 4 trocam todos de uma vez, e a asserção delas precisa ver este job também.)

- [ ] **Step 5: Rodar a guarda e o actionlint**

Run: `./scripts/qa/ci_invariants.sh && docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color; echo rc=$?`
Expected: `ok: 4 grupos de invariantes do CI` e `rc=0`, sem nenhuma saída do actionlint.

- [ ] **Step 6: Documentação dos 9 jobs e dos gatilhos**

Em `CLAUDE.md:108`, trocar o trecho
`CI lives in [.github/workflows/ci.yml](.github/workflows/ci.yml) (8 jobs: \`serverpod-backend\`,`
por
`CI lives in [.github/workflows/ci.yml](.github/workflows/ci.yml) and runs on every PR, on pushes to \`main\`/\`develop\`, and by hand (\`gh workflow run CI --ref <branch>\`). 9 jobs: \`workflow-lint\` (actionlint + \`scripts/qa/ci_invariants.sh\`, which fails when this job list drifts from the workflow), \`serverpod-backend\`,`
e manter o resto da linha.

Em `AGENTS.md:147`, trocar
`- o CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) tem oito jobs: \`serverpod-backend\`,`
por
`- o CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) roda em toda PR, em push para \`main\`/\`develop\` e à mão (\`gh workflow run CI --ref <branch>\`), e tem nove jobs: \`workflow-lint\` (actionlint + \`scripts/qa/ci_invariants.sh\`, que falha quando esta lista diverge do workflow), \`serverpod-backend\`,`
e manter o resto da linha.

Run: `grep -c "workflow-lint" CLAUDE.md AGENTS.md && ./scripts/qa/check_documentation_links.sh; echo rc=$?`
Expected: `CLAUDE.md:1`, `AGENTS.md:1`, `rc=0`.

- [ ] **Step 7: Commit**

```bash
git add scripts/qa/ci_invariants.sh .github/workflows/ci.yml CLAUDE.md AGENTS.md
git commit -m "fix(ci): CI roda em develop, cancela runs obsoletos de PR e guarda o próprio workflow

FINDING-2 e FINDING-7 da avaliação de 2026-09-28. O job workflow-lint roda
actionlint e scripts/qa/ci_invariants.sh, que falha quando a lista de jobs
diverge da documentada (o FINDING-1 não volta).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Push e PR (este push produz o run da Task 2)**

```bash
git push -u origin ci/correcoes-avaliacao-2026-09-28
gh pr create --base develop --title "fix(ci): correções da avaliação de CI de 2026-09-28" \
  --body "Executa docs/superpowers/plans/2026-09-28-ci-correcoes-avaliacao.md. O primeiro run desta PR é o dado que faltava para o FINDING-4 (primeira execução de CI sobre 74d89c0).

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

### Task 2: Obter o dado do FINDING-4 e decidir

**Files:**
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (nova Seção 6 no final)

**Interfaces:**
- Consumes: a PR aberta na Task 1, Step 8.
- Produces: Seção `## 6. Acompanhamento das correções` na avaliação. As Tasks 3 a 6 acrescentam linhas à tabela dela.

**Não faça push de nenhuma outra task antes de este run terminar.** O `cancel-in-progress` da própria Task 1 cancelaria o run, e o dado se perderia de novo.

- [ ] **Step 1: Identificar o run e confirmar que ele cobre `74d89c0`**

```bash
run=$(gh run list --branch ci/correcoes-avaliacao-2026-09-28 --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$run"
sha=$(gh run view "$run" --json headSha --jq .headSha); echo "$sha"
git merge-base --is-ancestor 74d89c0 "$sha" && echo "cobre 74d89c0"
```
Expected: um id numérico, o SHA do commit da Task 1 e `cobre 74d89c0`.

- [ ] **Step 2: Esperar o fim (até ~60 min; rodar em background)**

Run: `gh run watch "$run" --exit-status; echo rc=$?`
Expected: termina sozinho. `rc` pode ser 1 se o `android-e2e` falhar, e isso é dado, não erro do plano.

- [ ] **Step 3: Coletar o resultado por job**

```bash
gh run view "$run" --json jobs --jq '.jobs[] | "\(.name): \(.conclusion) (\(.startedAt) -> \(.completedAt))"'
```

- [ ] **Step 4: Aplicar a regra de decisão**

- **Algum job que não seja `android-e2e` vermelho** (inclusive `workflow-lint`): **pare o plano**. É regressão ou defeito da Task 1. Investigue com `superpowers:systematic-debugging` antes de seguir.
- **`android-e2e` verde:** FINDING-4 fechado. A correção de `74d89c0` (KVM, cache, smoke) funcionou.
- **`android-e2e` vermelho ou `cancelled`:** capture a causa e abra uma issue. A depuração **fica fora deste plano**, em sessão própria. O restante segue, porque o `android-e2e` não será check obrigatório.

```bash
job=$(gh run view "$run" --json jobs --jq '.jobs[] | select(.name=="android-e2e") | .databaseId')
gh run view --log-failed --job="$job" | grep -E "tests passed|failed to install|Unable to start|Timed out|error" | tail -20
gh issue create --label bug --title "android-e2e falha no primeiro run de CI sobre 74d89c0" \
  --body "Run $run (job $job), primeiro run de CI a cobrir 74d89c0 (FINDING-4 de docs/ci-audit/2026-09-28-avaliacao-ci-develop.md). Trecho do log:

\`\`\`
<colar a saída do grep acima>
\`\`\`

Próximo passo: sessão com superpowers:systematic-debugging, ponto de entrada scripts/qa/run_android_e2e.sh."
```

- [ ] **Step 5: Registrar na avaliação**

Acrescentar ao final de `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`, com os valores medidos nos Steps 1 a 4:

```markdown
## 6. Acompanhamento das correções

Plano: `docs/superpowers/plans/2026-09-28-ci-correcoes-avaliacao.md`.

| Achado | Estado | Evidência |
|---|---|---|
| FINDING-1 | Fechado | `32ddad5` (docs) e guarda `check_jobs` em `scripts/qa/ci_invariants.sh` |
| FINDING-2 | Fechado | `push` em `develop` e `workflow_dispatch` no `ci.yml`; guarda `check_gatilhos` |
| FINDING-7 | Fechado | bloco `concurrency` por PR/SHA; guarda `check_concorrencia` |
| FINDING-4 | <Fechado — `android-e2e` verde \| Aberto — issue #N> | run <id do Step 1> sobre <sha do Step 1> (ancestral de `74d89c0` confirmado); `android-e2e`: <conclusion>, <duração> |
```

- [ ] **Step 6: Commit (sem push ainda: ele vai junto com a Task 3)**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): primeiro run de CI sobre 74d89c0 (FINDING-4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Atualizar as ações para node24 (FINDING-6, parte 1)

**Files:**
- Modify: `scripts/qa/ci_invariants.sh` (novo check)
- Modify: `.github/workflows/ci.yml` (todas as ocorrências das quatro ações)
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (linha na tabela da Seção 6)

**Interfaces:**
- Consumes: `jobs`, `falhas`, `CHECKS` de `ci_invariants.sh` (Task 1).
- Produces: `check_versoes_de_acoes` e o dicionário `MAJOR_MINIMO`.

- [ ] **Step 1: Ler as notas de quebra antes de trocar**

```bash
for r in actions/checkout@v5.0.0 actions/checkout@v6.0.0 actions/checkout@v7.0.0 actions/setup-java@v5.0.0 actions/setup-java@v6.0.0 actions/cache@v5.0.0 actions/cache@v6.0.0 actions/upload-artifact@v5.0.0 actions/upload-artifact@v6.0.0 actions/upload-artifact@v7.0.0; do
  echo "=== $r"; gh release view "${r#*@}" -R "${r%@*}" --json body --jq .body | grep -iE "breaking|remov|require|minimum|node" | head -8
done
```
Esperado, conforme a leitura feita ao escrever este plano:
- em todas, o mínimo é o runner 2.327.1 (os runners hospedados já atendem);
- `checkout@v7` bloqueia o checkout de PR de fork em `pull_request_target`/`workflow_run`, gatilhos que este workflow não usa;
- `checkout@v6` persiste as credenciais num arquivo separado;
- `cache@v6` virou ESM, sem mudança de inputs;
- `upload-artifact@v7` adiciona `archive: false`, que é opcional;
- `setup-java@v6` não muda `distribution`/`java-version`.

Se a saída mostrar quebra que toque um input usado no `ci.yml` (`with:` de cada passo), pare e ajuste o passo junto.

- [ ] **Step 2: Acrescentar o check (teste que falha)**

Em `scripts/qa/ci_invariants.sh`, logo acima de `CHECKS = [`, inserir:

```python
# Major mínimo de cada ação da GitHub (FINDING-6): abaixo disso ela roda em
# Node 20, depreciado, ou — setup-java v4 — não recebe mais atualização.
MAJOR_MINIMO = {
    'actions/checkout': 7,
    'actions/setup-java': 6,
    'actions/cache': 6,
    'actions/upload-artifact': 7,
}


def check_versoes_de_acoes():
    for nome_job, job in jobs.items():
        for passo in job.get('steps') or []:
            uses = passo.get('uses') or ''
            acao, _, versao = uses.partition('@')
            minimo = MAJOR_MINIMO.get(acao)
            if minimo is None:
                continue
            if not versao.startswith('v') or not versao[1:].split('.')[0].isdigit():
                # Fixar por SHA é legítimo, mas então esta guarda precisa
                # aprender a ler o comentário de versão — não passar calada.
                falhas.append(f'FINDING-6: {nome_job} usa {uses}; este check só entende tags vN')
                continue
            if int(versao[1:].split('.')[0]) < minimo:
                falhas.append(f'FINDING-6: {nome_job} usa {uses}; mínimo v{minimo}')
```

e trocar a linha `CHECKS = [...]` por:

```python
CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia,
          check_versoes_de_acoes]
```

Run: `./scripts/qa/ci_invariants.sh 2>&1 | grep -c "FINDING-6"; echo`
Expected: `16`, uma falha por uso antigo: 9 `checkout@v4` (8 originais + o do `workflow-lint`), 2 `setup-java@v4`, 3 `cache@v4`, 2 `upload-artifact@v4`. Confira com `grep -cE "actions/(checkout|setup-java|cache|upload-artifact)@v4" .github/workflows/ci.yml`, que também deve dar `16`. A guarda precisa ver todas, não só a primeira.

- [ ] **Step 3: Trocar as versões**

```bash
sed -i -e 's#actions/checkout@v4#actions/checkout@v7#g' \
       -e 's#actions/setup-java@v4#actions/setup-java@v6#g' \
       -e 's#actions/cache@v4#actions/cache@v6#g' \
       -e 's#actions/upload-artifact@v4#actions/upload-artifact@v7#g' .github/workflows/ci.yml
```

- [ ] **Step 4: Guarda e actionlint verdes**

Run: `./scripts/qa/ci_invariants.sh && docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color; echo rc=$?`
Expected: `ok: 5 grupos de invariantes do CI`, `rc=0`.

- [ ] **Step 5: Commit, push e esperar o run**

```bash
git add scripts/qa/ci_invariants.sh .github/workflows/ci.yml
git commit -m "fix(ci): ações em node24 — checkout@v7, setup-java@v6, cache@v6, upload-artifact@v7 (FINDING-6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
run=$(gh run list --branch ci/correcoes-avaliacao-2026-09-28 --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run" --exit-status; echo rc=$?
```
Expected: todos os jobs, exceto possivelmente `android-e2e`, com `success`. O primeiro run depois da troca de `cache@v4` → `v6` pode perder o cache e ficar mais lento, o que é esperado.

- [ ] **Step 6: Confirmar que os avisos sumiram**

Run: `gh run view "$run" | grep -cE "Node.js 20 is deprecated|setup-java v4 is deprecated"`
Expected: `0`. Se o `android-e2e` foi cancelado antes de subir artifact, os avisos dele ainda contam como vistos, porque as annotations são emitidas no início do job.

- [ ] **Step 7: Registrar e commitar**

Acrescentar à tabela da Seção 6 da avaliação:

```markdown
| FINDING-6 (ações) | Fechado | run <id do Step 5>: 0 avisos de Node 20/setup-java v4; guarda `check_versoes_de_acoes` |
```

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): FINDING-6 — ações atualizadas, avisos zerados

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Fixar a imagem do runner em `ubuntu-24.04` (FINDING-6, parte 2)

**Files:**
- Modify: `scripts/qa/ci_invariants.sh` (novo check)
- Modify: `.github/workflows/ci.yml` (todos os `runs-on`, mais o comentário acima de `jobs:`)
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`

**Interfaces:**
- Consumes: `jobs`, `falhas`, `CHECKS` (Task 1).
- Produces: constante `RUNNER = 'ubuntu-24.04'` e `check_runner`. A Task 5 muda `RUNNER` só na branch de ensaio.

- [ ] **Step 1: Acrescentar o check (teste que falha)**

Acima de `CHECKS = [`, inserir:

```python
# Imagem fixada (FINDING-6): `ubuntu-latest` migra de versão sozinho, no dia
# que a GitHub escolher (Ubuntu 26 a partir de 2026-10-19). Trocar de imagem
# tem de ser um PR, não uma surpresa.
RUNNER = 'ubuntu-24.04'


def check_runner():
    for nome_job, job in jobs.items():
        if job.get('runs-on') != RUNNER:
            falhas.append(f"FINDING-6: {nome_job} roda em {job.get('runs-on')!r}; esperado {RUNNER!r}")
```

e a lista:

```python
CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia,
          check_versoes_de_acoes, check_runner]
```

Run: `./scripts/qa/ci_invariants.sh 2>&1 | grep -c "roda em 'ubuntu-latest'"`
Expected: `9` (um por job).

- [ ] **Step 2: Fixar a imagem**

```bash
sed -i 's/runs-on: ubuntu-latest/runs-on: ubuntu-24.04/g' .github/workflows/ci.yml
```

Logo acima da linha `jobs:`, inserir:

```yaml
# Todos os jobs fixam ubuntu-24.04 em vez de ubuntu-latest: o label migrou
# para Ubuntu 26 em 2026-10-19 sem aviso no dia, e o android-e2e (KVM, udev)
# e os builds Android (NDK/CMake em cache) são os mais sensíveis à troca. A
# migração é feita de propósito, depois de um ensaio — ver a Seção 6 de
# docs/ci-audit/2026-09-28-avaliacao-ci-develop.md.
```

- [ ] **Step 3: Guarda e actionlint verdes**

Run: `./scripts/qa/ci_invariants.sh && docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color; echo rc=$?`
Expected: `ok: 6 grupos de invariantes do CI`, `rc=0`.

- [ ] **Step 4: Commit, push, esperar e conferir**

```bash
git add scripts/qa/ci_invariants.sh .github/workflows/ci.yml
git commit -m "fix(ci): fixar ubuntu-24.04 em todos os jobs antes da migração do ubuntu-latest (FINDING-6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
run=$(gh run list --branch ci/correcoes-avaliacao-2026-09-28 --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run" --exit-status; echo rc=$?
gh run view "$run" | grep -c "ubuntu-latest label will migrate"
```
Expected: jobs verdes (exceto possivelmente `android-e2e`), e `0` avisos de migração.

- [ ] **Step 5: Registrar e commitar**

```markdown
| FINDING-6 (runner) | Fechado para o prazo de 2026-10-19 | run <id do Step 4>: todos os jobs em `ubuntu-24.04`, 0 avisos de migração; guarda `check_runner`. Ensaio do 26.04: ver a linha seguinte |
```

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): runner fixado em ubuntu-24.04

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```

---

### Task 5: Ensaio em `ubuntu-26.04` (dado para a migração futura, sem mesclar)

Fixar o 24.04 tira a pressa do prazo, mas não diz se o 26.04 funciona. O ensaio gera esse dado numa PR descartável.

**Files:**
- Branch descartável `ci/ensaio-ubuntu-26.04`, criada a partir da branch da Task 4. **Nada dela é mesclado.**
- Modify (na branch principal): `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`

**Interfaces:**
- Consumes: `RUNNER` (Task 4).

- [ ] **Step 1: Criar a branch de ensaio**

```bash
git switch -c ci/ensaio-ubuntu-26.04
sed -i 's/runs-on: ubuntu-24.04/runs-on: ubuntu-26.04/g' .github/workflows/ci.yml
sed -i "s/^RUNNER = 'ubuntu-24.04'/RUNNER = 'ubuntu-26.04'/" scripts/qa/ci_invariants.sh
```

- [ ] **Step 2: Chave de AVD própria (Review Focus 5)**

```bash
sed -i 's/key: avd-36-x86_64-pixel_7$/key: avd-36-x86_64-pixel_7-ubuntu-26.04/' .github/workflows/ci.yml
grep -n "key: avd-" .github/workflows/ci.yml
```
Expected: uma linha terminando em `-ubuntu-26.04`.

- [ ] **Step 3: Guarda, commit e PR em rascunho**

```bash
./scripts/qa/ci_invariants.sh && docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color
git commit -am "ci(ensaio): todos os jobs em ubuntu-26.04 — NÃO MESCLAR

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin ci/ensaio-ubuntu-26.04
gh pr create --draft --base develop --title "[NÃO MESCLAR] ensaio do CI em ubuntu-26.04" \
  --body "Só para medir a migração de imagem (FINDING-6). Será fechada sem merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 4: Esperar e coletar**

```bash
run=$(gh run list --branch ci/ensaio-ubuntu-26.04 --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run"; gh run view "$run" --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
```
Se depois de 15 minutos os jobs continuarem `queued` sem runner, cancele (`gh run cancel "$run"`) e registre o label como indisponível.

- [ ] **Step 5: Fechar o ensaio e registrar**

```bash
gh pr close ci/ensaio-ubuntu-26.04 --delete-branch --comment "Ensaio registrado na Seção 6 de docs/ci-audit/2026-09-28-avaliacao-ci-develop.md."
git switch ci/correcoes-avaliacao-2026-09-28 && git branch -D ci/ensaio-ubuntu-26.04
```

Se algum job falhou só no 26.04, abra `gh issue create --title "Migrar o CI para ubuntu-26.04" --label enhancement`. No corpo, liste os jobs que falharam, com o trecho de `gh run view --log-failed --job=<id> | tail -30` de cada um, e o link do run.

Acrescentar à tabela da Seção 6:

```markdown
| Ensaio ubuntu-26.04 | <Todos verdes — migração pode ser um PR trivial \| Falharam: <jobs>, issue #N \| Label indisponível> | run <id do Step 4> |
```

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): ensaio do CI em ubuntu-26.04

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: CI como gate — branch protection em `main` e `develop` (FINDING-5, FINDING-3)

**Files:**
- Modify: `scripts/qa/ci_invariants.sh` (lista de checks obrigatórios + saída `--checks-obrigatorios`)
- Modify: `CONTRIBUTING.md` (seção nova "CI e merge", depois de "Validar alterações")
- Modify: `CLAUDE.md:108`, `AGENTS.md:148` (frase sobre branch protection)
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`
- Configuração: `PUT repos/hbgit/SinalACS/branches/{develop,main}/protection`

**Interfaces:**
- Consumes: `JOBS_DOCUMENTADOS`, `jobs`, `falhas`, `CHECKS` (Task 1).
- Produces: `CHECKS_OBRIGATORIOS`, `check_checks_obrigatorios` e `./scripts/qa/ci_invariants.sh --checks-obrigatorios`, que imprime um JSON `[{"context": "<job>", "app_id": 15368}, ...]` e só é emitido se todas as invariantes passarem.

- [ ] **Step 1: Confirmar o `app_id` do GitHub Actions (não confiar no número de cabeça)**

```bash
sha=$(gh run list --branch ci/correcoes-avaliacao-2026-09-28 --limit 1 --json headSha --jq '.[0].headSha')
gh api "repos/hbgit/SinalACS/commits/$sha/check-runs" --jq '[.check_runs[] | {name, app: .app.id}] | unique_by(.name)'
```
Expected: todos os checks com `app` = `15368` e `name` igual ao id do job. Se o número for outro, use-o no Step 2.

- [ ] **Step 2: Acrescentar o check e a saída (teste que falha primeiro)**

No topo do bloco python, trocar `import sys` por:

```python
import json
import sys
```

Acima de `CHECKS = [`, inserir:

```python
# Checks obrigatórios para merge em main e develop (FINDING-5). O
# android-e2e fica de fora enquanto não tiver histórico verde: torná-lo
# obrigatório hoje travaria toda PR num job sabidamente instável (FINDING-4).
# A proteção de branch é aplicada a partir desta lista (--checks-obrigatorios),
# então renomear um job quebra aqui antes de deixar PRs esperando por um check
# que não existe mais.
CHECKS_OBRIGATORIOS = sorted(JOBS_DOCUMENTADOS - {'android-e2e'})
# App GitHub Actions: amarrar o check ao app impede que outra integração
# publique um status com o mesmo nome e destrave o merge.
APP_GITHUB_ACTIONS = 15368


def check_checks_obrigatorios():
    if 'android-e2e' in CHECKS_OBRIGATORIOS:
        falhas.append('FINDING-4: android-e2e não pode ser obrigatório enquanto for instável')
    for nome in CHECKS_OBRIGATORIOS:
        job = jobs.get(nome)
        if job is None:
            falhas.append(f'FINDING-5: check obrigatório {nome} não existe no workflow')
            continue
        # O nome do check é o `name:` do job, se houver; e um job com `if:`
        # pode não rodar e nunca reportar.
        if job.get('name', nome) != nome:
            falhas.append(f"FINDING-5: {nome} tem name: {job['name']!r}; o check obrigatório não casaria")
        if 'if' in job:
            falhas.append(f'FINDING-5: {nome} tem if: no nível do job; pode nunca reportar')
```

Trocar a lista:

```python
CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia,
          check_versoes_de_acoes, check_runner, check_checks_obrigatorios]
```

E trocar o bloco final

```python
print(f'ok: {len(CHECKS)} grupos de invariantes do CI')
```

por

```python
if '--checks-obrigatorios' in sys.argv[2:]:
    print(json.dumps([{'context': c, 'app_id': APP_GITHUB_ACTIONS} for c in CHECKS_OBRIGATORIOS]))
    sys.exit(0)
print(f'ok: {len(CHECKS)} grupos de invariantes do CI')
```

- [ ] **Step 3: Controle negativo e positivo**

```bash
# negativo: um name: divergente tem de quebrar
sed -i '0,/^  serverpod-backend:$/s//  serverpod-backend:\n    name: Backend/' .github/workflows/ci.yml
./scripts/qa/ci_invariants.sh; echo rc=$?
git checkout .github/workflows/ci.yml
# positivo
./scripts/qa/ci_invariants.sh && ./scripts/qa/ci_invariants.sh --checks-obrigatorios | python3 -m json.tool
```
Expected:
- o negativo sai `rc=1` com `FALHA: FINDING-5: serverpod-backend tem name: 'Backend'...`;
- depois do `git checkout`, `ok: 7 grupos de invariantes do CI`;
- um JSON com 8 entradas (todos os 9 jobs menos `android-e2e`), cada uma com `"app_id": 15368`.

- [ ] **Step 4: Documentar a regra de merge (FINDING-3)**

Em `CONTRIBUTING.md`, antes de `## Alterações no backend`, inserir:

~~~markdown
## CI e merge

`main` e `develop` são protegidas: uma PR só entra com todos os jobs do CI
verdes, exceto `android-e2e`. O `android-e2e` é informativo até acumular
histórico verde, mas vermelho nele continua sendo defeito a investigar, não
ruído. A lista de checks obrigatórios vem de
`./scripts/qa/ci_invariants.sh --checks-obrigatorios`. Ao criar, renomear ou
remover um job, atualize `JOBS_DOCUMENTADOS` nesse script, `CLAUDE.md` e
`AGENTS.md` no mesmo commit. O job `workflow-lint` falha se não fizer isso.

Não mescle com CI vermelho. Para rodar o CI numa branch sem abrir PR:

```bash
gh workflow run CI --ref <branch>
```
~~~

Em `CLAUDE.md:108`, trocar
`Neither \`main\` nor \`develop\` has branch protection, so red CI does not block merges — see`
por
`\`main\` and \`develop\` are protected: every job except \`android-e2e\` must pass to merge (list from \`./scripts/qa/ci_invariants.sh --checks-obrigatorios\`; admins can still push directly) — history in`

Em `AGENTS.md:148`, trocar
`- nem \`main\` nem \`develop\` têm branch protection: CI vermelho não bloqueia merge — ver`
por
`- \`main\` e \`develop\` são protegidas: todo job exceto \`android-e2e\` precisa passar para mesclar (lista em \`./scripts/qa/ci_invariants.sh --checks-obrigatorios\`; ver \`CONTRIBUTING.md\`) — histórico em`

Run: `./scripts/qa/check_documentation_links.sh; grep -c "branch protection" CLAUDE.md AGENTS.md; echo rc=$?`
Expected: links ok. `CLAUDE.md:0` e `AGENTS.md:0`: a frase antiga saiu dos dois.

- [ ] **Step 5: Linha da avaliação, commit, push e run verde**

Acrescentar à Seção 6:

```markdown
| FINDING-5 | Fechado | proteção em `main` e `develop` com os checks de `ci_invariants.sh --checks-obrigatorios` (todos menos `android-e2e`), `enforce_admins: false`; PR obrigatória em `main` |
| FINDING-3 | Fechado como regra | `CONTRIBUTING.md` › CI e merge; aplicado pela proteção do FINDING-5 |
```

```bash
git add scripts/qa/ci_invariants.sh CONTRIBUTING.md CLAUDE.md AGENTS.md docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "fix(ci): lista de checks obrigatórios vem da guarda do workflow (FINDING-5, FINDING-3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
run=$(gh run list --branch ci/correcoes-avaliacao-2026-09-28 --event pull_request --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run" --exit-status; gh run view "$run" --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'
```
Expected: os 8 jobs obrigatórios com `success`.

- [ ] **Step 6: Mesclar e ver o push em `develop` rodar (FINDING-2 medido)**

```bash
gh pr merge ci/correcoes-avaliacao-2026-09-28 --merge --delete-branch
git switch develop && git pull --ff-only
run=$(gh run list --branch develop --event push --limit 1 --json databaseId,headSha --jq '.[0].databaseId'); echo "$run"
gh run watch "$run" --exit-status
```
Expected: existe um run `push` em `develop` para o merge commit (a prova de que o FINDING-2 foi fechado), com os 8 obrigatórios verdes.

- [ ] **Step 7: Aplicar a proteção — CONFIRMAR COM O USUÁRIO ANTES**

É configuração do repositório, fora do git. Mostre o payload ao usuário e só aplique depois de um "sim" explícito:

```bash
checks=$(./scripts/qa/ci_invariants.sh --checks-obrigatorios)
for b in develop main; do
  reviews=null
  [ "$b" = main ] && reviews='{"required_approving_review_count":0}'
  payload="{\"required_status_checks\":{\"strict\":false,\"checks\":$checks},\"enforce_admins\":false,\"required_pull_request_reviews\":$reviews,\"restrictions\":null}"
  echo "== $b: $payload"
done
```

Depois da confirmação:

```bash
for b in develop main; do
  reviews=null
  [ "$b" = main ] && reviews='{"required_approving_review_count":0}'
  gh api -X PUT "repos/hbgit/SinalACS/branches/$b/protection" --input - <<EOF
{"required_status_checks":{"strict":false,"checks":$checks},"enforce_admins":false,"required_pull_request_reviews":$reviews,"restrictions":null}
EOF
done
```

- [ ] **Step 8: Verificar a proteção contra a fonte**

```bash
esperado=$(./scripts/qa/ci_invariants.sh --checks-obrigatorios | python3 -c 'import json,sys; print(" ".join(sorted(c["context"] for c in json.load(sys.stdin))))')
for b in develop main; do
  atual=$(gh api "repos/hbgit/SinalACS/branches/$b/protection/required_status_checks" --jq '[.checks[].context] | sort | join(" ")')
  [ "$atual" = "$esperado" ] && echo "$b ok" || echo "$b DIVERGE: $atual"
done
gh api repos/hbgit/SinalACS/branches/main/protection --jq '.required_pull_request_reviews.required_approving_review_count'
```
Expected: `develop ok`, `main ok`, `0`.

- [ ] **Step 9: Atualizar o grafo**

Run: `graphify update .`

---

## Fora de escopo (decidido, não esquecido)

- **Depurar o `android-e2e`** se a Task 2 der vermelho: fica numa sessão própria com `superpowers:systematic-debugging`, rastreada pela issue aberta na Task 2. Tornar o `android-e2e` obrigatório é um passo posterior, depois de um histórico verde.
- **Fixar ações por SHA** (endurecimento de supply chain): não pedido pela avaliação. O `check_versoes_de_acoes` recusa SHA de propósito, para que essa mudança venha acompanhada da própria guarda.
- **Migrar para `ubuntu-26.04`:** a Task 5 produz o dado e, se for preciso, a issue. A troca em si é um PR futuro de uma linha no `RUNNER`, mais o `sed`.
- **Aprovação obrigatória de revisor em `main`:** `required_approving_review_count: 0` exige PR mas não revisão. Subir esse número é decisão de time, não achado da avaliação.
