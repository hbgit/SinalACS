# Avaliação do CI adotado no branch develop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produzir uma avaliação estruturada e baseada em evidência do pipeline de CI (`.github/workflows/ci.yml`) tal como configurado e tal como vem operando contra o branch `develop`, cobrindo config estática, saúde histórica das execuções, estado atual, e governança/segurança — culminando num backlog priorizado de achados. Este plano NÃO altera o workflow nem configurações do GitHub; produz apenas o relatório de avaliação (mudanças concretas ficam para um plano de follow-up, fora deste escopo).

**Architecture:** Um único relatório (`docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`) é construído incrementalmente, uma seção por task. Cada task roda comandos reais (via `gh` CLI, já autenticado como `hbgit`, e leitura direta do workflow), captura a saída como evidência, e escreve um achado numerado (`FINDING-N`) com severidade. A Task 5 consolida tudo num backlog ordenado por severidade.

**Tech Stack:** `gh` CLI (GitHub REST/GraphQL via `gh api`, `gh run list`, `gh run view`), `git`, bash, leitura estática de `.github/workflows/ci.yml` e `AGENTS.md`. Opcionalmente `docker run rhysd/actionlint` para lint de sintaxe do workflow (não há `actionlint` instalado localmente).

**Spec:** Não há spec formal para esta avaliação — é uma auditoria ad hoc solicitada pelo usuário. Os documentos de referência usados para comparação são `AGENTS.md:138` (inventário de jobs do CI, desatualizado — ver Task 1) e o próprio `.github/workflows/ci.yml` (fonte de verdade viva).

## Global Constraints

- Não editar `.github/workflows/ci.yml`, `AGENTS.md`, nem qualquer configuração de branch protection do GitHub neste plano — é avaliação, não implementação.
- Todo o relatório é escrito em português, alinhado com a documentação do projeto (`CLAUDE.md`: "Project documentation, code comments, and UI copy are in Portuguese").
- `gh` já está autenticado nesta máquina como `hbgit` contra `hbgit/SinalACS` — todos os comandos abaixo assumem isso; não é necessário `gh auth login`.
- Os números, IDs de run e trechos de log abaixo foram capturados em 2026-09-28. Ao executar este plano, rode os comandos novamente: se os números tiverem mudado, registre o valor atual e anote a divergência como parte do achado (não copie os números antigos cegamente).
- Nenhum dado de paciente real é tocado por este plano — não se aplica a regra de nunca commitar dados de paciente, mas vale registrar se algum log de CI expuser algo sensível (ver Task 4).

---

## File Structure

- Create: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` — o relatório de avaliação, construído seção por seção ao longo das 5 tasks. É o único artefato produzido por este plano.

**Interfaces (convenção usada em todas as tasks):**
- Cada task **produz** uma seção `## N. <título>` no relatório, numerada sequencialmente, e zero ou mais achados `FINDING-N` (numeração global e crescente entre seções, não reiniciando por seção).
- Cada task **consome** o arquivo do jeito que a task anterior o deixou (append-only; nenhuma task edita uma seção escrita por outra).
- A Task 5 consome todos os `FINDING-N` das Tasks 1–4 e produz a seção final `## 5. Backlog priorizado`.

---

### Task 1: Inventário estático do workflow e comparação com a documentação

**Files:**
- Create: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`
- Read: `.github/workflows/ci.yml`, `AGENTS.md:138`

**Interfaces:**
- Consumes: nada (primeira task).
- Produces: seção `## 1. Inventário do workflow`, achados `FINDING-1` e `FINDING-2`. Tasks seguintes (2–5) referenciam a lista de 8 jobs estabelecida aqui.

- [ ] **Step 1: Criar o esqueleto do relatório**

Crie o arquivo com o cabeçalho abaixo (não inclua ainda as seções 2–5, elas vêm nas próximas tasks):

```markdown
# Avaliação do CI adotado no branch develop

Data da avaliação: 2026-09-28
Workflow avaliado: `.github/workflows/ci.yml` (branch `develop`, HEAD em `74d89c0`)
Repositório: `hbgit/SinalACS`

## 1. Inventário do workflow
```

