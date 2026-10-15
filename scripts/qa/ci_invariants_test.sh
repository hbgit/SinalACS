#!/usr/bin/env bash
#
# Controles positivo e negativo de checagens de scripts/qa/ci_invariants.sh:
# as três da issue #20 (um check obrigatório que passa verde sem ter rodado
# por causa de continue-on-error, strategy.matrix ou needs: apontando para um
# job fora de CHECKS_OBRIGATORIOS) e as do concurrency.group das issues #23 e
# #63 (ref e SHA no ramo de push/dispatch, número do PR no outro, evento no
# prefixo, e as limitações conhecidas da guarda por substring).
#
# Por que existe: sem fixture sintética, as três checagens só seriam
# exercitadas contra o .github/workflows/ci.yml real do momento — que, por
# não ter nenhum dos três defeitos, nunca provaria que a checagem DETECTA o
# que promete detectar, só que ela não acende à toa no arquivo de hoje. Cada
# caso aqui tem o par positivo (o defeito existe, a mensagem tem de aparecer)
# e negativo (uma variação vizinha SEM o defeito, a mensagem não pode
# aparecer) — o mesmo padrão de scripts/qa/tls_invariants.sh.
#
#   ./scripts/qa/ci_invariants_test.sh
#
# Não precisa de rede nem da stack; só python3 com PyYAML (mesma dependência
# do ci_invariants.sh, que este script chama via CI_INVARIANTS_WORKFLOW para
# apontar cada fixture em vez do .github/workflows/ci.yml real).
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

falhas=0
ok()    { echo "  ok    — $1"; }
falha() { echo "  FALHA — $1" >&2; falhas=$((falhas + 1)); }

# Roda o ci_invariants.sh contra a fixture $1 e devolve o stderr em $saida.
# Não usa `set -e`: um exit 1 é o resultado esperado sempre que a fixture tem
# um defeito de propósito.
rodar() {
  local fixture="$1"
  saida="$(CI_INVARIANTS_WORKFLOW="$fixture" "$repo_root/scripts/qa/ci_invariants.sh" 2>&1 1>/dev/null)"
}

# Espera que $trecho apareça na saída da fixture $1.
espera_falha() {
  local descricao="$1" fixture="$2" trecho="$3"
  rodar "$fixture"
  if printf '%s' "$saida" | grep -qF -- "$trecho"; then
    ok "$descricao: a checagem acusa (\"$trecho\")"
  else
    falha "$descricao: esperava \"$trecho\" na saída, não apareceu — saída: $saida"
  fi
}

# Espera que $trecho NÃO apareça na saída da fixture $1 — o controle
# negativo: prova que a checagem não dispara por acidente numa variação
# vizinha sem o defeito.
espera_ok() {
  local descricao="$1" fixture="$2" trecho="$3"
  rodar "$fixture"
  if printf '%s' "$saida" | grep -qF -- "$trecho"; then
    falha "$descricao: não devia acusar (\"$trecho\") e acusou — saída: $saida"
  else
    ok "$descricao: a checagem não dispara por acidente"
  fi
}

# Grupos de concorrência (issue #23). GRUPO_NOVO é o esperado: número do PR no
# ramo da esquerda do `||`, ref e SHA no da direita. GRUPO_ANTIGO é o que
# existia antes: só o SHA no ramo de push/dispatch.
GRUPO_NOVO='ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || format('"'"'{0}-{1}'"'"', github.ref, github.sha) }}'
GRUPO_ANTIGO='ci-${{ github.event_name }}-${{ github.event_name == '"'"'pull_request'"'"' && github.event.pull_request.number || github.sha }}'

