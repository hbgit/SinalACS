# Credenciais do FCM e Gorush no CI — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o job `android-e2e` do GitHub Actions decodificar os secrets `FCM_CREDENTIALS_BASE64` (chave de conta de serviço do FCM) e `GOOGLE_SERVICES_JSON_BASE64` (`google-services.json` do app do paciente), exportar `GOOGLE_APPLICATION_CREDENTIALS` e rodar o **push e2e com o Gorush e o FCM reais** no emulador do runner, sem nunca imprimir as credenciais e sem quebrar PRs de fork, onde os secrets não existem.

**Architecture:** Um script testável (`scripts/ci/decode_secret_file.sh`) decodifica cada secret: o de conta de serviço vai para um arquivo temporário `0600` em `$RUNNER_TEMP` com `GOOGLE_APPLICATION_CREDENTIALS` apontando para ele; o `google-services.json` vai para `apps/patient/android/app/` (onde o build do paciente o procura). Um segundo script (`scripts/qa/ci_push_e2e.sh`) copia a chave de `GOOGLE_APPLICATION_CREDENTIALS` para o diretório que o Gorush monta e chama o `push_e2e.sh` existente. O emulador do CI passa a usar a imagem `google_apis` (com Play Services, sem o qual o FCM não entrega token). O guarda `ci_invariants.sh` ganha invariantes para que nada disso derive sem ninguém ver.

**Tech Stack:** GitHub Actions (runner `ubuntu-24.04`, `reactivecircus/android-emulator-runner@v2`), bash, coreutils `base64`/`mktemp`/`install`, python3, Gorush 1.22.0 + FCM v1, actionlint 1.7.12 (via Docker).

**Spec:** `.github/workflows/ci.yml` (job `android-e2e`), `scripts/qa/ci_invariants.sh`, `scripts/qa/push_e2e.sh` (o que o push e2e exige), `infra/docker/gorush/README.md`, `apps/patient/android/app/build.gradle.kts` (plugin do Google Services só com o `google-services.json` presente), `CLAUDE.md` da raiz (seção do CI) e `docs/ci-audit/2026-09-28-avaliacao-ci-develop.md`.

## Estado verificado em 2026-09-30

- Os dois secrets **já estão cadastrados** no repositório: `FCM_CREDENTIALS_BASE64` e `GOOGLE_SERVICES_JSON_BASE64`. Não cadastre nada de novo.
- O `android-e2e` roda hoje **só** o smoke (`run_android_e2e.sh` → `e2e.sh --emulator --keep` + `measure_latency`). O push e2e (`push_e2e.sh`) nunca rodou na CI.
- O emulador do CI usa `api-level: 36`, `arch: x86_64`, `profile: pixel_7` e **não declara `target`**: a action usa o padrão `default` (imagem AOSP, **sem Google Play Services**). Sem Play Services o `getToken()` do FCM não devolve token. O cache do AVD tem chave `avd-36-x86_64-pixel_7-ubuntu-24.04`.
- `push_e2e.sh` (modo padrão, contra a stack de desenvolvimento) exige: `infra/docker/gorush/credentials/fcm-service-account.json` com modo `600` e ignorado pelo git (já está em `.gitignore`), `apps/patient/android/app/google-services.json` com o mesmo `project_id`, o `emulator-5554` (o padrão da action), e `.env` (do `bootstrap_env.sh`, que o job já roda). Ele segura o app instalado por 240 s.
- O build do paciente só aplica o plugin do Google Services quando `google-services.json` existe; sem ele o APK compila e o app degrada para "sem push" (é o que a CI faz hoje).
- Nada no repositório lê `GOOGLE_APPLICATION_CREDENTIALS` hoje (o Gorush lê `key_path: /credentials/fcm-service-account.json`). Este plano a torna a **origem** da chave que o `ci_push_e2e.sh` instala no diretório do Gorush.

## Global Constraints

- O conteúdo de nenhuma credencial é impresso (stdout, stderr, `::notice`/`::error`, `set -x`). Mensagens de erro não repetem trecho do secret nem do arquivo.
- Cada secret só chega ao script por `env:` do **passo**; nenhum `run:` do workflow contém `secrets.FCM_CREDENTIALS_BASE64` nem `secrets.GOOGLE_SERVICES_JSON_BASE64`, e o job não os declara em `env:` de nível de job (toda ação de terceiros os veria).
- Sem um secret (PR de fork, secret apagado): o passo termina com **sucesso**, emite `::notice` e não cria arquivo nem define variável; o job roda como roda hoje (push e2e pulado). Com o secret presente mas inválido: o passo **falha**, em voz alta.
- Arquivos: a chave em `$RUNNER_TEMP` (`0600`); a cópia no diretório do Gorush e o `google-services.json` em `0600`; um passo `if: always()` apaga os três.
- O script de decodificação **não sobrescreve** um arquivo de destino existente fora do CI (`GITHUB_ACTIONS != true`) e o modo de limpeza de arquivo **recusa** rodar fora do CI: um dev que execute o script por engano não perde o próprio `google-services.json`.
- `runs-on` continua `ubuntu-24.04`; ações nos majors mínimos (`checkout@v7`, `setup-java@v6`, `cache@v6`, `upload-artifact@v7`); sem `paths` filter; nenhum job criado ou renomeado (`JOBS_DOCUMENTADOS` e os 8 checks obrigatórios não mudam). `android-e2e` continua fora dos checks obrigatórios.
- A chave do cache do AVD continua começando com `avd-` e terminando com `-ubuntu-24.04` (invariante existente) e passa a conter o `target` do emulador.
- Textos, comentários e commits em português; commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Sem push nem merge sem o usuário pedir.
- Nenhuma credencial real em teste, log ou commit: os testes usam JSONs **falsos** (`FAKE-PRIVATE-KEY-NOT-REAL-…`).

## Review Focus

- Secrets ausentes (PR de fork, `dependabot`): o job não fica vermelho, não define `GOOGLE_APPLICATION_CREDENTIALS` e o `ci_push_e2e.sh` pula com `::notice`. Testes nas Tasks 1 e 2.
- Base64 do `base64 -w0` **e** do `base64` quebrado a cada 76 colunas, com CRLF e espaço final: todos decodificam. Teste na Task 1.
- `google-services.json` de **outro** app Firebase (pacote diferente) ou uma chave de conta de serviço colada no secret errado: falha sem vazar. Teste na Task 1.
- `google-services.json` ficando no workspace depois do job, ou apagando o de um dev rodando o script localmente: a limpeza só age no CI, e a escrita recusa sobrescrever fora dele. Teste na Task 1.
- Alguém reintroduz um secret dentro de `run:` ou no `env:` do job, remove a limpeza, move a decodificação para depois do E2E, deixa o emulador voltar à imagem sem Play Services (AOSP), ou muda o `target` sem mudar a chave do cache do AVD: o `ci_invariants.sh` falha. Teste na Task 3.
- O push e2e falhando (FCM instável) não pode esconder o resultado do smoke nem o artefato de latência: o `run_android_e2e.sh` roda o push por último e propaga o código de saída dele. Teste na Task 2 (propagação) e prova no runner na Task 5.

---

## Mapa de arquivos

- Criar: `scripts/ci/decode_secret_file.sh` e `scripts/ci/decode_secret_file_test.sh`.
- Criar: `scripts/qa/ci_push_e2e.sh` e `scripts/qa/ci_push_e2e_test.sh`.
- Criar: `scripts/qa/ci_invariants_fcm_test.sh`.
- Modificar: `scripts/qa/run_android_e2e.sh` (push por último, `down` com o perfil `push`).
- Modificar: `.github/workflows/ci.yml` (passos de decodificação e limpeza; `target: google_apis` e chave do AVD; passo de testes no `workflow-lint`).
- Modificar: `scripts/qa/ci_invariants.sh` (`CI_WORKFLOW_PATH` e `check_credenciais_fcm`).
- Modificar: `infra/docker/gorush/README.md`, `CLAUDE.md`, `PROGRESS.md`.

## Notas que o executor precisa saber antes de começar

