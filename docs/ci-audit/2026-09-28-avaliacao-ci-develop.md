# Avaliação do CI adotado no branch develop

Data da avaliação: 2026-09-28
Workflow avaliado: `.github/workflows/ci.yml` (branch `develop`, snapshot inicial em `74d89c0` — este próprio relatório soma commits adicionais sobre esse ponto, sem alterar o workflow)
Repositório: `hbgit/SinalACS`

## Resumo executivo

O pipeline tem 8 jobs (Seção 1), mas a documentação (`AGENTS.md`) só conhece 6 — sinal de que o workflow evoluiu sem o resto do repositório acompanhar. Nos últimos 10 dias, a PR que integra `develop` em `main` nunca teve uma execução 100% verde (Seção 2): 15 execuções, 14 falhas e 1 cancelamento por timeout, 0 sucessos, alternando entre um lint em `acs-app` (já corrigido em `9f21b9d`) e o job `android-e2e`, que segue instável. A equipe já commitou uma tentativa de correção para o `android-e2e` (`74d89c0`: KVM, cache, smoke de um teste por app) — mas a PR de integração que cobria esse trecho de `develop` já havia sido mesclada 22 minutos *antes* desse commit existir, e sem uma nova PR `develop → main` aberta o workflow não dispara para `develop` (FINDING-2). Resultado: nenhuma execução de CI jamais cobriu `74d89c0` nem qualquer commit posterior a ele — incluindo os commits desta própria avaliação, que só tocam este arquivo de documentação e não alteram esse quadro (Seção 3). Isso não é uma regressão confirmada; é uma lacuna de verificação que não se fecha sozinha com o tempo. Isso importa mais do que pareceria à primeira vista porque nem `main` nem `develop` têm branch protection (Seção 4) — ou seja, o CI vermelho nunca foi, de fato, um gate; foi só um relatório que ninguém era obrigado a atender. Prioridade imediata: gerar o dado que falta para o FINDING-4 (abrir a PR `develop → main` ou disparar o workflow manualmente contra `develop`, antes de qualquer sessão de debugging); estrutural: FINDING-5 (branch protection), para que corrigir o CI passe a valer a pena.

## 1. Inventário do workflow

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

**FINDING-1 (severidade: baixa — documentação desatualizada).** `AGENTS.md:138` descreve o CI como "seis jobs separados", listando `serverpod-backend`, `backend-docker-build`, `patient-app`, `acs-app`, `admin-app` e `admin-android-build`. O workflow atual tem **8 jobs**: os seis citados mais `coverage-report` (adicionado em `c27ffe3`) e `android-e2e` (adicionado depois, hoje o job mais instável — ver FINDING-4). `AGENTS.md` nunca foi atualizado quando esses dois jobs entraram. Recomendação: atualizar a linha 138 para listar os 8 jobs, ou trocar a enumeração por uma referência ao arquivo (`ver .github/workflows/ci.yml`) para não repetir o mesmo tipo de drift.

**FINDING-2 (severidade: informativa).** `push` só dispara CI em `main`/`master` — um push direto em `develop` (sem PR aberto) **não** roda o workflow. A cobertura de `develop` hoje depende inteiramente de haver um `pull_request` aberto tendo `develop` como head ou base. Na prática, no momento em que esta seção foi escrita, havia sempre uma PR de integração `develop → main` aberta (ver Seção 2), então o branch estava coberto — mas isso era um efeito colateral do fluxo de trabalho então vigente, não uma garantia do workflow; essa cobertura, aliás, já deixou de existir (ver Seção 3/FINDING-4). Se alguém commitar direto em `develop` sem PR, o CI simplesmente não roda para aquele commit.

actionlint: sem achados (2026-09-28)

## 2. Saúde histórica das execuções (develop)

Comando executado em 2026-09-28 (mesma data da Seção 1, mas em nova chamada — reconfirmado, não reaproveitado):

```bash
gh run list --branch develop --limit 15 --json databaseId,status,conclusion,createdAt,event,headBranch,displayTitle
```

Resultado: 15 execuções, todas do evento `pull_request` contra a PR #7 (`develop → main`, "docs: add lgpd_data_audit.md ..."), cobrindo 2026-09-15T14:41:50Z a 2026-09-25T17:52:44Z:
- 1 `cancelled` (a mais recente, `36169873626`, criada 2026-09-25T17:52:44Z)
- 14 `failure`
- 0 `success`