# Workflow mínimo que passa por TODAS as outras checagens do ci_invariants.sh
# (jobs documentados, gatilhos, concurrency, versões de ação, runner, limpeza
# do pg_data, credenciais do FCM) — assim, o único jeito de uma fixture
# derivada daqui falhar por causa das checagens desta issue é ela mesma ter o
# defeito que existe para provar. $1, se dado, substitui a linha `    # EXTRA`
# dentro do job admin-app (indentação de 4 espaços já incluída no marcador).
workflow_base() {
  local extra_admin_app="${1:-}"
  local grupo="${GRUPO_CONCORRENCIA:-$GRUPO_NOVO}"
  cat <<YAML
on:
  push:
    branches: [main, develop]
  pull_request: {}
  workflow_dispatch: {}
concurrency:
  group: ${grupo}
  cancel-in-progress: true
jobs:
  workflow-lint:
    runs-on: ubuntu-24.04
  serverpod-backend:
    runs-on: ubuntu-24.04
  backend-docker-build:
    runs-on: ubuntu-24.04
  patient-app:
    runs-on: ubuntu-24.04
  acs-app:
    runs-on: ubuntu-24.04
  admin-app:
    runs-on: ubuntu-24.04
${extra_admin_app}
  coverage-report:
    runs-on: ubuntu-24.04
  android-e2e:
    runs-on: ubuntu-24.04
    steps:
      - name: Decodifica a credencial do FCM
        env:
          FCM_CREDENTIALS_BASE64: \${{ secrets.FCM_CREDENTIALS_BASE64 }}
        run: ./scripts/ci/decode_secret_file.sh --env FCM_CREDENTIALS_BASE64 --kind service_account --temp-export GOOGLE_APPLICATION_CREDENTIALS
      - name: Decodifica o google-services.json
        env:
          GOOGLE_SERVICES_JSON_BASE64: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
        run: ./scripts/ci/decode_secret_file.sh --env GOOGLE_SERVICES_JSON_BASE64 --kind google_services --to apps/patient/android/app/google-services.json
      - name: E2E no emulador Android
        uses: reactivecircus/android-emulator-runner@v2
        with:
          target: google_apis
          script: "true"
      - name: Remove as credenciais do FCM
        if: always()
        run: |
          ./scripts/ci/decode_secret_file.sh --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS
          ./scripts/ci/decode_secret_file.sh --cleanup-file apps/patient/android/app/google-services.json
          ./scripts/ci/decode_secret_file.sh --cleanup-file infra/docker/gorush/credentials/fcm-service-account.json
      - name: Remove pg_data/ do workspace
        if: always()
        run: sudo rm -rf pg_data
  admin-android-build:
    runs-on: ubuntu-24.04
YAML
}

escreve() {
  # `local nome=... caminho="...$nome..."` na mesma linha falharia sob
  # `set -u`: bash expande o lado direito de TODAS as atribuições de um
  # `local` antes de declarar qualquer uma delas, então `$nome` ainda não
  # existiria quando `$caminho` fosse montado.
  local nome="$1"
  local extra="$2"
  local caminho="$tmp_dir/$nome.yml"
  workflow_base "$extra" > "$caminho"
  printf '%s' "$caminho"
}

escreve_grupo() {
  local nome="$1"
  local grupo="$2"
  local caminho="$tmp_dir/$nome.yml"
  GRUPO_CONCORRENCIA="$grupo" workflow_base '' > "$caminho"
  printf '%s' "$caminho"
}

echo '== Controle de base: a fixture limpa não deve acusar nada ='
base_fixture="$(escreve base '')"
rodar "$base_fixture"
if [[ -z "$saida" ]]; then
  ok 'a fixture base passa por todas as outras checagens sem ruído'
else
  falha "a fixture base deveria estar limpa e não está — saída: $saida"
fi

echo '== continue-on-error: true num check obrigatório vira sucesso mesmo falhando =='
espera_falha 'positivo' \
  "$(escreve continue_on_error_true '    continue-on-error: true')" \
  'admin-app (obrigatório) tem continue-on-error: true'
espera_ok 'negativo (continue-on-error: false, valor explícito)' \
  "$(escreve continue_on_error_false '    continue-on-error: false')" \
  'continue-on-error: true'

echo '== strategy.matrix num check obrigatório muda o nome do check =='
espera_falha 'positivo' \
  "$(escreve matrix '    strategy:
      matrix:
        flutter: ["3.44.8"]')" \
  'admin-app (obrigatório) tem strategy.matrix'
espera_ok 'negativo (strategy sem matrix, só fail-fast)' \
  "$(escreve strategy_sem_matrix '    strategy:
      fail-fast: true')" \
  'strategy.matrix'

echo '== needs: apontando para fora de CHECKS_OBRIGATORIOS esconde o job que falhou =='
espera_falha 'positivo (needs: android-e2e, não obrigatório)' \
  "$(escreve needs_fora '    needs: android-e2e')" \
  'admin-app (obrigatório) tem needs: android-e2e'
espera_ok 'negativo (needs: acs-app, também obrigatório)' \
  "$(escreve needs_dentro '    needs: acs-app')" \
  'admin-app (obrigatório) tem needs:'

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

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — as checagens de "verde sem rodar" (issue #20) e do grupo de concorrência (issues #23 e #63) conferem.'
else
  echo "FALHOU — $falhas asserção(ões) não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
