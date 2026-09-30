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

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — ci_push_e2e.sh" || { echo "$n asserção(ões) falharam"; exit 1; }