Esses números **batem exatamente** com o snapshot capturado no brief em 2026-09-28 — não houve drift. Nenhum novo run apareceu contra `develop`: `74d89c0` foi enviado a `origin/develop` depois do run mais recente (`36169873626`, 17:52:44Z) e, mesmo assim, não disparou CI; `2eae254` e os commits seguintes, por sua vez, sequer chegaram a ser enviados ao remoto (`origin/develop` continua em `74d89c0` — ver Seção 3). Em ambos os casos isso é consistente com o FINDING-2 (Seção 1): sem um evento de PR novo, push para `develop` não dispara CI.

Job que falhou em cada run, para uma amostra de 7 runs cobrindo do início ao fim do intervalo (comando `gh run view <id> --json jobs -q '.jobs[] | select(.conclusion!="success") | "\(.name): \(.conclusion) (\(.startedAt) -> \(.completedAt))"'`, reexecutado e confirmado idêntico ao do brief para as 6 amostras originais; a 7ª, o run cancelado, foi acrescentada por esta execução para fechar a lacuna):

```
34983384439 (2026-09-15): acs-app: failure
34990215500 (2026-09-15): acs-app: failure
35107542667 (2026-09-16): acs-app: failure
35619580425 (2026-09-21): android-e2e: failure
35867558228 (2026-09-23): android-e2e: failure
36143685083 (2026-09-25): acs-app: failure, android-e2e: failure
36169873626 (2026-09-25, mais recente): android-e2e: cancelled (60m01s, 17:52:48Z -> 18:53:00Z — bate com o timeout de 60 min do job)
```

Log da falha de `acs-app` no run `36143685083` (`gh run view --log-failed --job=108099411186`), idêntico ao trecho capturado no brief:

```
info • The import of 'package:test_api/scaffolding.dart' is unnecessary because all of the used elements are also provided by the import of 'package:flutter_test/flutter_test.dart' • integration_test/red_alert_cycle_test.dart:63:8 • unnecessary_import
info • The imported package 'test_api' isn't a dependency of the importing package • integration_test/red_alert_cycle_test.dart:63:8 • depend_on_referenced_packages
2 issues found. (ran in 9.1s)
##[error]Process completed with exit code 1.
```

Confirmação adicional (além do que o brief já constatava): o commit `9f21b9d` (2026-09-25T17:22:56Z) remove exatamente esse import em `apps/acs/integration_test/red_alert_cycle_test.dart`, e é anterior ao run cancelado `36169873626` (criado 2026-09-25T17:52:44Z). Nesse run mais recente, `gh run view 36169873626 --json jobs` mostra **todos os outros 7 jobs com `success`, incluindo `acs-app`** — só `android-e2e` foi `cancelled` por timeout. Ou seja, a causa 1 abaixo está confirmada como corrigida na prática (não só pela leitura do diff), e a única falha que sobrevive na execução mais recente observada é o timeout do `android-e2e`.

