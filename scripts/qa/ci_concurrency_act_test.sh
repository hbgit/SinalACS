#!/usr/bin/env bash
#
# Teste hermético de scripts/qa/ci_concurrency_act.sh (issue #63): sem
# Docker, sem act real e sem rede. act, docker e python3 são stubs no início
# do PATH; o git é o real, mas com uma configuração global hostil (assinatura
# obrigatória com um gpg que falha e um hook pre-commit que recusa tudo),
# para provar que a sonda não herda a configuração de quem roda.
#
#   ./scripts/qa/ci_concurrency_act_test.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
alvo="$repo_root/scripts/qa/ci_concurrency_act.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

falhas=0
ok()    { echo "  ok    — $1"; }
falha() { echo "  FALHA — $1" >&2; falhas=$((falhas + 1)); }

python_real="$(command -v python3)"
stubs="$tmp_dir/bin"
mkdir -p "$stubs" "$tmp_dir/hooks"

# act falso: devolve um grupo coerente com o evento e o payload, imitando a
# expressão real; ACT_STUB_MODO=mudo não imprime GRUPO= (act quebrado).
cat > "$stubs/act" <<'SH'
#!/usr/bin/env bash
evento="$1"; payload=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --eventpath ]]; then payload="$2"; fi
  shift
done
echo "[act-stub] evento=$evento payload=$payload"
if [[ "${ACT_STUB_MODO:-}" == mudo ]]; then exit 0; fi
num="$(sed -n 's/.*"number":\([0-9]*\).*/\1/p' "$payload")"
ref="$(sed -n 's/.*"ref":"\([^"]*\)".*/\1/p' "$payload")"
if [[ -n "$num" ]]; then
  echo "[sonda/sonda]   | GRUPO=ci-$evento-$num"
else
  echo "[sonda/sonda]   | GRUPO=ci-$evento-$ref-abc123"
fi
SH

# docker falso: `info` responde; `image inspect` falha com DOCKER_STUB_SEM_IMAGEM=1.
cat > "$stubs/docker" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == image && "${DOCKER_STUB_SEM_IMAGEM:-0}" == 1 ]]; then exit 1; fi
exit 0
SH

# python3 falso: com PY_STUB_SEM_YAML=1 qualquer `import yaml` falha.
cat > "$stubs/python3" <<SH
#!/usr/bin/env bash
if [[ "\${PY_STUB_SEM_YAML:-0}" == 1 ]]; then
  echo "ModuleNotFoundError: No module named 'yaml'" >&2; exit 1
fi
exec "$python_real" "\$@"
SH

printf '#!/bin/sh\necho "hook do usuário recusou" >&2\nexit 1\n' > "$tmp_dir/hooks/pre-commit"
chmod +x "$stubs"/* "$tmp_dir/hooks/pre-commit"

cat > "$tmp_dir/gitconfig-hostil" <<CFG
[commit]
	gpgsign = true
[gpg]
	program = false
[core]
	hooksPath = $tmp_dir/hooks
CFG

# roda [VAR=valor ...] → preenche $saida (stdout+stderr) e $codigo.
roda() {
  saida="$(env PATH="$stubs:$PATH" GIT_CONFIG_GLOBAL="$tmp_dir/gitconfig-hostil" \
    GIT_CONFIG_NOSYSTEM=1 "$@" "$alvo" 2>&1)"
  codigo=$?
}

echo '== caminho feliz com git hostil: a sonda ignora gpgsign e hooks do usuário =='
roda
if [[ "$codigo" == 0 ]] && grep -qF 'OK —' <<<"$saida"; then
  ok 'exit 0 e as cinco asserções conferem'
else
  falha "esperava exit 0 — exit=$codigo, saída: $saida"
fi
if grep -qE 'hook do usuário recusou|gpg failed' <<<"$saida"; then
  falha "a sonda herdou a configuração do usuário — saída: $saida"
else
  ok 'nenhum hook nem gpg do usuário rodou'
fi

echo '== sem PyYAML: falta de pré-requisito é exit 2 =='
roda PY_STUB_SEM_YAML=1
if [[ "$codigo" == 2 ]] && grep -qF 'PyYAML' <<<"$saida"; then
  ok 'exit 2 e a mensagem cita PyYAML'
else
  falha "esperava exit 2 citando PyYAML — exit=$codigo, saída: $saida"
fi

echo '== sem a imagem do runner: exit 2, com o comando para baixá-la =='
roda DOCKER_STUB_SEM_IMAGEM=1
if [[ "$codigo" == 2 ]] && grep -qF 'docker pull catthehacker/ubuntu:act-24.04' <<<"$saida"; then
  ok 'exit 2 e a mensagem diz como baixar a imagem'
else
  falha "esperava exit 2 com 'docker pull' — exit=$codigo, saída: $saida"
fi

echo '== commit da sonda impossível: exit 2, sem seguir para o act =='
# Uma data de autor inválida faz só o commit falhar (init e add passam), por
# um motivo que a sonda não neutraliza; o script tem de parar ali.
roda GIT_AUTHOR_DATE='data inválida'
if [[ "$codigo" == 2 ]] && grep -qF 'commit da sonda' <<<"$saida" && ! grep -qF '[act-stub]' <<<"$saida"; then
  ok 'exit 2 e o act não foi chamado'
else
  falha "esperava exit 2 antes do act — exit=$codigo, saída: $saida"
fi

echo '== act sem saída útil: exit 1 e o log fica no disco =='
roda ACT_STUB_MODO=mudo
dir_logs="$(sed -n 's/.*logs do act mantidos em \(.*\)$/\1/p' <<<"$saida" | tail -1)"
if [[ "$codigo" == 1 && -n "$dir_logs" && -d "$dir_logs" ]]; then
  n="$(find "$dir_logs" -name '*.log' | wc -l)"
  if [[ "$n" == 7 ]] && grep -qF '[act-stub]' "$dir_logs"/*.log; then
    ok 'exit 1, 7 logs preservados com a saída do act'
  else
    falha "esperava 7 logs com a saída do act em $dir_logs, achei $n"
  fi
  rm -rf "$(dirname "$dir_logs")"
else
  falha "esperava exit 1 e um diretório de logs — exit=$codigo, saída: $saida"
fi

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — ci_concurrency_act.sh sai com o código certo, guarda o log e ignora o git do usuário (issue #63).'
else
  echo "FALHOU — $falhas caso(s)." >&2
fi
[[ "$falhas" -eq 0 ]]