- [ ] **Step 2: Listar os 8 jobs atuais com trigger, runner e ações-chave**

Leia `.github/workflows/ci.yml` e preencha esta tabela no relatório (dados já extraídos, confirme contra o arquivo atual antes de colar):

```markdown
| Job | Working dir | Runner | Ações principais | Observação |
|---|---|---|---|---|
| `serverpod-backend` | `backend` | ubuntu-latest | dart-lang/setup-dart@v1 (Dart 3.12.2) | Postgres efêmero na porta 9090; gera `config/passwords.yaml` inline |
| `backend-docker-build` | raiz do workspace | ubuntu-latest | `docker build` | Contexto na raiz porque o Dockerfile precisa do `pubspec.lock` compartilhado |
| `patient-app` | `apps/patient` | ubuntu-latest | subosito/flutter-action@v2 (Flutter 3.44.8) | Cria `assets/certs/` vazio antes do `flutter analyze`/`flutter test` |
| `acs-app` | `apps/acs` | ubuntu-latest | subosito/flutter-action@v2 (Flutter 3.44.8) | Mesmo motivo do `patient-app` |
| `admin-app` | `apps/admin` | ubuntu-latest | subosito/flutter-action@v2 (Flutter 3.44.8) | Sem o passo de `assets/certs/` — admin não declara esse asset |
| `coverage-report` | raiz | ubuntu-latest | dart-lang/setup-dart@v1 + subosito/flutter-action@v2 | Sobe `docker compose --profile test up -d postgres-test`; roda `scripts/qa/measure_coverage.sh`; upload de artifact `coverage-reports` |
| `android-e2e` | raiz | ubuntu-latest | actions/setup-java@v4, subosito/flutter-action@v2, reactivecircus/android-emulator-runner@v2 | `timeout-minutes: 60`; único job com emulador Android; usa `secrets.GOOGLE_MAPS_API_KEY` |
| `admin-android-build` | `apps/admin` | ubuntu-latest | actions/setup-java@v4, subosito/flutter-action@v2 | Único job que roda Gradle de verdade (`flutter build apk --debug`) |
```

- [ ] **Step 3: Comparar com o inventário documentado em `AGENTS.md`**

Rode:

```bash
grep -n "o CI do projeto valida" AGENTS.md
```

Saída esperada (linha 138, confirme o número atual):

```
138:- o CI do projeto valida seis jobs separados: `serverpod-backend`, `backend-docker-build`, `patient-app`, `acs-app`, `admin-app` e `admin-android-build` (único que executa Gradle, compilando o APK do admin).
```

Escreva no relatório:

```markdown
**FINDING-1 (severidade: baixa — documentação desatualizada).** `AGENTS.md:138` descreve o CI como "seis jobs separados", listando `serverpod-backend`, `backend-docker-build`, `patient-app`, `acs-app`, `admin-app` e `admin-android-build`. O workflow atual tem **8 jobs**: os seis citados mais `coverage-report` (adicionado em `c27ffe3`) e `android-e2e` (adicionado depois, hoje o job mais instável — ver FINDING-4). `AGENTS.md` nunca foi atualizado quando esses dois jobs entraram. Recomendação: atualizar a linha 138 para listar os 8 jobs, ou trocar a enumeração por uma referência ao arquivo (`ver .github/workflows/ci.yml`) para não repetir o mesmo tipo de drift.
```

- [ ] **Step 4: Verificar a cobertura de triggers**

Leia o bloco `on:` do workflow (linhas 3–6):

```yaml
on:
  push:
    branches: [main, master]
  pull_request:
```

Escreva no relatório:

```markdown
**FINDING-2 (severidade: informativa).** `push` só dispara CI em `main`/`master` — um push direto em `develop` (sem PR aberto) **não** roda o workflow. A cobertura de `develop` hoje depende inteiramente de haver um `pull_request` aberto tendo `develop` como head ou base. Na prática há sempre uma PR de integração `develop → main` aberta (ver Seção 2), então o branch é coberto — mas isso é um efeito colateral do fluxo de trabalho atual, não uma garantia do workflow. Se alguém commitar direto em `develop` sem PR, o CI simplesmente não roda para aquele commit.
```

- [ ] **Step 5 (opcional, validação de sintaxe): rodar actionlint via Docker**

```bash
docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest -color
```

Se a imagem não estiver disponível localmente, o `docker run` vai baixá-la (~15 MB). Se o comando reportar problemas, adicione-os ao relatório como `FINDING-2a` (mesma severidade que o achado mais grave reportado pelo actionlint); se sair limpo, registre uma linha `actionlint: sem achados (2026-09-28)` ao final da Seção 1, sem criar um FINDING novo.

- [ ] **Step 6: Commit**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): inventariar jobs do CI e comparar com AGENTS.md"
```

---

### Task 2: Levantar a saúde histórica das execuções de CI em develop

**Files:**
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (append)

**Interfaces:**
- Consumes: lista de 8 jobs da Seção 1 (Task 1) para nomear os jobs que falharam.
- Produces: seção `## 2. Saúde histórica das execuções (develop)`, achado `FINDING-3`. A Task 3 depende do run ID mais recente identificado aqui para investigar o estado atual.

- [ ] **Step 1: Listar as últimas execuções de CI cujo head branch é `develop`**

```bash
gh run list --branch develop --limit 15 --json databaseId,status,conclusion,createdAt,event,headBranch,displayTitle
```

Saída capturada em 2026-09-28 (confirme se mudou — se houver runs mais recentes, use-as e ajuste as contagens abaixo):

```
15 execuções, todas do evento "pull_request" (PR #7, "docs: add lgpd_data_audit.md ..."), de 2026-09-15T14:41:50Z a 2026-09-25T17:52:44Z:
- 1 "cancelled" (a mais recente, 36169873626 — android-e2e estourou o timeout de 60 min)
- 14 "failure"
- 0 "success"
```

- [ ] **Step 2: Para cada execução com falha, identificar qual job falhou**

Rode para cada `databaseId` da lista (substitua pelos IDs reais obtidos no Step 1):

```bash
gh run view <run-id> --json jobs -q '.jobs[] | select(.conclusion!="success") | "\(.name): \(.conclusion) (\(.startedAt) -> \(.completedAt))"'
```

Amostra já coletada (6 de 15 runs, cobrindo do início ao fim do intervalo):

```
34983384439 (2026-09-15): acs-app: failure
34990215500 (2026-09-15): acs-app: failure
35107542667 (2026-09-16): acs-app: failure
35619580425 (2026-09-21): android-e2e: failure
35867558228 (2026-09-23): android-e2e: failure
36143685083 (2026-09-25): acs-app: failure, android-e2e: failure
```

- [ ] **Step 3: Ler o log da falha mais recente de `acs-app` na amostra**

```bash
gh run view 36143685083 --json jobs -q '.jobs[] | select(.name=="acs-app") | .databaseId'
# use o ID retornado no comando abaixo
gh run view --log-failed --job=<id-retornado>
```

Trecho relevante já capturado:

```
info • The import of 'package:test_api/scaffolding.dart' is unnecessary because all of the used elements are also provided by the import of 'package:flutter_test/flutter_test.dart' • integration_test/red_alert_cycle_test.dart:63:8 • unnecessary_import
info • The imported package 'test_api' isn't a dependency of the importing package • integration_test/red_alert_cycle_test.dart:63:8 • depend_on_referenced_packages
2 issues found. (ran in 9.1s)
##[error]Process completed with exit code 1.
```