1. **Forks:** o GitHub não entrega secrets a `pull_request` de fork; o valor chega como string vazia. É o caso que os scripts tratam com `::notice`.
2. **Mudar o `target` do emulador muda o AVD:** a primeira execução depois da mudança não acha o cache (`avd-36-google_apis-…`) e regenera o snapshot (alguns minutos a mais, uma vez). Isto é esperado.
3. **A imagem `google_apis` não foi exercitada nesta máquina** (o emulador local é a imagem Google Play, onde o push e2e já passou). Só a primeira execução no runner prova que o FCM entrega token na `google_apis`. Se não entregar, a saída é `target: google_apis_playstore`; a Task 5 cobre isso.
4. `git push` e `gh workflow run` são ações com efeito fora da máquina: a Task 5 pede confirmação do usuário antes de cada uma. `gh secret list` (só lê nomes) pode ser usado para conferir que os dois secrets existem.
5. Ferramentas: `docker` (imagem `rhysd/actionlint:1.7.12` já baixada), `python3` com PyYAML, `base64`, `mktemp` e `install` do GNU coreutils.

---

### Task 1: Script de decodificação de secrets, com testes

**Files:**
- Create: `scripts/ci/decode_secret_file.sh`
- Test: `scripts/ci/decode_secret_file_test.sh`

**Interfaces:**
- Produces (as Tasks 2–4 usam estes nomes e flags exatos):
  - `decode_secret_file.sh --env <VAR> --kind service_account|google_services (--temp-export <NOME> | --to <ARQUIVO>) [--package <id>]` — lê o secret de `$<VAR>`. Sem secret: `::notice`, exit 0, nada criado. Inválido: `::error`, exit 1, nada criado. `--temp-export NOME`: arquivo `0600` em `$RUNNER_TEMP/secret.XXXXXX.json` e linha `NOME=<arquivo>` anexada a `$GITHUB_ENV`. `--to ARQUIVO`: grava em `ARQUIVO` (`0600`, criando o diretório), **recusa** sobrescrever um arquivo existente quando `GITHUB_ACTIONS != true` (exit 1). `--package` (só `google_services`): exige um `client` com esse `package_name`.
  - `decode_secret_file.sh --cleanup-temp <NOME>` — apaga o arquivo apontado por `$<NOME>` **só** se estiver sob `$RUNNER_TEMP`; sempre exit 0.
  - `decode_secret_file.sh --cleanup-file <ARQUIVO>` — apaga `ARQUIVO` **só** se `GITHUB_ACTIONS=true`; fora do CI avisa e sai 0 sem apagar.
  - Uso incorreto (faltam `--env`/`--kind`, ou nem `--temp-export` nem `--to`, ou os dois, ou `--kind` desconhecido): exit 2.

- [ ] **Step 1: Escrever os testes que falham**