**FINDING-3 (severidade: alta — CI vermelho não é exceção, é a norma).** As últimas 15 execuções do CI contra a PR de integração `develop → main` (PR #7), cobrindo 10 dias corridos (2026-09-15 a 2026-09-25), tiveram **0 sucessos**: 14 falhas e 1 cancelamento por timeout. Duas causas se alternam:
1. `acs-app` falhando em `flutter analyze` por lints `info` em `integration_test/red_alert_cycle_test.dart` (corrigido em `9f21b9d`; confirmado nesta reexecução que o run seguinte a esse commit, `36169873626`, já passa `acs-app` com sucesso).
2. `android-e2e` falhando ou estourando o timeout de 60 minutos (recorrente em 21, 23 e 25/09, inclusive no run mais recente observado; ver FINDING-4 para o estado após a última tentativa de correção em `74d89c0`).

Conclusão: durante toda a janela observada, não houve um único run totalmente verde da PR que leva `develop` para `main`. Isso é consistente com a ausência de branch protection (FINDING-5): nada no GitHub bloqueou o trabalho de continuar avançando apesar do CI vermelho, então o sinal vermelho não gerou pressão para corrigir a causa raiz — apenas se acumulou.

## 3. Estado atual da HEAD

Comandos executados em 2026-09-28 (nova chamada, para esta seção):

```bash
git log -1 --format='%H %ci' HEAD
gh run list --limit 10 --json databaseId,status,conclusion,createdAt,headBranch,event,headSha
```

`HEAD` local é `9ed4f92` (2026-09-28 09:47:00 -0400) — **dois commits à frente** do snapshot do brief (`74d89c0`, 2026-09-25 19:46:48 +0000): `2eae254` e `9ed4f92`, que são exatamente os commits das Tasks 1 e 2 deste próprio plano (só tocam `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`, `git show --stat` confirma). `git status --short --branch` mostra `develop...origin/develop [ahead 2]` — esses dois commits ainda não foram enviados ao remoto; `origin/develop` continua em `74d89c0`.

Nenhuma execução do CI cobre `74d89c0`, `2eae254` ou `9ed4f92`. Confirmado por busca direta na API, não só pela lista dos últimos 10/15 runs:

```bash
gh api "repos/hbgit/SinalACS/actions/runs?per_page=100" \
  --jq '.workflow_runs[] | select(.head_sha | startswith("74d89c0") or startswith("2eae254") or startswith("9ed4f92"))'
```

Retorna vazio para os três SHAs. Isso já era previsível pela FINDING-2 (Seção 1) e pelo texto da Seção 2 ("nenhum novo run apareceu contra `develop` apesar dos commits `74d89c0` e `2eae254`..."): `push` só dispara CI em `main`/`master`, e a única PR `develop → main` (#7) já foi mesclada e fechada em 2026-09-25T19:24:17Z — não há PR aberta hoje que pegue esses commits. `gh pr list --state all` confirma: as únicas PRs abertas no momento são `#12` (`docs/ui-ux-test-plan-execution → develop`) e `#11` (`feat/theme-light-dark → develop`), nenhuma delas `develop → main`.

**Correção ao brief: o run `36179475405` usado como "estado da HEAD" não testa `74d89c0`.** O brief presumiu que o run `36179475405` (`push` em `main`, `headSha` `543cded`, criado pela mesclagem da PR #7) incluía `74d89c0` por ser o run mais recente disponível. Não inclui:

```bash
git merge-base --is-ancestor 74d89c0 543cded && echo ancestor || echo "not ancestor"
# → not ancestor
git log --oneline -1 543cded^2   # segundo pai do merge commit = ponta de develop mesclada pela PR #7
# → 9f21b9d fix(ci): remove import obsoleto de test_api que quebrava o flutter analyze
```

(`543cded^1`, o primeiro pai, é `9293536` — a ponta de `main` antes da mesclagem, não usado aqui;
o commit relevante para esta comparação é o segundo pai, a ponta de `develop` que a PR #7 trouxe.)

A PR #7 foi mesclada às 19:24:17Z; o commit `74d89c0` só foi enviado a `develop` 22 minutos depois, às 19:46:48Z — ou seja, `74d89c0` (o commit "perf(ci): android-e2e com KVM, caches e smoke de um teste por app", que é a própria tentativa de correção do `android-e2e`) **fisicamente não existia ainda** quando a PR #7 foi mesclada. `36179475405` testa o código em `9f21b9d`, um commit *antes* da tentativa de correção — não depois dela. Não existe, e não existirá até uma nova PR `develop → main` ser aberta, nenhuma execução de CI que exercite `74d89c0` ou qualquer commit posterior.

Diante da impossibilidade de obter um run que cubra `74d89c0`, uso `36179475405` como run mais recente disponível mesmo sabendo que ele reflete o commit anterior — é o mesmo run que o brief usou, mas seus resultados descrevem o estado do `android-e2e` **antes** de `74d89c0`, não depois. Trato isso como o achado principal desta seção.

```bash
gh run view 36179475405
```

```
JOBS
✓ coverage-report      ✓ admin-app          ✓ admin-android-build
✓ acs-app              ✓ serverpod-backend  ✓ backend-docker-build
✓ patient-app
X android-e2e in 21m58s (ID 108218045718)
```

7 de 8 jobs verdes; `android-e2e` é o único vermelho, e termina em 21m58s — não é o timeout de 60 min visto no run anterior da Seção 2.

```bash
gh run view --job=108218045718 | grep -A5 -i "error\|failed\|passed"
```

```
X The process '/usr/bin/sh' failed with exit code 1
X 0 tests passed, 1 failed.
X 0 tests passed, 1 failed.
```

**Segunda correção ao brief: as duas linhas "0 tests passed, 1 failed" não são uma por app.** O brief presumiu uma linha para `apps/patient` e outra para `apps/acs`, já que o smoke roda um arquivo por app. Lendo o log completo do passo que falhou (`gh run view --log-failed --job=108218045718`), as duas linhas correspondem à **mesma tentativa, duas vezes, no mesmo app**:

```
19:45:40 adb: failed to install .../apps/patient/build/app/outputs/flutter-apk/app-debug.apk: cmd: Failure calling service package: Broken pipe (32)
19:45:44 ❌ loading .../apps/patient/integration_test/backend_connection_test.dart (failed): Unable to start the app on the device.
19:45:44 0 tests passed, 1 failed.
19:45:44 aviso: flutter test integration_test falhou (possível "Broken pipe" do adb install em emulador sem aceleração de hardware); tentando de novo.
19:46:12 adb: failed to install .../apps/patient/build/app/outputs/flutter-apk/app-debug.apk: cmd: Can't find service: package
19:46:14 ❌ loading .../apps/patient/integration_test/backend_connection_test.dart (failed): Unable to start the app on the device.
19:46:14 0 tests passed, 1 failed.
```

(o texto do aviso e o alvo `integration_test` — a pasta inteira, não `smoke_test.dart` — confirmam de novo que este run roda o script de `9f21b9d`, anterior ao "smoke de um teste por app" de `74d89c0`.) As duas falhas são a tentativa inicial e a única retentativa de `apps/patient` — nenhuma delas é `apps/acs`. O script (`scripts/qa/e2e.sh`, `set -euo pipefail`) roda `apps/patient` primeiro; como a retentativa também falhou por incapacidade de instalar o APK no emulador (mesma causa "Broken pipe"/"Can't find service", raiz em emulador sem aceleração de hardware — documentada nos comentários do próprio `e2e.sh`), o script abortou ali. **`apps/acs` e `apps/admin` nunca chegaram a rodar neste run.** Não sabemos, a partir dele, se o smoke do `acs` passaria ou falharia.

Comparação com a Seção 2: o run imediatamente anterior na mesma cadeia de commits, `36143685083` (`40035a6`, um commit antes de `9f21b9d`), teve "10 tests passed, 4 failed" — passagem parcial, sinal de que ao menos alguns testes chegaram a rodar em pelo menos um dos apps. Entre `40035a6` e `9f21b9d` a única mudança é a remoção do import não usado em `acs-app` (lint, não toca `e2e.sh`); ainda assim o `android-e2e` piorou de "passagem parcial" para "aborta na primeira instalação do APK, zero testes chegam a rodar". Isso é consistente com falha de infraestrutura não determinística (emulador sem KVM, mencionada nos comentários de `e2e.sh` como causa já identificada antes de `74d89c0`), não com uma regressão introduzida por código de teste.

**FINDING-4 (severidade: crítica — o único job que exercita o device de verdade está com o resultado da correção tentada ainda não verificado por CI).** Em todo commit a partir de `74d89c0` (inclusive) — incluindo os desta própria avaliação —, não existe **nenhuma** execução de CI: a PR `develop → main` que cobria esses commits já foi mesclada antes de `74d89c0` existir, e sem uma PR nova aberta o workflow não dispara para `develop` (FINDING-2). A execução mais recente disponível, `36179475405`, na verdade testa `9f21b9d` — o commit imediatamente *anterior* a `74d89c0`, a própria tentativa de correção (KVM, cache, smoke de um teste por app) que o time aplicou para resolver a instabilidade do `android-e2e` registrada na Seção 2. Nessa execução, `android-e2e` falhou em 21m58s (não por timeout): a instalação do APK do `apps/patient` no emulador falhou duas vezes seguidas ("Broken pipe (32)", depois "Can't find service: package") e o script abortou antes de sequer tentar `apps/acs` ou `apps/admin` — um retrocesso em relação ao run anterior da mesma cadeia (`36143685083`, "10 tests passed, 4 failed", passagem parcial), mas causado por flakiness de infraestrutura documentada (emulador sem aceleração de hardware), não por uma mudança de código de teste.

Ou seja: o time já escreveu e commitou (`74d89c0`) a correção mais provável para essa causa raiz — mas essa correção nunca rodou no CI, nem uma única vez. Não há como hoje afirmar se `android-e2e` está corrigido, seguindo quebrado do mesmo jeito, ou pior — o dado simplesmente não existe. Isso é mais grave do que uma regressão confirmada: é um item que a equipe acredita ter resolvido, sem qualquer verificação. Combinado com o FINDING-2 (push direto em `develop` não dispara CI) e o fato de não haver hoje PR aberta `develop → main`, essa lacuna de verificação persiste indefinidamente até que alguém abra essa PR (ou dispare o workflow manualmente) — não é algo que se resolva sozinho com o tempo.

`android-e2e` continua sendo o único job do repositório que sobe um emulador Android real e exercita o ciclo completo (per `AGENTS.md`/`CLAUDE.md`: MQTT com TLS, fila offline, ciclo de alerta vermelho). Os outros 7 jobs (`flutter analyze`/`flutter test` unitário, build de APK do admin, testes de integração do backend) não cobrem o que `android-e2e` cobre, e enquanto ele não roda de verdade contra `74d89c0`, essa cobertura fim-a-fim está, na prática, sem sinal algum — nem verde, nem vermelho, ausente.

Recomendação: antes de qualquer sessão de debugging, gerar o dado que falta — abrir a PR `develop → main` (ou disparar o workflow manualmente contra `develop`) para obter uma execução real de CI contra `74d89c0`. Só então decidir o próximo passo: se `android-e2e` passar, o KVM resolveu a causa já documentada; se falhar, aí sim abrir uma sessão dedicada com a skill `superpowers:systematic-debugging`, usando `scripts/qa/run_android_e2e.sh` como ponto de entrada. O artifact `android-e2e-metrics` não é uma fonte confiável de dados de latência enquanto o job abortar antes do fim: neste run ele nem foi gerado (`No files were found with the provided path: build/qa/latency. No artifacts will be uploaded.` — só o artifact `coverage-reports` apareceu na lista de artifacts do run).

## 4. Governança e segurança

Comandos executados em 2026-09-28 (nova chamada, para esta seção):

### 4.1 Proteção de branch

```bash
gh api repos/:owner/:repo/branches/develop/protection
gh api repos/:owner/:repo/branches/main/protection
```

Ambos retornam o mesmo 404, hoje:

```json
{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"404"}
```

Idêntico ao snapshot do brief — sem drift.

**FINDING-5 (severidade: alta — CI não é um gate, é só um relatório).** Nem `develop` nem `main` têm branch protection configurada no GitHub (ambos retornam 404 "Branch not protected"). Isso significa que nenhum check de CI é obrigatório para merge — combinado ao FINDING-3 (15 execuções seguidas vermelhas na PR de integração), fica claro que o CI vermelho nunca impediu ninguém de continuar commitando ou, potencialmente, de fazer merge. O invariante do projeto "Red alerts must never be silently dropped" (`CLAUDE.md`) é sobre o produto, mas o mesmo princípio de "nunca falhar silenciosamente" vale para o pipeline que valida esse produto — hoje ele pode falhar silenciosamente (ninguém é bloqueado) por dias.

### 4.2 Ações desatualizadas e prazos de infraestrutura

**Correção ao brief: as annotations não estavam de fato transcritas nas Seções 2/3 do arquivo.** Reli as Seções 2 e 3 antes de escrever este trecho (conforme pedido) e nenhuma delas contém o texto das annotations de depreciação — só o job inventory da Seção 1 lista as ações (`actions/setup-java@v4` etc.), sem as mensagens de aviso. Em vez de copiar o texto do brief sem verificação, refiz a captura ao vivo contra o run mais recente disponível (`36179475405`, o mesmo identificado na Seção 3 como o run que efetivamente testa `9f21b9d`, não `74d89c0` — mas as annotations de infraestrutura independem do commit testado, já que vêm do runner/GitHub, não do código):

```bash
gh run view 36179475405
```

Bloco `ANNOTATIONS` (trecho relevante, agregado por tipo de aviso — cada aviso aparece uma vez por job que o dispara):

```
! Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to run on Node.js 24: actions/checkout@v4, actions/upload-artifact@v4 (coverage-report, android-e2e)
! Node.js 20 is deprecated. [...]: actions/checkout@v4 (admin-app, acs-app, serverpod-backend, backend-docker-build, patient-app)
! Node.js 20 is deprecated. [...]: actions/cache@v4, actions/checkout@v4, actions/setup-java@v4 (admin-android-build)
! Node.js 20 is deprecated. [...]: actions/checkout@v4, actions/setup-java@v4, actions/upload-artifact@v4 (android-e2e)
! setup-java v4 is deprecated and will no longer receive updates. Please migrate to actions/setup-java@v5. (admin-android-build, android-e2e)
- "The ubuntu-latest label will migrate to Ubuntu 26 beginning October 19, 2026. [...]" (todos os 8 jobs)
```

Confirmado ao vivo: as quatro ações citadas no brief (`checkout@v4`, `cache@v4`, `setup-java@v4`, `upload-artifact@v4`) aparecem de fato nos avisos de Node.js 20, distribuídas entre os jobs conforme o uso de cada uma (nem toda ação aparece em todo job — `cache@v4` só é usada por `admin-android-build`, por exemplo); o aviso de depreciação do `setup-java v4` em si aparece nos dois jobs que o usam (`admin-android-build`, `android-e2e`); e o aviso de migração para Ubuntu 26 em 2026-10-19 aparece nos 8 jobs, já que todos usam `ubuntu-latest`.

**Recomputado: hoje (2026-09-28) até 2026-10-19 são exatamente 21 dias corridos — 3 semanas, sem arredondamento.** A data do contexto desta sessão confirma a mesma data usada no brief; não houve drift.

**FINDING-6 (severidade: média — dívida de infraestrutura com prazo concreto).** Toda execução do CI emite estas annotations, hoje ignoradas:
- `actions/checkout@v4`, `actions/cache@v4`, `actions/setup-java@v4`, `actions/upload-artifact@v4` — todas ainda no Node.js 20, forçadas a rodar em Node 24 pelo runner (aviso de depreciação da GitHub, não bloqueante ainda).
- `setup-java v4` está deprecated; o vendor recomenda migrar para `setup-java@v5`.
- `ubuntu-latest` migra para Ubuntu 26 a partir de **2026-10-19** — a **três semanas** da data desta avaliação (2026-09-28). Como nenhum job fixa a versão da imagem (todos usam `ubuntu-latest`), essa migração vai acontecer automaticamente e sem aviso prévio no dia, podendo quebrar qualquer job que dependa implicitamente de pacotes/versões do Ubuntu 24 atual (candidatos mais prováveis: `android-e2e`, que já depende de KVM e de uma regra de udev específica, e `admin-android-build`/`acs-app`/`patient-app`, que dependem do NDK/CMake cacheado).

Recomendação: fixar as ações em versões mais novas (`checkout@v5`, `setup-java@v5`, etc.) num PR pequeno e isolado, e rodar o pipeline uma vez contra uma imagem `ubuntu-24.04` explícita antes de 2026-10-19 para confirmar que nada quebra com a migração.

### 4.3 Uso de segredos e controle de concorrência

```bash
grep -n "secrets\." .github/workflows/ci.yml
grep -n "^concurrency:" .github/workflows/ci.yml
```

Saída:

```
183:      GOOGLE_MAPS_API_KEY: ${{ secrets.GOOGLE_MAPS_API_KEY }}
```

(`concurrency:` não retorna nenhuma linha — ausente do arquivo.) Idêntico ao esperado pelo brief: só uma ocorrência de `secrets.`, nenhum bloco `concurrency:`.

**Nota positiva (não é finding).** O único segredo real referenciado é `secrets.GOOGLE_MAPS_API_KEY`. `CI_POSTGRES_PASSWORD` é deliberadamente hardcoded (`.github/workflows/ci.yml:27`, valor literal `ci-ephemeral-not-a-secret`) e documentado no próprio workflow como não-segredo (banco efêmero, existe só dentro do runner) — não há vazamento de credencial de dev/prod no pipeline.

**FINDING-7 (severidade: baixa — desperdício de minutos de CI).** Não há bloco `concurrency:` no workflow. Cada novo push à mesma PR dispara uma execução completa sem cancelar a anterior. Isso é particularmente caro para `android-e2e`, que sozinho pode consumir até 60 minutos por tentativa (timeout configurado) — e a Seção 2 mostrou 15 tentativas em 10 dias na mesma PR. Um bloco como:

```yaml
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

cancelaria runs obsoletos assim que um novo commit chegasse na mesma PR/branch.

### 4.4 Verificação de log por segredo exposto

Job usado como amostra: `serverpod-backend` do run `36169873626` (job `108186514572`), por ser o que gera `config/passwords.yaml`. ID confirmado ao vivo com `gh run view 36169873626 --json jobs -q '.jobs[] | select(.name=="serverpod-backend") | .databaseId'` → `108186514572`, igual ao do brief.

```bash
gh run view --log --job=108186514572 2>&1 | grep -i "senha\|password\|secret\|token" | grep -v "CI_POSTGRES_PASSWORD\|GOOGLE_MAPS_API_KEY\|passwords.yaml"
```

A saída não veio vazia como no brief, mas nada nela é um segredo real: as linhas são (a) `Secret source: Actions` e `##[group]GITHUB_TOKEN Permissions` — texto padrão do runner sobre o próprio `GITHUB_TOKEN` efêmero, não um valor; (b) `token: ***` — já mascarado pelo GitHub; (c) o comando `docker create` do Postgres de teste, contendo `-e "POSTGRES_PASSWORD=ci-ephemeral-not-a-secret"` — o mesmo valor não-secreto da nota positiva acima, só que sem o texto literal `CI_POSTGRES_PASSWORD` que meu filtro excluía (o nome da env var vira `POSTGRES_PASSWORD` dentro do comando docker); e (d) dezenas de nomes de teste em português contendo "senha"/"token"/"segredo" (ex.: `login institucional aceita matrícula e senha corretas`, `JWT_SECRET development aceita um segredo próprio`) — são descrições de casos de teste de autenticação, não credenciais. Nenhum valor de segredo real (JWT_SECRET, AUDIT_CHAIN_SECRET, senha de paciente/ACS real, etc.) aparece no log.

Nenhum segredo exposto em log encontrado na amostra verificada.

## 5. Backlog priorizado

Ordenado por severidade (crítica → alta → média → baixa → informativa). Nenhum item foi implementado por este plano — é avaliação, não execução.

| # | Severidade | Achado | Ação recomendada | Como executar |
|---|---|---|---|---|
| FINDING-4 | Crítica | A única correção tentada para `android-e2e` (`74d89c0`: KVM, cache, smoke de um teste por app) nunca rodou no CI — a PR `develop → main` que cobriria esses commits já havia sido mesclada 22 minutos antes de `74d89c0` existir. A execução mais recente disponível (`36179475405`) testa o commit anterior (`9f21b9d`) e mostra a instalação do APK do `apps/patient` falhando duas vezes seguidas no emulador; o script aborta ali e `apps/acs`/`apps/admin` nunca chegam a rodar. | Antes de qualquer sessão de debugging, gerar o dado que falta: abrir a PR `develop → main` ou disparar o workflow manualmente contra `develop` para obter uma execução real de CI contra `74d89c0`. Só depois, se falhar, investigar a causa. | Abrir PR de integração ou `gh workflow run` contra `develop`; só se o resultado for vermelho, `superpowers:systematic-debugging` com `scripts/qa/run_android_e2e.sh` como entry point |
| FINDING-3 | Alta | As 15 execuções do CI contra a PR de integração `develop → main` nos últimos 10 dias tiveram 0 sucessos (14 falhas, 1 cancelamento por timeout); uma das duas causas alternadas (lint em `acs-app`) já foi corrigida em `9f21b9d`, a outra (`android-e2e`) persiste sem verificação (ver FINDING-4). | Tratar CI vermelho como bloqueante de fato, não como ruído de configuração; não fechar/mesclar a PR de integração sem um run 100% verde | Prática de time / reforçado por branch protection (FINDING-5), não requer mudança de código |
| FINDING-5 | Alta | Nem `main` nem `develop` têm branch protection — nenhum check de CI é obrigatório para merge, então o CI vermelho documentado no FINDING-3 nunca bloqueou ninguém | Configurar required status checks (mínimo: todos os jobs exceto talvez `android-e2e` até FINDING-4 ser resolvido) | Configuração no GitHub (Settings → Branches), fora do repositório |
| FINDING-6 | Média | Ações do workflow desatualizadas (`checkout@v4`, `cache@v4`, `setup-java@v4` deprecated, `upload-artifact@v4` em Node 20 forçado a Node 24); `ubuntu-latest` migra para Ubuntu 26 em 2026-10-19 (3 semanas a partir da data desta avaliação) | PR isolado fixando `checkout@v5`, `setup-java@v5` etc.; testar contra `ubuntu-24.04` explícito antes do prazo | PR pequeno em `.github/workflows/ci.yml` |
| FINDING-1 | Baixa | `AGENTS.md:138` descreve o CI como "seis jobs separados"; o workflow atual tem 8 (`coverage-report` e `android-e2e` nunca foram incorporados à documentação) | Atualizar a linha 138 para listar os 8 jobs, ou trocar por referência ao arquivo (`ver .github/workflows/ci.yml`) para não repetir o mesmo tipo de drift | Edição de doc |
| FINDING-7 | Baixa | Sem bloco `concurrency:` no workflow; cada novo push à mesma PR dispara uma execução completa sem cancelar a anterior, custo alto para `android-e2e` (até 60 min por tentativa, 15 tentativas em 10 dias na mesma PR) | Adicionar bloco `concurrency` ao workflow | PR pequeno em `.github/workflows/ci.yml` |
| FINDING-2 | Informativa | `push` só dispara CI em `main`/`master`; um push direto em `develop` sem PR aberta não roda o workflow — e hoje não há nenhuma PR `develop → main` aberta (a única, #7, foi mesclada em 2026-09-25), então essa cobertura simplesmente não existe agora. É exatamente essa ausência que abre a lacuna de verificação descrita no FINDING-4 | Nenhuma ação obrigatória por si só, mas é a causa estrutural do FINDING-4: considerar adicionar `push: branches: [..., develop]` ou um trigger `workflow_dispatch` para que a cobertura de CI não dependa de haver uma PR aberta por acaso | N/A por padrão; se adotada, PR pequeno em `.github/workflows/ci.yml` |

Follow-up sugerido: um plano de implementação separado (via `superpowers:writing-plans` de novo) para os itens de severidade alta/média. A prioridade imediata **não** é depurar `android-e2e` (FINDING-4) — é gerar o dado que falta, abrindo a PR `develop → main` ou disparando o workflow manualmente, já que hoje não existe nenhuma execução de CI contra a única correção já tentada. Em paralelo, o item estrutural é FINDING-5 (branch protection), para que corrigir o CI passe a valer a pena de fato.

## 6. Acompanhamento das correções

Plano: `docs/superpowers/plans/2026-09-28-ci-correcoes-avaliacao.md`.

| Achado | Estado | Evidência |
|---|---|---|
| FINDING-1 | Fechado | `32ddad5` (docs) e guarda `check_jobs` em `scripts/qa/ci_invariants.sh` |
| FINDING-2 | Fechado | `push` em `develop` e `workflow_dispatch` no `ci.yml`; guarda `check_gatilhos` |
| FINDING-7 | Fechado | bloco `concurrency` por PR/SHA; guarda `check_concorrencia` |
| FINDING-4 | Fechado — a correção de `74d89c0` funciona | run `36494654391` sobre `9d84f80` (descendente de `74d89c0`, confirmado com `git merge-base --is-ancestor`), primeiro run de CI a cobrir `74d89c0`: o passo "E2E no emulador Android" passou (smoke do paciente 1/1, smoke do ACS 1/1, RNF04 OK, ciclo do alerta vermelho OK). O job ainda terminou `failure` em 13m28s, por um defeito diferente, só visível agora que o E2E chega ao fim: o pós-passo do `subosito/flutter-action` roda `hashFiles('**/pubspec.lock')` sobre o workspace e não consegue ler `pg_data/` (modo 700, dono do container do Postgres). Corrigido com um passo `if: always()` que apaga `pg_data/` depois do E2E, com guarda `check_limpeza_do_workspace` |
