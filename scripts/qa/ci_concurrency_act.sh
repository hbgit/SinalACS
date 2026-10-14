#!/usr/bin/env bash
#
# Avalia o concurrency.group REAL do ci.yml com o `act`, para push,
# pull_request e workflow_dispatch (issue #23).
#
# O que prova: a expressão avalia para grupos distintos entre main e develop
# no mesmo SHA e para o mesmo grupo em dois pushes no mesmo PR.
# O que NÃO prova: o act não implementa `concurrency` nem `cancel-in-progress`;
# o cancelamento de fato só se vê no GitHub (ver o plano da issue #23,
# Tarefa 7).
#
# A expressão é lida do ci.yml e colada num workflow-sonda de um job; assim a
# sonda nunca deriva do workflow real. Roda num repositório git descartável com
# main e develop no MESMO commit, então github.ref e github.sha vêm do git.
#
#   ./scripts/qa/ci_concurrency_act.sh
#
# Precisa de act, docker, git e python3 com PyYAML. Sai com 2 se faltar algo.
set -uo pipefail

ACT_TESTADO='0.2.89'
IMAGEM_RUNNER='ubuntu-24.04=catthehacker/ubuntu:act-24.04'
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for bin in act docker git python3; do
  command -v "$bin" >/dev/null || { echo "faltando: $bin (testado com act $ACT_TESTADO)" >&2; exit 2; }
done
docker info >/dev/null 2>&1 || { echo 'docker não está acessível' >&2; exit 2; }

grupo="$(python3 -I - "$repo_root/.github/workflows/ci.yml" <<'PY'
import sys, yaml
print(yaml.safe_load(open(sys.argv[1]))['concurrency']['group'])
PY
)"
[[ -n "$grupo" ]] || { echo 'não achei concurrency.group no ci.yml' >&2; exit 1; }

sonda="$tmp_dir/repo"
mkdir -p "$sonda/.github/workflows"
cat > "$sonda/.github/workflows/sonda.yml" <<YAML
on:
  push:
  pull_request:
  workflow_dispatch:
jobs:
  sonda:
    runs-on: ubuntu-24.04
    steps:
      - run: echo "GRUPO=${grupo}"
YAML
git -C "$sonda" init -q -b main
git -C "$sonda" add -A
git -C "$sonda" -c user.name=t -c user.email=t@t commit -q -m sonda
git -C "$sonda" branch develop

# Payload de PR simulado: só o número importa para o grupo.
payload_pr() {
  printf '{"action":"synchronize","number":%s,"pull_request":{"number":%s}}' "$1" "$1" > "$tmp_dir/pr$1.json"
  printf '%s' "$tmp_dir/pr$1.json"
}
echo '{}' > "$tmp_dir/vazio.json"

# roda_act <branch> <evento> <payload>  → imprime o grupo resolvido
roda_act() {
  git -C "$sonda" switch -q "$1"
  ( cd "$sonda" && act "$2" -W .github/workflows/sonda.yml --eventpath "$3" \
      -P "$IMAGEM_RUNNER" --pull=false 2>&1 ) \
    | sed -n 's/.*| GRUPO=\(.*\)$/\1/p' | tail -1
}

falhas=0
confere() { # descrição, 1=iguais|0=distintos, a, b
  local d="$1" igual="$2" a="$3" b="$4"
  if [[ -z "$a" || -z "$b" ]]; then
    echo "  FALHA — $d: sem saída do act" >&2; falhas=$((falhas + 1)); return
  fi
  if { [[ "$igual" == 1 ]] && [[ "$a" == "$b" ]]; } || { [[ "$igual" == 0 ]] && [[ "$a" != "$b" ]]; }; then
    echo "  ok    — $d ($a | $b)"
  else
    echo "  FALHA — $d: '$a' vs '$b'" >&2; falhas=$((falhas + 1))
  fi
}

push_main="$(roda_act main push "$tmp_dir/vazio.json")"
push_dev="$(roda_act develop push "$tmp_dir/vazio.json")"
disp_main="$(roda_act main workflow_dispatch "$tmp_dir/vazio.json")"
disp_dev="$(roda_act develop workflow_dispatch "$tmp_dir/vazio.json")"
pr7_a="$(roda_act develop pull_request "$(payload_pr 7)")"
pr7_b="$(roda_act main pull_request "$(payload_pr 7)")"
pr8="$(roda_act develop pull_request "$(payload_pr 8)")"

echo '== grupos resolvidos pelo act (issue #23) =='
confere 'push: main e develop no mesmo SHA têm grupos DISTINTOS' 0 "$push_main" "$push_dev"
confere 'dispatch: main e develop no mesmo SHA têm grupos DISTINTOS' 0 "$disp_main" "$disp_dev"
confere 'PR 7 vindo de branches diferentes cai no MESMO grupo (cancela o obsoleto)' 1 "$pr7_a" "$pr7_b"
confere 'PR 7 e PR 8 têm grupos distintos' 0 "$pr7_a" "$pr8"
confere 'push e dispatch na mesma branch têm grupos distintos (event_name no prefixo)' 0 "$push_main" "$disp_main"

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — o grupo real do ci.yml se comporta como a issue #23 pede.'
else
  echo "FALHOU — $falhas asserção(ões) não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