`scripts/ci/decode_secret_file_test.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Testes de decode_secret_file.sh. Sem framework: cada caso roda o script num ambiente
# novo e afirma sobre o que saiu e o que ficou em disco. As credenciais são FALSAS.
set -uo pipefail
cd "$(dirname "$0")/../.."
script="$PWD/scripts/ci/decode_secret_file.sh"
# Cada asserção que falha acrescenta uma linha ao marcador (funciona dentro de subshell).
marcador="$(mktemp)"
raiz="$(mktemp -d)"
trap 'rm -rf "$raiz" "$marcador"' EXIT
FAKE_KEY='FAKE-PRIVATE-KEY-NOT-REAL-0123456789'
PACOTE='br.com.exemplo.app'

sa_json() {
  printf '{"type":"service_account","project_id":"p","client_email":"x@p.iam.gserviceaccount.com","private_key":"%s"}' "$FAKE_KEY"
}
gs_json() {  # $1 = pacote (padrão $PACOTE)
  printf '{"project_info":{"project_id":"fake-proj","api-key-fake":"%s"},"client":[{"client_info":{"android_client_info":{"package_name":"%s"}}}]}' "$FAKE_KEY" "${1:-$PACOTE}"
}

novo_ambiente() {
  T="$(mktemp -d "$raiz/caso.XXXXXX")"   # limpo por inteiro no EXIT (um trap RETURN apagaria já ao sair daqui)
  export RUNNER_TEMP="$T/runner_tmp" GITHUB_ENV="$T/github_env"
  mkdir -p "$RUNNER_TEMP"; : >"$GITHUB_ENV"
  unset GOOGLE_APPLICATION_CREDENTIALS FCM_SECRET GS_SECRET GITHUB_ACTIONS
  DEST="$T/ws/apps/patient/android/app/google-services.json"
}

# $1 descrição; resto: comando de teste (avaliado)
afirma() {
  local desc="$1"; shift
  if eval "$*"; then echo "ok: $desc"; else echo "FALHOU: $desc"; echo x >>"$marcador"; fi
}

sa()  { "$script" --env FCM_SECRET --kind service_account --temp-export GOOGLE_APPLICATION_CREDENTIALS "$@"; }
gs()  { "$script" --env GS_SECRET --kind google_services --to "$DEST" "$@"; }
vazio_em() { [[ -z "$(ls -A "$1" 2>/dev/null)" ]]; }

t_sem_secret_termina_bem_e_nao_cria_nada() {
  novo_ambiente
  out="$(sa 2>&1)"; rc=$?
  afirma "sa sem secret: exit 0 com ::notice" '[[ $rc -eq 0 ]] && grep -q "^::notice" <<<"$out"'
  afirma "sa sem secret: GITHUB_ENV intacto e nenhum arquivo" '[[ ! -s "$GITHUB_ENV" ]] && vazio_em "$RUNNER_TEMP"'
  export GS_SECRET=$' \n\t '
  out="$(gs 2>&1)"; rc=$?
  afirma "gs só de espaços conta como ausente: exit 0, nenhum arquivo" '[[ $rc -eq 0 && ! -e "$DEST" ]]'
}

t_service_account_uma_linha() {
  novo_ambiente
  export FCM_SECRET="$(sa_json | base64 -w0)"
  out="$(sa 2>&1)"; rc=$?
  arq="$(sed -n 's/^GOOGLE_APPLICATION_CREDENTIALS=//p' "$GITHUB_ENV")"
  afirma "sa uma linha: exit 0" '[[ $rc -eq 0 ]]'
  afirma "sa uma linha: arquivo sob RUNNER_TEMP, conteúdo idêntico, modo 600" '[[ -f "$arq" && "$arq" == "$RUNNER_TEMP"/* && "$(cat "$arq")" == "$(sa_json)" && "$(stat -c %a "$arq")" == 600 ]]'
  afirma "sa uma linha: exatamente uma linha em GITHUB_ENV" '[[ "$(wc -l <"$GITHUB_ENV")" -eq 1 ]]'
  afirma "sa uma linha: NADA do conteúdo na saída" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "service_account" <<<"$out"'
}

t_service_account_quebrado_com_crlf() {
  novo_ambiente
  export FCM_SECRET="$(sa_json | base64 | sed 's/$/\r/')  "   # quebra a cada 76 colunas + CRLF + espaços
  out="$(sa 2>&1)"; rc=$?
  arq="$(sed -n 's/^GOOGLE_APPLICATION_CREDENTIALS=//p' "$GITHUB_ENV")"
  afirma "sa quebrado+CRLF: exit 0 e conteúdo idêntico" '[[ $rc -eq 0 && "$(cat "$arq")" == "$(sa_json)" ]]'
}

t_preserva_o_que_ja_estava_em_github_env() {
  novo_ambiente
  echo 'OUTRA=1' >"$GITHUB_ENV"
  export FCM_SECRET="$(sa_json | base64 -w0)"
  sa >/dev/null 2>&1
  afirma "anexa, não sobrescreve" 'grep -qx "OUTRA=1" "$GITHUB_ENV" && grep -q "^GOOGLE_APPLICATION_CREDENTIALS=" "$GITHUB_ENV"'
}

t_service_account_invalido_nao_vaza() {
  novo_ambiente
  for invalido in \
      'isto nao e base64 !!!' \
      "$(printf 'isto nao e json %s' "$FAKE_KEY" | base64 -w0)" \
      "$(printf '{"type":"authorized_user","client_email":"a","private_key":"%s"}' "$FAKE_KEY" | base64 -w0)" \
      "$(printf '{"type":"service_account","client_email":"a"}' | base64 -w0)" \
      "$(printf '[1,2,3]' | base64 -w0)" \
      "$(gs_json | base64 -w0)"; do
    export FCM_SECRET="$invalido"
    out="$(sa 2>&1)"; rc=$?
    afirma "sa inválido (${invalido:0:10}…): exit 1 com ::error" '[[ $rc -eq 1 ]] && grep -q "^::error" <<<"$out"'
    afirma "sa inválido: nada do conteúdo vaza e nenhum traceback do Python" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "isto nao e" <<<"$out" && ! grep -q "Traceback" <<<"$out"'
    afirma "sa inválido: não deixa arquivo nem variável" 'vazio_em "$RUNNER_TEMP" && [[ ! -s "$GITHUB_ENV" ]]'
  done
}

t_google_services_grava_no_destino() {
  novo_ambiente
  export GS_SECRET="$(gs_json | base64 -w0)"
  out="$(gs --package "$PACOTE" 2>&1)"; rc=$?
  afirma "gs: exit 0, arquivo no destino com conteúdo idêntico e modo 600" '[[ $rc -eq 0 && "$(cat "$DEST")" == "$(gs_json)" && "$(stat -c %a "$DEST")" == 600 ]]'
  afirma "gs: não exporta variável e não deixa temporário" '[[ ! -s "$GITHUB_ENV" ]] && vazio_em "$RUNNER_TEMP"'
  afirma "gs: nada do conteúdo na saída" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "fake-proj" <<<"$out"'
}

t_google_services_invalido() {
  novo_ambiente
  for invalido in \
      "$(gs_json 'br.com.OUTRO.app' | base64 -w0)" \
      "$(printf '{"project_info":{"project_id":"x"},"client":[]}' | base64 -w0)" \
      "$(printf '{"client":[{"client_info":{"android_client_info":{"package_name":"%s"}}}]}' "$PACOTE" | base64 -w0)" \
      "$(sa_json | base64 -w0)" \
      'isto nao e base64 !!!'; do
    export GS_SECRET="$invalido"
    out="$(gs --package "$PACOTE" 2>&1)"; rc=$?
    afirma "gs inválido (${invalido:0:10}…): exit 1 e nada gravado" '[[ $rc -eq 1 && ! -e "$DEST" ]] && grep -q "^::error" <<<"$out"'
    afirma "gs inválido: nada do conteúdo vaza" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "fake-proj" <<<"$out"'
  done
}

t_nao_sobrescreve_fora_do_ci() {
  novo_ambiente
  mkdir -p "$(dirname "$DEST")"; echo 'DO-DEV' >"$DEST"
  export GS_SECRET="$(gs_json | base64 -w0)"
  out="$(gs 2>&1)"; rc=$?
  afirma "fora do CI: recusa sobrescrever e preserva o arquivo do dev" '[[ $rc -eq 1 && "$(cat "$DEST")" == "DO-DEV" ]]'
  out="$(GITHUB_ACTIONS=true gs 2>&1)"; rc=$?
  afirma "no CI: sobrescreve" '[[ $rc -eq 0 && "$(cat "$DEST")" == "$(gs_json)" ]]'
}

t_cleanup_temp_apaga_so_sob_runner_temp() {
  novo_ambiente
  export FCM_SECRET="$(sa_json | base64 -w0)"
  sa >/dev/null 2>&1
  export GOOGLE_APPLICATION_CREDENTIALS="$(sed -n 's/^GOOGLE_APPLICATION_CREDENTIALS=//p' "$GITHUB_ENV")"
  "$script" --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS; rc=$?
  afirma "cleanup-temp: exit 0 e arquivo removido" '[[ $rc -eq 0 && ! -e "$GOOGLE_APPLICATION_CREDENTIALS" ]]'
  alheio="$T/alheio.json"; echo x >"$alheio"
  GOOGLE_APPLICATION_CREDENTIALS="$alheio" "$script" --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS
  afirma "cleanup-temp: não apaga arquivo fora do RUNNER_TEMP" '[[ -e "$alheio" ]]'
  unset GOOGLE_APPLICATION_CREDENTIALS
  "$script" --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS; rc=$?
  afirma "cleanup-temp sem variável: exit 0" '[[ $rc -eq 0 ]]'
}

t_cleanup_file_so_no_ci() {
  novo_ambiente
  mkdir -p "$(dirname "$DEST")"; echo 'DO-DEV' >"$DEST"
  "$script" --cleanup-file "$DEST"; rc=$?
  afirma "cleanup-file fora do CI: exit 0 e NÃO apaga" '[[ $rc -eq 0 && -e "$DEST" ]]'
  GITHUB_ACTIONS=true "$script" --cleanup-file "$DEST"; rc=$?
  afirma "cleanup-file no CI: apaga" '[[ $rc -eq 0 && ! -e "$DEST" ]]'
  GITHUB_ACTIONS=true "$script" --cleanup-file "$DEST"; rc=$?
  afirma "cleanup-file de arquivo inexistente: exit 0" '[[ $rc -eq 0 ]]'
}

t_uso_incorreto() {
  novo_ambiente
  "$script" --kind service_account --temp-export X >/dev/null 2>&1; rc=$?
  afirma "sem --env: exit 2" '[[ $rc -eq 2 ]]'
  "$script" --env A --kind service_account >/dev/null 2>&1; rc=$?
  afirma "sem destino: exit 2" '[[ $rc -eq 2 ]]'
  "$script" --env A --kind service_account --temp-export X --to /tmp/y >/dev/null 2>&1; rc=$?
  afirma "os dois destinos: exit 2" '[[ $rc -eq 2 ]]'
  "$script" --env A --kind outro --temp-export X >/dev/null 2>&1; rc=$?
  afirma "kind desconhecido: exit 2" '[[ $rc -eq 2 ]]'
}

t_nao_usa_set_x() {
  afirma "o script não liga set -x (vazaria o secret no log)" '! grep -Eq "^[[:space:]]*set [-+a-z]*x|set -o xtrace" "$script"'
}

t_sem_secret_termina_bem_e_nao_cria_nada
t_service_account_uma_linha
t_service_account_quebrado_com_crlf
t_preserva_o_que_ja_estava_em_github_env
t_service_account_invalido_nao_vaza
t_google_services_grava_no_destino
t_google_services_invalido
t_nao_sobrescreve_fora_do_ci
t_cleanup_temp_apaga_so_sob_runner_temp
t_cleanup_file_so_no_ci
t_uso_incorreto
t_nao_usa_set_x

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — decode_secret_file.sh" || { echo "$n asserção(ões) falharam"; exit 1; }
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `chmod +x scripts/ci/decode_secret_file_test.sh && ./scripts/ci/decode_secret_file_test.sh; echo rc=$?`
Expected: `rc=1`, dezenas de `FALHOU: …`, porque `scripts/ci/decode_secret_file.sh` não existe. (A asserção de `set -x` passa por ausência; é esperado.)

- [ ] **Step 3: Implementar o script**

`scripts/ci/decode_secret_file.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
#
# Decodifica um secret do GitHub que guarda um arquivo em base64 (`base64 -w0 arquivo`).
#
#   --env VAR --kind service_account --temp-export NOME   # arquivo 0600 em $RUNNER_TEMP + NOME=<caminho> em $GITHUB_ENV
#   --env VAR --kind google_services  --to ARQUIVO [--package ID]
#   --cleanup-temp NOME                                   # apaga o arquivo de $NOME, só se sob $RUNNER_TEMP
#   --cleanup-file ARQUIVO                                # apaga ARQUIVO, só no CI (GITHUB_ACTIONS=true)
#
# Por que é um script e não YAML inline: o secret entra por `env:` do passo (nunca por
# `${{ }}` dentro de `run:`, que é injeção de script e pede um `echo` para vazar) e o
# comportamento fica testável (decode_secret_file_test.sh).
#
# Regras: NUNCA imprime o conteúdo (sem `set -x`, sem eco, erros genéricos); sem o secret
# (PR de fork) sai com 0 e não cria nada; com o secret inválido sai com 1; fora do CI não
# sobrescreve nem apaga arquivo que já existia (é o `google-services.json` de um dev).
set -euo pipefail
umask 077

