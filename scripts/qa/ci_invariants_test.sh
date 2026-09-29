#!/usr/bin/env bash
#
# Controles positivo e negativo das três checagens que a issue #20 pediu para
# scripts/qa/ci_invariants.sh: um check obrigatório que passa verde sem ter
# rodado por causa de continue-on-error, strategy.matrix ou needs: apontando
# para um job fora de CHECKS_OBRIGATORIOS.
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

# Workflow mínimo que passa por TODAS as outras checagens do ci_invariants.sh
# (jobs documentados, gatilhos, concurrency, versões de ação, runner, limpeza
# do pg_data) — assim, o único jeito de uma fixture derivada daqui falhar por
# causa das checagens desta issue é ela mesma ter o defeito que existe para
# provar. $1, se dado, substitui a linha `    # EXTRA` dentro do job
# admin-app (indentação de 4 espaços já incluída no marcador).
workflow_base() {
  local extra_admin_app="${1:-}"
  cat <<YAML
on:
  push:
    branches: [main, develop]
  pull_request: {}
  workflow_dispatch: {}
concurrency:
  group: ci-\${{ github.event_name }}-\${{ github.event.pull_request.number }}-\${{ github.sha }}
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
      - name: E2E no emulador Android
        run: "true"
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

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — as checagens de check obrigatório "verde sem rodar" (issue #20) conferem.'
else
  echo "FALHOU — $falhas asserção(ões) não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
