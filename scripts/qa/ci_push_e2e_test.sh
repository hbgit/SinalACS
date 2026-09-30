#!/usr/bin/env bash
# ci_push_e2e.sh: pula sem credenciais; com elas, instala a chave e chama o push e2e.
set -uo pipefail
cd "$(dirname "$0")/../.."
orig="$PWD/scripts/qa/ci_push_e2e.sh"
repo="$PWD"
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
echo "${GORUSH_UID:-}:${GORUSH_GID:-}" >"$(dirname "$0")/uid_gid"
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
afirma "o container do Gorush roda com o uid/gid do host (a chave 0600 é do usuário do runner)" '[[ "$(cat "$R/uid_gid")" == "$(id -u):$(id -g)" ]]'
afirma "o docker-compose.yml usa GORUSH_UID/GORUSH_GID no serviço gorush" 'sed -n "/^  gorush:/,/^  serverpod:/p" "$repo/docker-compose.yml" | grep -q "GORUSH_UID" && sed -n "/^  gorush:/,/^  serverpod:/p" "$repo/docker-compose.yml" | grep -q "GORUSH_GID"'
afirma "a saída não imprime o conteúdo da chave" '! grep -q "FAKE" <<<"$out"'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json" STUB_RC=7
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "o exit do push e2e é propagado (7)" '[[ $rc -eq 7 ]]'

# ---- M3: uma falha do `docker compose down` no trap não pode trocar o código de saída ----------
stub="$raiz/stub_bin"; mkdir -p "$stub"; printf '#!/bin/sh\nexit 1\n' >"$stub/docker"; chmod +x "$stub/docker"
linha_trap="$(grep '^trap ' "$repo/scripts/qa/run_android_e2e.sh")"
PATH="$stub:$PATH" bash -c "set -e; $linha_trap; exit 7"; rc=$?
afirma "M3 o trap de down que falha preserva o exit do script (7)" '[[ $rc -eq 7 ]]'
PATH="$stub:$PATH" bash -c "set -e; $linha_trap; exit 0"; rc=$?
afirma "M3 o trap de down que falha não transforma sucesso em falha" '[[ $rc -eq 0 ]]'

# ---- M8: o cabeçalho do push_e2e.sh não pode mais dizer que NÃO roda na CI ----------------------
afirma "M8 o cabeçalho do push_e2e.sh não afirma 'NÃO roda na CI'" '! sed -n 1,25p "$repo/scripts/qa/push_e2e.sh" | grep -q "NÃO roda na CI"'

# ---- M9: no CI o log é público — o project_id não pode ser impresso ------------------------------
guarda="$raiz/guarda.py"
sed -n "/^python3 - <<'PYEOF'/,/^PYEOF/p" "$repo/scripts/qa/push_e2e.sh" | sed '1d;$d' >"$guarda"
mkdir -p "$raiz/g/infra/docker/gorush/credentials" "$raiz/g/apps/patient/android/app"
echo '{"type":"service_account","project_id":"proj-secreto-123","client_email":"x@y","private_key":"k"}' >"$raiz/g/infra/docker/gorush/credentials/fcm-service-account.json"
echo '{"project_info":{"project_id":"proj-secreto-123"},"client":[{"client_info":{"android_client_info":{"package_name":"br.com.prismrr.sinalacs.patient"}}}]}' >"$raiz/g/apps/patient/android/app/google-services.json"
out_ci="$(cd "$raiz/g" && GITHUB_ACTIONS=true python3 "$guarda" 2>&1)"; rc_ci=$?
out_local="$(cd "$raiz/g" && env -u GITHUB_ACTIONS python3 "$guarda" 2>&1)"
afirma "M9 a guarda roda com chaves válidas (exit 0)" '[[ $rc_ci -eq 0 ]]'
afirma "M9 no CI o project_id não é impresso" '! grep -q "proj-secreto-123" <<<"$out_ci" && grep -q "chave ok" <<<"$out_ci"'
afirma "M9 fora do CI o project_id continua aparecendo (útil ao dev)" 'grep -q "proj-secreto-123" <<<"$out_local"'

# ---- M10: parar o push e2e tem de matar o `flutter test` (neto do subshell), não só o subshell --
fn="$(sed -n '/^parar_arvore()/,/^}/p' "$repo/scripts/qa/push_e2e.sh")"
afirma "M10 push_e2e.sh define parar_arvore e liga o controle de jobs (set -m)" '[[ -n "$fn" ]] && grep -q "^set -m" "$repo/scripts/qa/push_e2e.sh"'
marca="$raiz/neto.pid"
bash -c "set -m; $fn
( sh -c 'echo \$\$ >$marca; exec sleep 300' & wait ) &
hold=\$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s $marca ] && break; sleep 0.2; done
parar_arvore \$hold
sleep 0.5" 2>/dev/null
neto="$(cat "$marca" 2>/dev/null || echo 0)"
afirma "M10 o neto (flutter test) morre junto" '[[ "$neto" != 0 ]] && ! kill -0 "$neto" 2>/dev/null'
kill "$neto" 2>/dev/null || true

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — ci_push_e2e.sh" || { echo "$n asserção(ões) falharam"; exit 1; }