uso() { echo 'uso: decode_secret_file.sh --env VAR --kind service_account|google_services (--temp-export NOME | --to ARQUIVO) [--package ID] | --cleanup-temp NOME | --cleanup-file ARQUIVO' >&2; exit 2; }

modo=decodificar; env_nome=''; tipo=''; temp_export=''; destino=''; pacote=''; alvo=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) [[ $# -ge 2 ]] || uso; env_nome="$2"; shift 2 ;;
    --kind) [[ $# -ge 2 ]] || uso; tipo="$2"; shift 2 ;;
    --temp-export) [[ $# -ge 2 ]] || uso; temp_export="$2"; shift 2 ;;
    --to) [[ $# -ge 2 ]] || uso; destino="$2"; shift 2 ;;
    --package) [[ $# -ge 2 ]] || uso; pacote="$2"; shift 2 ;;
    --cleanup-temp) [[ $# -ge 2 ]] || uso; modo=limpar_temp; alvo="$2"; shift 2 ;;
    --cleanup-file) [[ $# -ge 2 ]] || uso; modo=limpar_arquivo; alvo="$2"; shift 2 ;;
    *) uso ;;
  esac
done

if [[ "$modo" == limpar_temp ]]; then
  arquivo="${!alvo:-}"
  # Só apaga o que este script criou: sob $RUNNER_TEMP. Outro passo pode ter
  # redefinido a variável para um arquivo que não é nosso.
  if [[ -n "$arquivo" && -n "${RUNNER_TEMP:-}" && "$arquivo" == "$RUNNER_TEMP"/* ]]; then
    rm -f -- "$arquivo"
  fi
  exit 0
fi

if [[ "$modo" == limpar_arquivo ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    rm -f -- "$alvo"
  else
    echo "aviso: --cleanup-file só age no CI (GITHUB_ACTIONS=true); $alvo foi mantido." >&2
  fi
  exit 0
fi

# -- decodificar -------------------------------------------------------------
[[ -n "$env_nome" && -n "$tipo" ]] || uso
[[ "$tipo" == service_account || "$tipo" == google_services ]] || uso
if [[ -n "$temp_export" && -n "$destino" ]] || [[ -z "$temp_export" && -z "$destino" ]]; then uso; fi

segredo="${!env_nome:-}"
if [[ -z "${segredo//[[:space:]]/}" ]]; then
  echo "::notice title=secret::$env_nome ausente (PR de fork ou secret não cadastrado): nada foi decodificado e o que depende dele fica desligado."
  exit 0
fi

if [[ -n "$destino" && -e "$destino" && "${GITHUB_ACTIONS:-}" != true ]]; then
  echo "::error title=secret::$destino já existe e isto não é o CI: não sobrescrevo o arquivo de um desenvolvedor."
  exit 1
fi

dir="${RUNNER_TEMP:-$(mktemp -d)}"
tmp="$(mktemp --suffix=.json "$dir/secret.XXXXXX")"
falhar() {
  rm -f -- "$tmp"
  echo "::error title=secret::$1"
  exit 1
}

# base64 do `base64 -w0`, do `base64` com quebra em 76 colunas, com CRLF ou espaço
# final: tudo que é espaço em branco sai antes de decodificar.
if ! printf '%s' "$segredo" | tr -d '[:space:]' | base64 -d >"$tmp" 2>/dev/null; then
  falhar "$env_nome não é um base64 válido."
fi

# Só confirma a FORMA. Saída e erro descartados: um traceback do Python imprimiria o dado.
if ! python3 - "$tmp" "$tipo" "$pacote" >/dev/null 2>&1 <<'PY'
import json, sys
caminho, tipo, pacote = sys.argv[1:4]
d = json.load(open(caminho, encoding='utf-8'))
if tipo == 'service_account':
    ok = (isinstance(d, dict) and d.get('type') == 'service_account'
          and d.get('client_email') and d.get('private_key'))
else:  # google_services
    clientes = d.get('client') if isinstance(d, dict) else None
    ok = bool(isinstance(d, dict) and (d.get('project_info') or {}).get('project_id')
              and isinstance(clientes, list) and clientes)
    if ok and pacote:
        ok = any((((c.get('client_info') or {}).get('android_client_info') or {}).get('package_name') == pacote)
                 for c in clientes if isinstance(c, dict))
sys.exit(0 if ok else 1)
PY
then
  falhar "$env_nome decodificou, mas não tem a forma esperada de um $tipo${pacote:+ do pacote $pacote}."
fi

chmod 600 "$tmp"
if [[ -n "$destino" ]]; then
  mkdir -p "$(dirname "$destino")"
  mv -f -- "$tmp" "$destino"
  echo "::notice title=secret::$env_nome decodificado em $destino (conteúdo não impresso)."
else
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "$temp_export=$tmp" >>"$GITHUB_ENV"
  fi
  echo "::notice title=secret::$env_nome decodificado em $tmp ($temp_export definida para os próximos passos; conteúdo não impresso)."
fi
```

- [ ] **Step 4: Rodar e ver passar**

Run: `./scripts/ci/decode_secret_file_test.sh; echo rc=$?`
Expected: todas as linhas `ok: …`, terminando em `OK — decode_secret_file.sh`, `rc=0`.

- [ ] **Step 5: Provar que os testes pegam mutações**

Rode cada mutação temporária numa cópia (`cp scripts/ci/decode_secret_file.sh /tmp/bak.sh`, edite, rode o teste, restaure com `cp /tmp/bak.sh scripts/ci/decode_secret_file.sh`):
1. Troque `chmod 600 "$tmp"` por `chmod 644 "$tmp"` **e** apague `umask 077` → o teste falha em `modo 600`.
2. Apague `>/dev/null 2>&1` do `python3 -` → o teste falha em `nenhum traceback do Python`.
3. Apague o `if [[ -n "$destino" && -e "$destino" … ]]` inteiro → falha `fora do CI: recusa sobrescrever`.
4. Troque `"${GITHUB_ACTIONS:-}" == true` do `--cleanup-file` por `-n "${GITHUB_ACTIONS:-x}"` → falha `cleanup-file fora do CI … NÃO apaga`.
Expected: vermelho em cada uma; verde de novo após restaurar.

- [ ] **Step 6: Commit**

```bash
git add scripts/ci/decode_secret_file.sh scripts/ci/decode_secret_file_test.sh
git commit -m "ci: script que decodifica secrets em base64 (chave do FCM e google-services.json) sem imprimir nem sobrescrever

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Push e2e no CI — `ci_push_e2e.sh` e o `run_android_e2e.sh`

**Files:**
- Create: `scripts/qa/ci_push_e2e.sh`
- Test: `scripts/qa/ci_push_e2e_test.sh`
- Modify: `scripts/qa/run_android_e2e.sh` (linhas 15 e 28-31)

**Interfaces:**
- Consumes: `GOOGLE_APPLICATION_CREDENTIALS` (caminho da chave, definido pelo passo da Task 4 via `--temp-export`), `apps/patient/android/app/google-services.json`, `./scripts/qa/push_e2e.sh` (existente; sem argumentos no CI, isto é, só o caminho feliz).
- Produces: `ci_push_e2e.sh` — sem a chave ou sem o `google-services.json`: `::notice`, exit 0. Com os dois: instala a chave em `infra/docker/gorush/credentials/fcm-service-account.json` (modo `0600`) e **é substituído** (`exec`) por `$PUSH_E2E_SCRIPT` (padrão `./scripts/qa/push_e2e.sh`; só o teste o troca), propagando o exit dele. `run_android_e2e.sh` roda o push **por último** e sai com o código dele.

- [ ] **Step 1: Escrever o teste que falha**

`scripts/qa/ci_push_e2e_test.sh` (`chmod +x`). Ele monta uma árvore mínima num diretório temporário (o script faz `cd` para a raiz a partir da própria localização):

```bash
#!/usr/bin/env bash
# ci_push_e2e.sh: pula sem credenciais; com elas, instala a chave e chama o push e2e.
set -uo pipefail
cd "$(dirname "$0")/../.."
orig="$PWD/scripts/qa/ci_push_e2e.sh"
raiz="$(mktemp -d)"; trap 'rm -rf "$raiz"' EXIT
marcador="$raiz/falhas"; : >"$marcador"
afirma() { if eval "$2"; then echo "ok: $1"; else echo "FALHOU: $1"; echo x >>"$marcador"; fi; }

nova_arvore() {
  R="$raiz/repo.$RANDOM"; mkdir -p "$R/scripts/qa" "$R/apps/patient/android/app"
  cp "$orig" "$R/scripts/qa/ci_push_e2e.sh"
  cat >"$R/stub_push.sh" <<'STUB'
#!/usr/bin/env bash
echo "chamado" >>"$(dirname "$0")/chamadas"
[[ -f infra/docker/gorush/credentials/fcm-service-account.json ]] && stat -c %a infra/docker/gorush/credentials/fcm-service-account.json >"$(dirname "$0")/modo_da_chave"
exit "${STUB_RC:-0}"
STUB
  chmod +x "$R/stub_push.sh" "$R/scripts/qa/ci_push_e2e.sh"
  echo '{"chave":"FAKE"}' >"$raiz/chave.json"
  unset GOOGLE_APPLICATION_CREDENTIALS STUB_RC
  export PUSH_E2E_SCRIPT="$R/stub_push.sh"
}
roda() { "$R/scripts/qa/ci_push_e2e.sh" 2>&1; }

nova_arvore
out="$(roda)"; rc=$?
afirma "sem variável e sem google-services: pula (exit 0, ::notice, stub não chamado)" '[[ $rc -eq 0 ]] && grep -q "^::notice" <<<"$out" && [[ ! -e "$R/chamadas" ]]'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json"
out="$(roda)"; rc=$?
afirma "com a chave mas sem google-services.json: pula" '[[ $rc -eq 0 && ! -e "$R/chamadas" && ! -e "$R/infra" ]]'

nova_arvore
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "com google-services.json mas sem a chave: pula" '[[ $rc -eq 0 && ! -e "$R/chamadas" ]]'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/inexistente.json"
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "variável apontando para arquivo inexistente: pula" '[[ $rc -eq 0 && ! -e "$R/chamadas" ]]'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json"
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
cofre="$R/infra/docker/gorush/credentials/fcm-service-account.json"
afirma "com os dois: instala a chave idêntica em 0600" '[[ "$(cat "$cofre")" == "$(cat "$raiz/chave.json")" && "$(cat "$R/modo_da_chave")" == 600 ]]'
afirma "com os dois: chama o push e2e uma vez" '[[ "$(wc -l <"$R/chamadas")" -eq 1 ]]'
afirma "a saída não imprime o conteúdo da chave" '! grep -q "FAKE" <<<"$out"'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json" STUB_RC=7
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "o exit do push e2e é propagado (7)" '[[ $rc -eq 7 ]]'

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — ci_push_e2e.sh" || { echo "$n asserção(ões) falharam"; exit 1; }
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `chmod +x scripts/qa/ci_push_e2e_test.sh && ./scripts/qa/ci_push_e2e_test.sh; echo rc=$?`
Expected: `rc=1` (o `cp` do script inexistente falha e as asserções ficam vermelhas).

- [ ] **Step 3: Implementar o script**

`scripts/qa/ci_push_e2e.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
#
# Push e2e (Gorush e FCM reais) no CI — só se as credenciais existirem.
#
# Precisa de GOOGLE_APPLICATION_CREDENTIALS (chave da conta de serviço, decodificada pelo
# passo do workflow) e de apps/patient/android/app/google-services.json. Sem elas (PR de
# fork, secrets ausentes) avisa e sai com 0: o smoke do job continua valendo sozinho.
#
# O Gorush lê a chave de infra/docker/gorush/credentials/fcm-service-account.json
# (config.yml `key_path`), então a chave de GOOGLE_APPLICATION_CREDENTIALS é instalada ali
# com modo 600, que é o que o push_e2e.sh exige. Nunca imprime a chave.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

origem="${GOOGLE_APPLICATION_CREDENTIALS:-}"
google_services=apps/patient/android/app/google-services.json
destino=infra/docker/gorush/credentials/fcm-service-account.json
push="${PUSH_E2E_SCRIPT:-./scripts/qa/push_e2e.sh}"

if [[ -z "$origem" || ! -f "$origem" || ! -f "$google_services" ]]; then
  echo '::notice title=push e2e::sem a chave do FCM ou sem google-services.json (PR de fork ou secrets ausentes): push e2e pulado.'
  exit 0
fi

install -D -m 600 "$origem" "$destino"
exec "$push"
```

- [ ] **Step 4: Rodar e ver passar**

Run: `./scripts/qa/ci_push_e2e_test.sh; echo rc=$?`
Expected: todas `ok:` e `OK — ci_push_e2e.sh`, `rc=0`.

- [ ] **Step 5: Ligar ao `run_android_e2e.sh`**

Em `scripts/qa/run_android_e2e.sh`:

(a) linha 15: `trap 'docker compose down' EXIT` → `trap 'docker compose --profile push down' EXIT` (com o perfil, o Gorush que o push e2e sobe também é derrubado).

(b) substituir as linhas 28–31 por:

```bash
./scripts/qa/e2e.sh --emulator --keep
dart run scripts/qa/measure_latency.dart \
  --mqtt-password "$MQTT_ACS_PASSWORD" \
  --output build/qa/latency/metrics.json

# Push e2e (Gorush e FCM reais) por ÚLTIMO: uma falha do FCM não pode esconder o resultado
# do smoke nem impedir o artefato de latência, mas o job TEM de falhar quando o push falha.
# Sem as credenciais (PR de fork) o script avisa e sai com 0.
push_rc=0
./scripts/qa/ci_push_e2e.sh || push_rc=$?
exit "$push_rc"
```

- [ ] **Step 6: Verificar sintaxe e commit**

Run: `bash -n scripts/qa/run_android_e2e.sh scripts/qa/ci_push_e2e.sh && echo ok`
Expected: `ok`.

```bash
git add scripts/qa/ci_push_e2e.sh scripts/qa/ci_push_e2e_test.sh scripts/qa/run_android_e2e.sh
git commit -m "ci(android-e2e): push e2e com o Gorush e o FCM reais quando há credenciais, por último e propagando o resultado

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Invariantes do workflow (credenciais e emulador com Play Services)

**Files:**
- Modify: `scripts/qa/ci_invariants.sh` (a linha do `exec python3 - …`; novo `check_credenciais_fcm`; lista `CHECKS`)
- Test: `scripts/qa/ci_invariants_fcm_test.sh`

**Interfaces:**
- Consumes: os nomes exatos que a Task 4 cria no `ci.yml` — passos `Decodifica a credencial do FCM` (env `FCM_CREDENTIALS_BASE64`), `Decodifica o google-services.json` (env `GOOGLE_SERVICES_JSON_BASE64`), `Remove as credenciais do FCM` (`if: always()`, `run` contendo `decode_secret_file.sh --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS`, `--cleanup-file apps/patient/android/app/google-services.json` e `--cleanup-file infra/docker/gorush/credentials/fcm-service-account.json`), o passo `E2E no emulador Android`, e os dois passos `reactivecircus/android-emulator-runner` com `target: google_apis` e a chave de cache `avd-36-google_apis-x86_64-pixel_7-ubuntu-24.04`.
- Produces: `CI_WORKFLOW_PATH` (variável opcional que aponta o guarda para outro `ci.yml`, só para teste) e `check_credenciais_fcm` (mais um item em `CHECKS`; a mensagem final passa de `8 grupos` para `9 grupos`).

- [ ] **Step 1: Escrever o teste que falha**

`scripts/qa/ci_invariants_fcm_test.sh` (`chmod +x`): muta uma cópia do `ci.yml` e exige que o guarda reprove cada regressão (e aprove a cópia intacta).

```bash
#!/usr/bin/env bash
# O guarda do workflow precisa pegar as regressões das credenciais do FCM e do emulador.
set -uo pipefail
cd "$(dirname "$0")/../.."
orig=.github/workflows/ci.yml
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
marcador="$tmp/falhas"; : >"$marcador"

roda() { CI_WORKFLOW_PATH="$1" ./scripts/qa/ci_invariants.sh 2>&1; }
afirma() { if eval "$2"; then echo "ok: $1"; else echo "FALHOU: $1"; echo x >>"$marcador"; fi; }

# mutação: $1 nome, $2 expressão python em `t` (o texto do ci.yml) que devolve o novo texto
muta() {
  local nome="$1" codigo="$2" alvo="$tmp/$1.yml"
  python3 - "$orig" "$alvo" <<PY
import sys
t = open(sys.argv[1], encoding='utf-8').read()
novo = (lambda t: $codigo)(t)
assert novo != t, 'a mutação não mudou nada (o texto esperado mudou no ci.yml?)'
open(sys.argv[2], 'w', encoding='utf-8').write(novo)
PY
  out="$(roda "$alvo")"; rc=$?
  afirma "$nome: o guarda reprova" '[[ $rc -ne 0 ]]'
  afirma "$nome: a falha cita o FCM" 'grep -q "FCM" <<<"$out"'
}

out="$(roda "$orig")"; rc=$?
afirma "workflow intacto passa" '[[ $rc -eq 0 ]]'

muta fcm_sem_env_do_passo \
  "t.replace('          FCM_CREDENTIALS_BASE64: \${{ secrets.FCM_CREDENTIALS_BASE64 }}\n', '', 1)"
muta gs_sem_env_do_passo \
  "t.replace('          GOOGLE_SERVICES_JSON_BASE64: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}\n', '', 1)"
muta fcm_dentro_do_run \
  "t.replace('--env FCM_CREDENTIALS_BASE64', '--env X_\${{ secrets.FCM_CREDENTIALS_BASE64 }}', 1)"
muta gs_dentro_do_run \
  "t.replace('--env GOOGLE_SERVICES_JSON_BASE64', '--env X_\${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}', 1)"
muta fcm_no_env_do_job \
  "t.replace('      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n', '      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n      FCM_CREDENTIALS_BASE64: \${{ secrets.FCM_CREDENTIALS_BASE64 }}\n', 1)"
muta gs_no_env_do_job \
  "t.replace('      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n', '      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n      GOOGLE_SERVICES_JSON_BASE64: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}\n', 1)"
muta limpeza_sem_always \
  "t.replace('        if: always()\n        run: |\n          ./scripts/ci/decode_secret_file.sh --cleanup-temp', '        run: |\n          ./scripts/ci/decode_secret_file.sh --cleanup-temp', 1)"
muta limpeza_sem_google_services \
  "t.replace('--cleanup-file apps/patient/android/app/google-services.json', 'true', 1)"
muta limpeza_sem_chave_do_gorush \
  "t.replace('--cleanup-file infra/docker/gorush/credentials/fcm-service-account.json', 'true', 1)"
muta decodifica_depois_do_e2e \
  "t.replace('      - name: Decodifica o google-services.json', '      - name: Decodifica o google-services.json (movido)', 1)"
muta emulador_sem_play_services \
  "t.replace('          target: google_apis\n', '', 1)"
muta cache_do_avd_sem_o_target \
  "t.replace('avd-36-google_apis-x86_64-pixel_7-ubuntu-24.04', 'avd-36-x86_64-pixel_7-ubuntu-24.04', 1)"

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — invariantes das credenciais do FCM" || { echo "$n asserção(ões) falharam"; exit 1; }
```

As mutações usam os trechos **exatos** que a Task 4 escreve no `ci.yml`. O `assert` de "a mutação não mudou nada" faz um texto divergente estourar em voz alta: se estourar, ajuste a string da mutação para o texto real do `ci.yml`, não enfraqueça o guarda. As mensagens do guarda abaixo começam com `FCM:` porque o teste exige isso em todas as mutações.

- [ ] **Step 2: Rodar e ver falhar**

Run: `chmod +x scripts/qa/ci_invariants_fcm_test.sh && ./scripts/qa/ci_invariants_fcm_test.sh; echo rc=$?`
Expected: `rc=1` (o `ci.yml` ainda não tem os passos: a primeira mutação já estoura o `assert` "não mudou nada").

- [ ] **Step 3: Implementar o guarda**

Em `scripts/qa/ci_invariants.sh`:

(a) trocar a linha do `exec`:

```bash
exec python3 - "${CI_WORKFLOW_PATH:-$repo_root/.github/workflows/ci.yml}" "$@" <<'PY'
```

(b) acrescentar, antes de `CHECKS = [`:

```python
# Credenciais do FCM (chave de conta de serviço e google-services.json) no android-e2e.
# Os secrets valem acesso ao projeto Firebase; estas propriedades têm de sobreviver a
# edições:
#  1. cada secret entra por `env:` do PASSO — nunca dentro de `run:` (injeção de script, e
#     um `echo` o vazaria) nem no `env:` do JOB (toda ação de terceiros o veria);
#  2. os passos que os decodificam vêm ANTES do E2E (o build do paciente e o push e2e os
#     leem);
#  3. um passo `if: always()` apaga os três arquivos depois;
#  4. o push só entrega com Play Services: o emulador precisa de `target: google_apis` (o
#     padrão da action é a imagem AOSP, sem ele), e a chave do cache do AVD precisa
#     conter o target, senão um AVD antigo seria restaurado em cima do novo.
SEGREDOS_FCM = {
    'FCM_CREDENTIALS_BASE64': 'Decodifica a credencial do FCM',
    'GOOGLE_SERVICES_JSON_BASE64': 'Decodifica o google-services.json',
}
LIMPEZA_FCM = 'Remove as credenciais do FCM'
LIMPEZAS_ESPERADAS = (
    'decode_secret_file.sh --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS',
    '--cleanup-file apps/patient/android/app/google-services.json',
    '--cleanup-file infra/docker/gorush/credentials/fcm-service-account.json',
)
TARGET_EMULADOR = 'google_apis'


def check_credenciais_fcm():
    for nome_job, job in jobs.items():
        for segredo in SEGREDOS_FCM:
            if segredo in (job.get('env') or {}):
                falhas.append(f'FCM: {nome_job} declara {segredo} no env: do job; declare só no passo')
            for passo in job.get('steps') or []:
                if f'secrets.{segredo}' in (passo.get('run') or ''):
                    falhas.append(f"FCM: o passo {passo.get('name')!r} de {nome_job} usa secrets.{segredo} dentro de run:; passe por env: do passo")
    passos = (jobs.get('android-e2e') or {}).get('steps') or []
    nomes = [p.get('name', '') for p in passos]
    indice_e2e = nomes.index('E2E no emulador Android') if 'E2E no emulador Android' in nomes else None
    ultimo = -1
    for segredo, nome_passo in SEGREDOS_FCM.items():
        if nome_passo not in nomes:
            falhas.append(f'FCM: android-e2e sem o passo {nome_passo!r}')
            continue
        i = nomes.index(nome_passo)
        ultimo = max(ultimo, i)
        passo = passos[i]
        if (passo.get('env') or {}).get(segredo) != '${{ secrets.' + segredo + ' }}':
            falhas.append(f'FCM: o passo {nome_passo!r} precisa de env: {segredo}: ${{{{ secrets.{segredo} }}}}')
        if 'decode_secret_file.sh' not in (passo.get('run') or ''):
            falhas.append(f'FCM: o passo {nome_passo!r} precisa chamar scripts/ci/decode_secret_file.sh')
        if indice_e2e is not None and i > indice_e2e:
            falhas.append(f'FCM: {nome_passo!r} vem DEPOIS do E2E; o arquivo não existiria nele')
    limpeza = [p for p in passos[ultimo + 1:] if p.get('name') == LIMPEZA_FCM]
    if not limpeza:
        falhas.append(f'FCM: nenhum passo {LIMPEZA_FCM!r} depois das decodificações')
    else:
        passo = limpeza[0]
        if passo.get('if') != 'always()':
            falhas.append(f'FCM: o passo {LIMPEZA_FCM!r} precisa de if: always()')
        for trecho in LIMPEZAS_ESPERADAS:
            if trecho not in (passo.get('run') or ''):
                falhas.append(f'FCM: o passo {LIMPEZA_FCM!r} não roda {trecho!r}')
    # Emulador com Play Services e cache do AVD coerente.
    emuladores = [p for p in passos if str(p.get('uses', '')).startswith('reactivecircus/android-emulator-runner')]
    if not emuladores:
        falhas.append('FCM: android-e2e sem passo reactivecircus/android-emulator-runner')
    for passo in emuladores:
        if (passo.get('with') or {}).get('target') != TARGET_EMULADOR:
            falhas.append(f"FCM: o passo {passo.get('name')!r} precisa de target: {TARGET_EMULADOR} (sem Play Services o FCM não entrega token)")
    for passo in passos:
        chave = str((passo.get('with') or {}).get('key', ''))
        if chave.startswith('avd-') and f'-{TARGET_EMULADOR}-' not in chave:
            falhas.append(f'FCM: a chave do cache do AVD {chave!r} não contém o target {TARGET_EMULADOR!r}')
```

(c) acrescentar `check_credenciais_fcm` ao final da lista `CHECKS`.

- [ ] **Step 4: Rodar (ainda vermelho, por falta do `ci.yml`)**

Run: `./scripts/qa/ci_invariants.sh; echo rc=$?`
Expected: várias linhas `FALHA: FCM: …` e `rc=1`. É o esperado: o guarda já está certo e o workflow ainda não. A Task 4 o deixa verde.

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/ci_invariants.sh scripts/qa/ci_invariants_fcm_test.sh
git commit -m "ci: invariantes das credenciais do FCM e do emulador com Play Services

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

> Este commit deixa o `ci_invariants.sh` vermelho até a Task 4. **Não dê push entre as Tasks 3 e 4**: a Task 4 é o commit que fecha o par.

---

### Task 4: Passos no `ci.yml`

**Files:**
- Modify: `.github/workflows/ci.yml` (jobs `android-e2e` e `workflow-lint`)

**Interfaces:**
- Consumes: `scripts/ci/decode_secret_file.sh` (Task 1), `scripts/qa/run_android_e2e.sh` já com o push (Task 2), os nomes que o guarda da Task 3 exige.
- Produces: o `android-e2e` decodifica as duas credenciais antes do E2E, limpa sempre, e usa o emulador `google_apis`.

- [ ] **Step 1: Passos de decodificação**

Logo depois de `- uses: actions/checkout@v7` do job `android-e2e` (antes de `Habilita KVM`):

```yaml
      # Credenciais do FCM para o push e2e (Gorush e FCM reais). Cada secret é um arquivo em
      # base64 (`base64 -w0 arquivo`). A chave da conta de serviço vai para um arquivo
      # temporário (0600) e GOOGLE_APPLICATION_CREDENTIALS aponta para ele; o
      # google-services.json vai para onde o build do paciente o procura (sem ele o APK
      # compila e degrada para "sem push"). Sem os secrets (PR de fork) os passos só avisam
      # e o job roda como sempre. Cada secret entra por `env:` do PASSO: nunca em `run:`
      # (injeção de script) e nunca no `env:` do job (toda ação de terceiros o veria) —
      # ci_invariants.sh vigia as duas coisas.
      - name: Decodifica a credencial do FCM
        env:
          FCM_CREDENTIALS_BASE64: ${{ secrets.FCM_CREDENTIALS_BASE64 }}
        run: |
          ./scripts/ci/decode_secret_file.sh --env FCM_CREDENTIALS_BASE64 \
            --kind service_account --temp-export GOOGLE_APPLICATION_CREDENTIALS
      - name: Decodifica o google-services.json
        env:
          GOOGLE_SERVICES_JSON_BASE64: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
        run: |
          ./scripts/ci/decode_secret_file.sh --env GOOGLE_SERVICES_JSON_BASE64 \
            --kind google_services --package br.com.prismrr.sinalacs.patient \
            --to apps/patient/android/app/google-services.json
```

- [ ] **Step 2: Emulador com Play Services**

Nos **dois** passos `reactivecircus/android-emulator-runner@v2` (`Gera o snapshot do AVD para o cache` e `E2E no emulador Android`), logo depois de `api-level: 36`:

```yaml
          target: google_apis
```

E a chave do cache do AVD (`key: avd-36-x86_64-pixel_7-ubuntu-24.04`) passa a:

```yaml
          key: avd-36-google_apis-x86_64-pixel_7-ubuntu-24.04
```

Acrescente ao comentário dessa chave: `# target no nome: o push e2e precisa de Play Services (a imagem padrão da action é AOSP, sem ele); trocar o target sem trocar a chave restauraria o AVD antigo.`

- [ ] **Step 3: Limpeza, depois do E2E**

Junto da limpeza do `pg_data/` (depois do passo `E2E no emulador Android`, antes do `upload-artifact`):

```yaml
      # Apaga as credenciais mesmo se o E2E falhar. Num runner hospedado o disco é descartado
      # ao fim do job, mas o passo mantém a regra verdadeira em qualquer runner (inclusive um
      # autohospedado no futuro) e tira o google-services.json e a chave do Gorush do workspace.
      - name: Remove as credenciais do FCM
        if: always()
        run: |
          ./scripts/ci/decode_secret_file.sh --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS
          ./scripts/ci/decode_secret_file.sh --cleanup-file apps/patient/android/app/google-services.json
          ./scripts/ci/decode_secret_file.sh --cleanup-file infra/docker/gorush/credentials/fcm-service-account.json
```

- [ ] **Step 4: Testes dos scripts no `workflow-lint`**

No job `workflow-lint`, depois do passo que roda `./scripts/qa/ci_invariants.sh`:

```yaml
      - name: Testes dos scripts de CI
        run: |
          ./scripts/ci/decode_secret_file_test.sh
          ./scripts/qa/ci_push_e2e_test.sh
          ./scripts/qa/ci_invariants_fcm_test.sh
```

(`workflow-lint` é um dos 8 checks obrigatórios e já tem `python3` e PyYAML; os testes precisam só de bash, coreutils e python3. O nome do job não muda.)

- [ ] **Step 5: Rodar o guarda, os testes e o actionlint**

Run:
```bash
./scripts/qa/ci_invariants.sh
./scripts/ci/decode_secret_file_test.sh
./scripts/qa/ci_push_e2e_test.sh
./scripts/qa/ci_invariants_fcm_test.sh
docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color; echo actionlint_rc=$?
```
Expected: `ok: 9 grupos de invariantes do CI`; `OK — decode_secret_file.sh`; `OK — ci_push_e2e.sh`; `OK — invariantes das credenciais do FCM` (as 12 mutações reprovadas e o intacto aprovado); `actionlint_rc=0` sem saída. Se o actionlint acusar `shellcheck` em algum `run:`, corrija o trecho do YAML.

- [ ] **Step 6: Ensaiar os passos como o runner os executa, com credenciais FALSAS**

```bash
T="$(mktemp -d)"; export RUNNER_TEMP="$T" GITHUB_ENV="$T/env" GITHUB_ACTIONS=true
FCM_CREDENTIALS_BASE64="$(printf '{"type":"service_account","client_email":"x@p","private_key":"FAKE"}' | base64 -w0)" \
  ./scripts/ci/decode_secret_file.sh --env FCM_CREDENTIALS_BASE64 --kind service_account --temp-export GOOGLE_APPLICATION_CREDENTIALS
GOOGLE_SERVICES_JSON_BASE64="$(printf '{"project_info":{"project_id":"p"},"client":[{"client_info":{"android_client_info":{"package_name":"br.com.prismrr.sinalacs.patient"}}}]}' | base64 -w0)" \
  ./scripts/ci/decode_secret_file.sh --env GOOGLE_SERVICES_JSON_BASE64 --kind google_services --package br.com.prismrr.sinalacs.patient --to "$T/ws/google-services.json"
cut -c1-60 "$T/env"; ls -l "$T/ws/google-services.json" | cut -c1-10
unset GITHUB_ACTIONS RUNNER_TEMP GITHUB_ENV
```
Expected: duas linhas `::notice`, `GOOGLE_APPLICATION_CREDENTIALS=…/secret.XXXXXX.json` em `$T/env` e modo `-rw-------`. **Não use `--to apps/patient/android/app/google-services.json` neste ensaio**: como `GITHUB_ACTIONS=true` foi exportado de propósito, o script sobrescreveria o arquivo real do dev; por isso o destino é `$T`.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(android-e2e): decodifica as credenciais do FCM, usa o emulador com Play Services e roda o push e2e

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Documentação e prova no runner real

**Files:**
- Modify: `infra/docker/gorush/README.md` (seção nova "Na CI")
- Modify: `CLAUDE.md` (bullet do CI)
- Modify: `PROGRESS.md` (seção curta datada)

**Interfaces:**
- Consumes: Tasks 1–4 commitadas.
- Produces: documentação e a prova de que o push e2e roda num runner de verdade (depende de ações que o usuário precisa autorizar).

- [ ] **Step 1: Documentar**

- `infra/docker/gorush/README.md`, seção nova:

```markdown
## Na CI (GitHub Actions)

O job `android-e2e` usa dois secrets, cada um o arquivo em base64 (`base64 -w0 arquivo`):

| Secret | Arquivo | Onde vai no runner |
|---|---|---|
| `FCM_CREDENTIALS_BASE64` | `fcm-service-account.json` | arquivo `0600` em `$RUNNER_TEMP`; `GOOGLE_APPLICATION_CREDENTIALS` aponta para ele; `ci_push_e2e.sh` o instala em `infra/docker/gorush/credentials/` (o que o Gorush monta) |
| `GOOGLE_SERVICES_JSON_BASE64` | `google-services.json` | `apps/patient/android/app/` (o build do paciente o procura ali) |

Com os dois, o job roda o `push_e2e.sh` (caminho feliz) depois do smoke: o aviso do ACS chega
à bandeja do emulador pelo Gorush e FCM reais. Sem eles (PR de fork, secret apagado) os passos
só avisam e o job roda como antes. O emulador do CI usa a imagem `google_apis` (Play Services):
a imagem padrão da action é AOSP e o FCM não entrega token nela.

Os arquivos são apagados por um passo `if: always()`; `scripts/ci/decode_secret_file.sh` nunca
imprime o conteúdo e não sobrescreve nem apaga arquivos de um desenvolvedor fora do CI.
```

- `CLAUDE.md`, no bullet do CI: acrescentar que `workflow-lint` também roda `scripts/ci/decode_secret_file_test.sh`, `scripts/qa/ci_push_e2e_test.sh` e `scripts/qa/ci_invariants_fcm_test.sh`, e que o `ci_invariants.sh` falha quando `FCM_CREDENTIALS_BASE64`/`GOOGLE_SERVICES_JSON_BASE64` aparecem dentro de um `run:` ou no `env:` do job, quando uma decodificação vem depois do E2E, quando falta o passo `if: always()` de limpeza, quando o emulador perde o `target: google_apis` ou quando a chave do cache do AVD não o contém.
- `PROGRESS.md`: seção "Credenciais do FCM e Gorush no CI (2026-09-30)" com o que foi feito, os testes, e o limite da nota 3 (a imagem `google_apis` só é provada pelo primeiro run no runner).

- [ ] **Step 2: Conferir links e guarda**

Run: `./scripts/qa/check_documentation_links.sh; ./scripts/qa/ci_invariants.sh`
Expected: ambos verdes.

- [ ] **Step 3: Commit**

```bash
git add infra/docker/gorush/README.md CLAUDE.md PROGRESS.md
git commit -m "docs: credenciais do FCM e push e2e no CI (secrets, destinos e o que o runner prova)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: PARAR e pedir autorização antes de qualquer efeito externo**

Não execute sem um "sim" explícito do usuário para cada item:

1. `gh secret list` (só lê nomes): conferir que `FCM_CREDENTIALS_BASE64` e `GOOGLE_SERVICES_JSON_BASE64` existem. Não imprime valores.
2. `git push -u origin fix/patient` (a branch nunca foi publicada).
3. `gh workflow run CI --ref fix/patient` e `gh run watch`.

Resultado esperado no log do job `android-e2e`:
- **Decodifica a credencial do FCM** e **Decodifica o google-services.json**: verdes, com `::notice … decodificado em …`. **Nenhuma** linha com o conteúdo: procure `private_key`, `BEGIN` e `api_key` no log (zero ocorrências).
- O boot do emulador `google_apis` (regenera o AVD na 1ª vez) e o smoke passando como antes.
- O `push_e2e.sh` terminando com `OK — o aviso chegou ao emulador`.
- **Remove as credenciais do FCM**: verde ao final.
- Num PR de fork (ou com um secret ausente): `::notice … ausente`, `push e2e pulado`, job verde.

**Se o push falhar no runner** (diagnóstico antes de mexer): (a) `getToken()` sem token → troque `target: google_apis` por `google_apis_playstore` nos dois passos da action e na chave do cache (e ajuste `TARGET_EMULADOR` no guarda e a chave na mutação de teste), repita; (b) `FALTA … fcm-service-account.json`/modo → o `install` do `ci_push_e2e.sh` não rodou: confira `GOOGLE_APPLICATION_CREDENTIALS` no log; (c) `project_id difere` → os dois secrets são de projetos Firebase diferentes; (d) timeout do job → o push adiciona ~6 min; se o job se aproximar dos 60 min, suba `timeout-minutes` (decisão do usuário).

- [ ] **Step 5: Registrar o resultado**

Se a prova no runner foi feita, acrescente o número do run ao `PROGRESS.md` e faça um commit `docs:` curto. Se não foi, registre "prova no runner real pendente: precisa do push da branch" na mesma seção.

---

## Fora do escopo

- Rodar o push e2e com `--negativos` ou com `--e2e-db` no CI (mais ~3 min e mais peças: relé do OTP e o `postgres-test`). O caminho feliz contra a stack de desenvolvimento é o que entra.
- Restringir o passo a branches protegidas ou a um **Environment** do GitHub com revisores: hoje qualquer PR de dentro do repositório recebe os secrets e um autor com permissão de escrita poderia, editando o `ci.yml`, imprimi-los. O `ci_invariants.sh` protege contra regressão acidental, não contra um autor mal-intencionado. Decisão de política do repositório.
- Rotação da chave da conta de serviço e a cópia em `/opt/apps_android/` (modo 644) fora do repositório.
- iOS/APNs e aparelho físico.

## Self-review

- **Cobertura do pedido:** os dois secrets decodificados por base64 para arquivos no runner (Tasks 1, 4); `GOOGLE_APPLICATION_CREDENTIALS` definida e **consumida** pelo `ci_push_e2e.sh` (Tasks 1, 2, 4); Gorush ligado no CI com o FCM real (Tasks 2, 4); `google-services.json` no lugar onde o build do paciente o procura (Tasks 1, 4); emulador com Play Services (Tasks 3, 4).
- **Placeholders:** nenhum; todo passo de código traz o código e todo comando traz o resultado esperado.
- **Consistência de nomes:** `decode_secret_file.sh` com `--env/--kind/--temp-export/--to/--package/--cleanup-temp/--cleanup-file`, `ci_push_e2e.sh`, `PUSH_E2E_SCRIPT`, `Decodifica a credencial do FCM`, `Decodifica o google-services.json`, `Remove as credenciais do FCM`, `check_credenciais_fcm`, `CI_WORKFLOW_PATH`, `target: google_apis` e `avd-36-google_apis-x86_64-pixel_7-ubuntu-24.04` são os mesmos nas Tasks 1–5; a contagem `9 grupos` vem de acrescentar um item a `CHECKS` (hoje 8).
- **Ordem de commits:** a Task 3 deixa o guarda vermelho de propósito até a Task 4; o plano manda não dar push entre as duas.
- **Riscos anotados:** a imagem `google_apis` não foi exercitada localmente (nota 3, com a saída `google_apis_playstore`); o autor com escrita que exfiltra o secret (Fora do escopo); o tempo do job (Task 5, item d).
