#!/usr/bin/env bash
#
# Login real do backoffice (staff) no emulador-5554, contra o BANCO DE TESTE.
#
#   ./scripts/qa/admin_login_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/admin_login_e2e.sh   # aparelho físico
#
# Sobe a stack de e2e (e2e_stack.sh: banco sinalacs_e2e, sem login de
# desenvolvimento), semeia fixtures sintéticas (inclui um administrador do
# backoffice SEM MFA, com matrícula e senha novas a cada execução), sobe o relé
# (que entrega a credencial do admin em /admin, uma única vez) e roda
# apps/admin/integration_test/admin_login_e2e.dart no emulador: senha errada,
# ativação da MFA pela tela, código errado e login com o código até o painel.
# Depois confere no banco de teste a conta de staff (TOTP ativado,
# passo registrado, tentativas zeradas). Nada é escrito no banco de desenvolvimento; o banco e o
# manifesto são apagados ao final.
#
# Os dados do painel seguem no MockAdminDataSource (#41): só o login é real.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$HOME/.pub-cache/bin"

dev="${DEVICE:-emulator-5554}"
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "aparelho $dev não encontrado (adb devices)"; exit 4; }

relay_pid=""
cleanup() {
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null || true
  rm -f .e2e/fixtures.json   # primeiro: tem a senha do admin, mesmo se o down falhar
  ./scripts/qa/e2e_stack.sh down >/dev/null 2>&1 \
    || echo 'aviso: e2e_stack.sh down falhou; o banco sinalacs_e2e pode ter sobrado' >&2
  echo 'A stack de desenvolvimento foi substituída pela de e2e: rode `docker compose up -d` para voltá-la.'
}
trap cleanup EXIT

if porta_ocupada 8765; then
  echo 'erro: a porta 8765 já está ocupada (relé antigo?). Encerre-o: pkill -f scripts/qa/otp_relay.py' >&2
  exit 1
fi

echo "== stack de e2e (banco de teste)"
./scripts/qa/e2e_stack.sh up
./scripts/qa/e2e_stack.sh seed
./scripts/dev/sync_dev_ca.sh >/dev/null 2>&1 || true
[[ -f apps/admin/assets/certs/dev_rpc_ca.crt ]] \
  || { echo 'erro: falta apps/admin/assets/certs/dev_rpc_ca.crt (./scripts/dev/sync_dev_ca.sh)' >&2; exit 1; }
adb -s "$dev" reverse tcp:8443 tcp:443 >/dev/null
adb -s "$dev" reverse tcp:8765 tcp:8765 >/dev/null

E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" python3 scripts/qa/otp_relay.py >/dev/null 2>&1 &
relay_pid=$!
for _ in $(seq 1 20); do
  curl -fs http://127.0.0.1:8765/now >/dev/null 2>&1 && break
  sleep 0.25
done
kill -0 "$relay_pid" 2>/dev/null || { echo 'erro: o relé não subiu' >&2; exit 1; }

staff_id="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['staff']['id'])")"

echo "== login do backoffice no emulador"
# `|| status=$?`: sob `set -e` + `pipefail` uma falha encerraria o script antes
# da mensagem; assim a mensagem sai e o `trap cleanup` continua rodando.
status=0
( cd apps/admin && flutter pub get >/dev/null && flutter test integration_test/admin_login_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ ) 2>&1 || status=$?
[[ "$status" -eq 0 ]] || { echo "erro: o login do backoffice no emulador falhou (código $status)" >&2; exit 1; }

echo "== conta de staff no banco de teste"
sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
igual 'TOTP ativado e passo registrado' 'true|true' \
  "select (\"totpEnabledAt\" is not null)::text || '|' || (\"totpLastStep\" is not null)::text from user_credentials where \"userId\"='$staff_id'"
igual 'tentativas falhas zeradas pelo login' 0 \
  "select \"failedAttempts\" from user_credentials where \"userId\"='$staff_id'"
echo 'OK — login real do backoffice contra o banco de teste'