Nota: ambos os lints são de severidade `info`, mas `flutter analyze` mesmo assim saiu com exit code 1 — ou o `analysis_options.yaml` de `apps/acs` eleva esses lints a erro, ou o comportamento padrão do analyzer nesta versão do Flutter trata qualquer achado (mesmo `info`) como falha do processo. Isso já foi corrigido no commit `9f21b9d` ("fix(ci): remove import obsoleto de test_api que quebrava o flutter analyze"), que é posterior a este run — ou seja, esta causa específica já está resolvida na branch atual. Registre isso no achado como contexto, não como problema em aberto.

- [ ] **Step 4: Escrever o achado consolidado**

```markdown
## 2. Saúde histórica das execuções (develop)

**FINDING-3 (severidade: alta — CI vermelho não é exceção, é a norma).** As últimas 15 execuções do CI contra a PR de integração `develop → main` (PR #7), cobrindo 10 dias corridos (2026-09-15 a 2026-09-25), tiveram **0 sucessos**: 14 falhas e 1 cancelamento por timeout. Duas causas se alternam:
1. `acs-app` falhando em `flutter analyze` por lints `info` em `integration_test/red_alert_cycle_test.dart` (corrigido em `9f21b9d`, posterior à maioria destas execuções).
2. `android-e2e` falhando ou estourando o timeout de 60 minutos (recorrente em 21, 23 e 25/09; ver FINDING-4 para o estado após a última tentativa de correção).

Conclusão: durante toda a janela observada, não houve um único run totalmente verde da PR que leva `develop` para `main`. Isso é consistente com a ausência de branch protection (FINDING-5): nada no GitHub bloqueou o trabalho de continuar avançando apesar do CI vermelho, então o sinal vermelho não gerou pressão para corrigir a causa raiz — apenas se acumulou.
```

- [ ] **Step 5: Commit**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): registrar saude historica das execucoes em develop"
```

---

### Task 3: Confirmar o estado atual (HEAD) e isolar a causa aberta em android-e2e

**Files:**
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (append)

**Interfaces:**
- Consumes: nada de tasks anteriores além do arquivo do relatório em si.
- Produces: seção `## 3. Estado atual da HEAD`, achado `FINDING-4`. A Task 5 eleva este achado a topo do backlog (é o único `crítica`).

- [ ] **Step 1: Identificar a execução de CI mais recente contra o HEAD atual**

```bash
git log -1 --format='%H %ci' HEAD
gh run list --limit 10 --json databaseId,status,conclusion,createdAt,headBranch,event,headSha
```

Capturado em 2026-09-28: HEAD é `74d89c0` (2026-09-25 19:46:48 +0000). O run mais recente e relevante é `36179475405`, evento `push` em `main`, `headSha` `543cded` (merge commit que inclui `74d89c0`).

- [ ] **Step 2: Inspecionar os jobs dessa execução**

```bash
gh run view 36179475405
```

Saída capturada:

```
JOBS
✓ coverage-report      ✓ admin-app          ✓ admin-android-build
✓ acs-app              ✓ serverpod-backend  ✓ backend-docker-build
✓ patient-app
X android-e2e in 21m58s
```

7 de 8 jobs verdes. `android-e2e` é o único vermelho — e desta vez não é timeout (terminou em 21m58s, bem dentro do limite de 60 min): é falha real de teste.

- [ ] **Step 3: Ler o detalhe da falha de `android-e2e`**

```bash
gh run view --job=108218045718 | grep -A5 -i "error\|failed\|passed"
```

Saída capturada:

```
X The process '/usr/bin/sh' failed with exit code 1
X 0 tests passed, 1 failed.
X 0 tests passed, 1 failed.
```

Duas linhas "0 tests passed, 1 failed" — uma por app (patient e acs), já que `scripts/qa/run_android_e2e.sh` roda o smoke de cada um. Compare com o estado da Task 2 (run `36143685083`, 2026-09-25T13:51): lá a mensagem era **"10 tests passed, 4 failed"** — passagem parcial. Agora, após o commit `74d89c0` ("perf(ci): android-e2e com KVM, caches e smoke de um teste por app"), o resultado é **0 passando** nos dois apps.

- [ ] **Step 4: Escrever o achado**

