# Avaliação do CI adotado no branch develop

Data da avaliação: 2026-09-28
Workflow avaliado: `.github/workflows/ci.yml` (branch `develop`, HEAD em `74d89c0`)
Repositório: `hbgit/SinalACS`

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

**FINDING-2 (severidade: informativa).** `push` só dispara CI em `main`/`master` — um push direto em `develop` (sem PR aberto) **não** roda o workflow. A cobertura de `develop` hoje depende inteiramente de haver um `pull_request` aberto tendo `develop` como head ou base. Na prática há sempre uma PR de integração `develop → main` aberta (ver Seção 2), então o branch é coberto — mas isso é um efeito colateral do fluxo de trabalho atual, não uma garantia do workflow. Se alguém commitar direto em `develop` sem PR, o CI simplesmente não roda para aquele commit.

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

Esses números **batem exatamente** com o snapshot capturado no brief em 2026-09-28 — não houve drift. Nenhum novo run apareceu contra `develop` apesar dos commits `74d89c0` e `2eae254` terem sido pushados depois do run mais recente (`36169873626`, 17:52:44Z); isso é consistente com o FINDING-2 (Seção 1): sem um evento de PR novo, esses commits não disparam CI em `develop`.

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
