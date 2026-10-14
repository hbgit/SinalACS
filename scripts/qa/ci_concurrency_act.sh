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
# Precisa de act, docker, git, python3 com PyYAML e da imagem do runner já
# baixada (o act roda com --pull=false). Sai com 2 se faltar algo, 1 se uma
# asserção não conferir — nesse caso os logs do act ficam no disco e o
# caminho é impresso. Testado sem Docker por ci_concurrency_act_test.sh.
set -uo pipefail

ACT_TESTADO='0.2.89'
IMAGEM_RUNNER='ubuntu-24.04=catthehacker/ubuntu:act-24.04'
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

for bin in act docker git python3; do
  command -v "$bin" >/dev/null || { echo "faltando: $bin (testado com act $ACT_TESTADO)" >&2; exit 2; }
done
docker info >/dev/null 2>&1 || { echo 'docker não está acessível' >&2; exit 2; }
python3 -I -c 'import yaml' 2>/dev/null || {
  echo 'faltando: PyYAML (python3-yaml no apt, ou pip install pyyaml)' >&2; exit 2; }
imagem="${IMAGEM_RUNNER#*=}"
docker image inspect "$imagem" >/dev/null 2>&1 || {
  echo "faltando a imagem do runner: docker pull $imagem" >&2; exit 2; }

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
# A sonda não herda assinatura nem hooks de quem roda: um gpgsign=true global
# ou um core.hooksPath com pre-commit derrubaria o commit, e um post-checkout
# rodaria a cada `switch`. Config local vence a global.
git -C "$sonda" config commit.gpgsign false
git -C "$sonda" config core.hooksPath /dev/null
git -C "$sonda" add -A
git -C "$sonda" -c user.name=t -c user.email=t@t commit -q -m sonda || {
  echo 'não consegui criar o commit da sonda' >&2; exit 2; }
git -C "$sonda" branch develop

# Payload de PR simulado: só o número importa para o grupo.
payload_pr() {
  printf '{"action":"synchronize","number":%s,"pull_request":{"number":%s}}' "$1" "$1" > "$tmp_dir/pr$1.json"
  printf '%s' "$tmp_dir/pr$1.json"
}

# O act NÃO deriva github.ref da branch em checkout: ele lê o campo `ref` do
# payload e, sem ele, cai na branch padrão (main). O GitHub real manda `ref` em
# push e dispatch, então o payload simulado também manda.
payload_ref() {
  printf '{"ref":"refs/heads/%s"}' "$1" > "$tmp_dir/ref-${1//\//_}.json"
  printf '%s' "$tmp_dir/ref-${1//\//_}.json"
}

# roda_act <branch> <evento> <payload>  → imprime o grupo resolvido. A saída
# inteira do act vai para um log por chamada, mantido se algo falhar.
roda_act() {
  local log="$tmp_dir/logs/$1-$2-$(basename "$3" .json).log"
  git -C "$sonda" switch -q "$1"
  ( cd "$sonda" && act "$2" -W .github/workflows/sonda.yml --eventpath "$3" \
      -P "$IMAGEM_RUNNER" --pull=false ) > "$log" 2>&1
  sed -n 's/.*| GRUPO=\(.*\)$/\1/p' "$log" | tail -1
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

push_main="$(roda_act main push "$(payload_ref main)")"
push_dev="$(roda_act develop push "$(payload_ref develop)")"
disp_main="$(roda_act main workflow_dispatch "$(payload_ref main)")"
disp_dev="$(roda_act develop workflow_dispatch "$(payload_ref develop)")"
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
  manter_logs=1
  echo "FALHOU — $falhas asserção(ões) não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