```markdown
## 3. Estado atual da HEAD

**FINDING-4 (severidade: crítica — regressão no único job que exercita o device de verdade).** No HEAD atual (`74d89c0`, run `36179475405`), 7 dos 8 jobs do CI estão verdes. O único vermelho é `android-e2e`, e a falha não é mais o timeout de 60 min observado na Seção 2 — o job termina em 21m58s com **"0 tests passed, 1 failed"** tanto para `apps/patient` quanto para `apps/acs`. Isso é uma regressão em relação ao estado imediatamente anterior (run `36143685083`, mesma PR, "10 tests passed, 4 failed" — passagem parcial). O commit mais recente na branch, `74d89c0`, reduziu o escopo do job para "smoke de um teste por app" com o objetivo de reduzir o tempo de execução (documentado no próprio commit e nos comentários do workflow sobre cache de AVD/Gradle) — mas o efeito colateral observado é que os dois smokes agora falham 100% das vezes, não uma fração.

`android-e2e` é o único job do repositório que sobe um emulador Android real e exercita o ciclo completo (per `AGENTS.md`/`CLAUDE.md`: MQTT com TLS, fila offline, ciclo de alerta vermelho). Com ele quebrado, o CI perdeu a única cobertura que valida esse comportamento fim-a-fim — os outros 7 jobs (`flutter analyze`/`flutter test` unitário, build de APK do admin, testes de integração do backend) não cobrem o que `android-e2e` cobre.

Recomendação: tratar isso como o item de maior prioridade do backlog (Seção 5) e abrir uma sessão dedicada com a skill `superpowers:systematic-debugging`, usando `scripts/qa/run_android_e2e.sh` como ponto de entrada e o artifact `android-e2e-metrics` (quando presente) como fonte de dados de latência.
```

- [ ] **Step 5: Commit**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): confirmar regressao atual do job android-e2e na HEAD"
```

---

### Task 4: Avaliar governança e segurança do pipeline

**Files:**
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (append)
- Read: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nada de tasks anteriores além do arquivo do relatório.
- Produces: seção `## 4. Governança e segurança`, achados `FINDING-5`, `FINDING-6`, `FINDING-7`.

- [ ] **Step 1: Verificar proteção de branch**

```bash
gh api repos/:owner/:repo/branches/develop/protection
gh api repos/:owner/:repo/branches/main/protection
```

Saída capturada em 2026-09-28 (ambos idênticos):

```json
{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"404"}
```

Escreva:

```markdown
## 4. Governança e segurança

**FINDING-5 (severidade: alta — CI não é um gate, é só um relatório).** Nem `develop` nem `main` têm branch protection configurada no GitHub (ambos retornam 404 "Branch not protected"). Isso significa que nenhum check de CI é obrigatório para merge — combinado ao FINDING-3 (15 execuções seguidas vermelhas na PR de integração), fica claro que o CI vermelho nunca impediu ninguém de continuar commitando ou, potencialmente, de fazer merge. O invariante do projeto "Red alerts must never be silently dropped" (`CLAUDE.md`) é sobre o produto, mas o mesmo princípio de "nunca falhar silenciosamente" vale para o pipeline que valida esse produto — hoje ele pode falhar silenciosamente (ninguém é bloqueado) por dias.
```

- [ ] **Step 2: Verificar ações desatualizadas e prazos de infraestrutura**

Reaproveite as annotations já coletadas nas Tasks 2 e 3 (aparecem em toda execução, independente do job):

