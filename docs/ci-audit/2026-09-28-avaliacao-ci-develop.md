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