```markdown
**FINDING-6 (severidade: média — dívida de infraestrutura com prazo concreto).** Toda execução do CI emite estas annotations, hoje ignoradas:
- `actions/checkout@v4`, `actions/cache@v4`, `actions/setup-java@v4`, `actions/upload-artifact@v4` — todas ainda no Node.js 20, forçadas a rodar em Node 24 pelo runner (aviso de depreciação da GitHub, não bloqueante ainda).
- `setup-java v4` está deprecated; o vendor recomenda migrar para `setup-java@v5`.
- `ubuntu-latest` migra para Ubuntu 26 a partir de **2026-10-19** — a **três semanas** da data desta avaliação (2026-09-28). Como nenhum job fixa a versão da imagem (todos usam `ubuntu-latest`), essa migração vai acontecer automaticamente e sem aviso prévio no dia, podendo quebrar qualquer job que dependa implicitamente de pacotes/versões do Ubuntu 24 atual (candidatos mais prováveis: `android-e2e`, que já depende de KVM e de uma regra de udev específica, e `admin-android-build`/`acs-app`/`patient-app`, que dependem do NDK/CMake cacheado).

Recomendação: fixar as ações em versões mais novas (`checkout@v5`, `setup-java@v5`, etc.) num PR pequeno e isolado, e rodar o pipeline uma vez contra uma imagem `ubuntu-24.04` explícita antes de 2026-10-19 para confirmar que nada quebra com a migração.
```

- [ ] **Step 3: Verificar uso de segredos e ausência de controle de concorrência**

```bash
grep -n "secrets\." .github/workflows/ci.yml
grep -n "^concurrency:" .github/workflows/ci.yml
```

Saída esperada: só uma ocorrência de `secrets.` (`GOOGLE_MAPS_API_KEY` em `android-e2e`), e nenhuma ocorrência de `concurrency:`. Escreva:

```markdown
**Nota positiva (não é finding).** O único segredo real referenciado é `secrets.GOOGLE_MAPS_API_KEY`. `CI_POSTGRES_PASSWORD` é deliberadamente hardcoded e documentado no próprio workflow como não-segredo (banco efêmero, existe só dentro do runner) — não há vazamento de credencial de dev/prod no pipeline.

**FINDING-7 (severidade: baixa — desperdício de minutos de CI).** Não há bloco `concurrency:` no workflow. Cada novo push à mesma PR dispara uma execução completa sem cancelar a anterior. Isso é particularmente caro para `android-e2e`, que sozinho pode consumir até 60 minutos por tentativa (timeout configurado) — e a Seção 2 mostrou 15 tentativas em 10 dias na mesma PR. Um bloco como:

\`\`\`yaml
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
\`\`\`

cancelaria runs obsoletos assim que um novo commit chegasse na mesma PR/branch.
```

- [ ] **Step 4: Checar se algum log de CI expôs algo sensível**

```bash
gh run view --log --job=108186514572 2>&1 | grep -i "senha\|password\|secret\|token" | grep -v "CI_POSTGRES_PASSWORD\|GOOGLE_MAPS_API_KEY\|passwords.yaml"
```

(Job usado como amostra: `serverpod-backend` do run `36169873626`, por ser o que gera `config/passwords.yaml`.) Se a saída for vazia, registre uma linha `Nenhum segredo exposto em log encontrado na amostra verificada.` ao final da Seção 4. Se aparecer algo, isso vira um `FINDING` novo de severidade `crítica` (vazamento de segredo em log é sempre crítico) — pare e escale para o usuário antes de continuar, já que pode exigir rotação imediata de credencial fora do escopo deste plano.

- [ ] **Step 5: Commit**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): avaliar governanca, acoes desatualizadas e segredos do CI"
```

---

### Task 5: Consolidar o backlog priorizado e fechar a avaliação

**Files:**
- Modify: `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md` (append seção final + inserir resumo executivo no topo)

**Interfaces:**
- Consumes: `FINDING-1` a `FINDING-7` (e qualquer `FINDING-2a`/finding extra das Tasks 1 e 4) escritos pelas tasks anteriores.
- Produces: seção `## 5. Backlog priorizado` e um bloco `## Resumo executivo` inserido logo após o título do relatório. Este é o artefato final entregue ao usuário.

- [ ] **Step 1: Reler o relatório inteiro e listar todos os FINDINGs por número**

```bash
grep -n "^\*\*FINDING-" docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
```

Confirme que a sequência é contígua (FINDING-1, FINDING-2, [FINDING-2a opcional], FINDING-3 ... FINDING-7, mais qualquer achado extra da Task 4/Step 4). Se algum número estiver faltando ou duplicado, corrija antes de prosseguir — não adivinhe o que estava lá, releia a seção correspondente.

- [ ] **Step 2: Escrever a seção de backlog, ordenada por severidade**

Insira ao final do arquivo:

```markdown
## 5. Backlog priorizado

Ordenado por severidade (crítica → alta → média → baixa → informativa). Nenhum item foi implementado por este plano — é avaliação, não execução.

| # | Severidade | Achado | Ação recomendada | Como executar |
|---|---|---|---|---|
| FINDING-4 | Crítica | `android-e2e` com 0 testes passando nos dois apps na HEAD atual | Investigar a regressão introduzida por `74d89c0` | `superpowers:systematic-debugging`, entry point `scripts/qa/run_android_e2e.sh` |
| FINDING-3 | Alta | CI da PR de integração develop→main ficou vermelho em 15/15 execuções ao longo de 10 dias | Não fechar a PR até um run 100% verde; tratar vermelho como bloqueante de fato, já que não é bloqueante de configuração | Prática de time, não requer mudança de código |
| FINDING-5 | Alta | Nem `main` nem `develop` têm branch protection | Configurar required status checks (mínimo: todos os jobs exceto talvez `android-e2e` até FINDING-4 ser resolvido) | Configuração no GitHub (Settings → Branches), fora do repositório |
| FINDING-6 | Média | Ações do workflow desatualizadas; `ubuntu-latest` migra para Ubuntu 26 em 2026-10-19 (3 semanas) | PR isolado fixando `checkout@v5`, `setup-java@v5` etc.; testar contra `ubuntu-24.04` explícito antes do prazo | PR pequeno em `.github/workflows/ci.yml` |
| FINDING-1 | Baixa | `AGENTS.md:138` descreve 6 jobs, workflow tem 8 | Atualizar a linha ou trocar por referência ao arquivo | Edição de doc |
| FINDING-7 | Baixa | Sem `concurrency:`, runs obsoletos não são cancelados | Adicionar bloco `concurrency` ao workflow | PR pequeno em `.github/workflows/ci.yml` |
| FINDING-2 | Informativa | Push direto em `develop` sem PR não dispara CI | Nenhuma ação obrigatória; documentar o comportamento esperado se o time quiser confiar nisso | N/A |

Follow-up sugerido: um plano de implementação separado (via `superpowers:writing-plans` de novo) para os itens de severidade alta/média, começando por FINDING-4 já que ele está bloqueando a única cobertura de dispositivo real do projeto.
```

- [ ] **Step 3: Inserir o resumo executivo no topo do relatório**

Logo após a linha `Repositório: \`hbgit/SinalACS\`` e antes de `## 1. Inventário do workflow`, insira:

```markdown

## Resumo executivo

O pipeline tem 8 jobs (Seção 1), mas a documentação (`AGENTS.md`) só conhece 6 — sinal de que o workflow evoluiu sem o resto do repositório acompanhar. Nos últimos 10 dias, a PR que integra `develop` em `main` nunca teve uma execução 100% verde (Seção 2): a causa mudou ao longo do tempo, mas hoje (HEAD `74d89c0`) está concentrada inteiramente no job `android-e2e`, que regrediu para 0 testes passando em ambos os apps depois da última tentativa de otimização de tempo de execução (Seção 3). Isso importa mais do que pareceria à primeira vista porque nem `main` nem `develop` têm branch protection (Seção 4) — ou seja, o CI vermelho nunca foi, de fato, um gate; foi só um relatório que ninguém era obrigado a atender. Prioridade imediata: FINDING-4 (regressão do `android-e2e`); estrutural: FINDING-5 (branch protection) para que corrigir o CI passe a valer a pena.
```

- [ ] **Step 4: Commit final**

```bash
git add docs/ci-audit/2026-09-28-avaliacao-ci-develop.md
git commit -m "docs(ci-audit): consolidar backlog priorizado e resumo executivo da avaliacao de CI"
```
