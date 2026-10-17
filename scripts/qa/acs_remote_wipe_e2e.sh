#!/usr/bin/env bash
#
# Limpeza remota do aparelho do ACS (issue #81) no emulador-5554, contra o
# BANCO DE TESTE: o aparelho é limpo com uma visita NÃO enviada e o painel
# aberto.
#
#   ./scripts/qa/acs_remote_wipe_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/acs_remote_wipe_e2e.sh   # aparelho físico
#
# O teste (apps/acs/integration_test/remote_wipe_e2e.dart) entra como o ACS da
# fixture, registra uma visita com o envio de visitas fora do ar (decorator de
# `AcsBackend`: só os caminhos de envio; login e lista seguem o servidor real) e
# fica no formulário. Por um `Client` próprio, o coordenador da fixture (relé
# `/coordenador`, ativação da MFA e TOTP) pede a limpeza do aparelho. A volta do
# segundo plano dispara a consulta e o aparelho é limpo: banco, chave do
# SQLCipher, tokens de envio e id da instalação. "Entrar de novo" abre o painel
# com o id novo. Depois, este script confere no banco o pedido entregue e
# confirmado, os tokens do id antigo revogados, a trilha dos três eventos, a
# visita que NUNCA chegou a `visits` e a cadeia de auditoria.
#
# ATENÇÃO: substitui a stack de desenvolvimento pela de e2e; o banco de e2e e o
# manifesto são apagados ao final.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

for arg in "$@"; do
  case "$arg" in
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$HOME/.pub-cache/bin"

dev="${DEVICE:-emulator-5554}"
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "aparelho $dev não encontrado (adb devices)"; exit 4; }

relay_pid=""
saida_teste="$(mktemp)"
cleanup() {
  rm -f "$saida_teste"
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null || true
  rm -f .e2e/fixtures.json   # primeiro: tem as senhas sintéticas, mesmo se o down falhar
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
set -a; source .env; set +a
adb -s "$dev" reverse tcp:8443 tcp:443 >/dev/null
adb -s "$dev" reverse tcp:8883 tcp:8883 >/dev/null
adb -s "$dev" reverse tcp:8765 tcp:8765 >/dev/null

E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" python3 scripts/qa/otp_relay.py >/dev/null 2>&1 &
relay_pid=$!
for _ in $(seq 1 20); do
  curl -fs http://127.0.0.1:8765/now >/dev/null 2>&1 && break
  sleep 0.25
done
kill -0 "$relay_pid" 2>/dev/null || { echo 'erro: o relé não subiu' >&2; exit 1; }

sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }
fx() { python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));print(eval(sys.argv[1]))" "$1" || true; }
acs_id="$(fx "d['acs']['id']")"
coord_id="$(fx "d['coordinator']['id']")"
[[ -n "$acs_id" && -n "$coord_id" ]] || { echo 'erro: manifesto de fixtures incompleto' >&2; exit 1; }
# Sem os blocos de credencial: as senhas chegam pelo relé, nunca pelo argv.
fixtures="$(python3 -c "import json;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);d.pop('acsB',None);d.pop('staff',None);d.pop('coordinator',None);print(json.dumps(d))")"

echo "== limpeza remota no emulador"
( cd apps/acs && flutter pub get >/dev/null && flutter test integration_test/remote_wipe_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
    --dart-define=E2E_FIXTURES="$fixtures" ) 2>&1 | tee "$saida_teste"
[[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo 'erro: a limpeza remota no emulador falhou' >&2; exit 1; }
for marca in E2E_WIPE_PEDIDO E2E_WIPE_APARELHO E2E_WIPE_OK; do
  grep -q "$marca" "$saida_teste" || { echo "erro: o teste terminou sem a linha $marca" >&2; exit 1; }
done

pedido="$(grep -o 'E2E_WIPE_PEDIDO .*' "$saida_teste" | tail -1)"
ok="$(grep -o 'E2E_WIPE_OK .*' "$saida_teste" | tail -1)"
campo() { sed -n "s/.* $2=\([0-9a-fA-F-]*\).*/\1/p" <<<" $1"; }
ordem="$(campo "$pedido" order)"; aparelho="$(campo "$pedido" device)"
visita="$(campo "$ok" visita)"; novo="$(campo "$ok" novo)"
uuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
[[ "$ordem" =~ $uuid && "$visita" =~ $uuid ]] || { echo 'erro: marcadores sem uuid de pedido ou de visita' >&2; exit 1; }
[[ "$aparelho" =~ $uuid && "$novo" =~ $uuid && "$aparelho" != "$novo" ]] \
  || { echo 'erro: id antigo e novo da instalação ausentes ou iguais' >&2; exit 1; }
[[ "$(campo "$ok" acs)" == "$acs_id" ]] || { echo 'erro: o ACS no aparelho não é o da fixture' >&2; exit 1; }

echo "== limpeza remota no banco de teste (pedido $ordem)"
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
igual 'pedido do aparelho: id|motivo|alvo|quem pediu' "$ordem|stolen|$acs_id|$coord_id" \
  "select id || '|' || reason || '|' || \"targetUserId\" || '|' || \"requestedBy\" from device_wipe_orders where \"deviceId\" = '$aparelho'"
igual 'pedido entregue e confirmado (deliveredAt e confirmedAt)' 'true' \
  "select (\"deliveredAt\" is not null and \"confirmedAt\" is not null)::text from device_wipe_orders where id = '$ordem'"
# Não vazio: o id antigo TINHA tokens (senão "zero vivos" não provaria nada).
igual 'o id antigo tinha refresh token e token de envio' 'true' \
  "select ((select count(*) from acs_refresh_tokens where \"deviceId\" = '$aparelho') > 0 and (select count(*) from acs_upload_tokens where \"deviceId\" = '$aparelho') > 0)::text"
igual 'refresh tokens vivos do id antigo' 0 \
  "select count(*) from acs_refresh_tokens where \"deviceId\" = '$aparelho' and \"revokedAt\" is null"
igual 'tokens de envio vivos do id antigo' 0 \
  "select count(*) from acs_upload_tokens where \"deviceId\" = '$aparelho' and \"revokedAt\" is null"
igual 'o login de novo usou o id novo (refresh token vivo)' 'true' \
  "select (count(*) > 0)::text from acs_refresh_tokens where \"userId\" = '$acs_id' and \"deviceId\" = '$novo' and \"revokedAt\" is null"
igual 'trilha wipe_ordered (admin_device, pelo coordenador)' 1 \
  "select count(*) from audit_logs where \"resourceId\" = '$ordem' and \"resourceType\" = 'admin_device' and result = 'wipe_ordered' and \"userId\" = '$coord_id'"
igual 'trilha wipe_delivered (acs_device)' 1 \
  "select count(*) from audit_logs where \"resourceId\" = '$ordem' and \"resourceType\" = 'acs_device' and result = 'wipe_delivered'"
igual 'trilha wipe_confirmed (acs_device)' 1 \
  "select count(*) from audit_logs where \"resourceId\" = '$ordem' and \"resourceType\" = 'acs_device' and result = 'wipe_confirmed'"
igual 'a visita não enviada NÃO está em visits' 0 \
  "select count(*) from visits where \"localId\" = '$visita'"
igual 'nenhuma visita do ACS no servidor' 0 \
  "select count(*) from visits where \"acsId\" = '$acs_id'"

# Cadeia de hash da trilha (LGPD-RT03) íntegra depois do pedido, da entrega e da confirmação.
echo "== cadeia de auditoria no banco de teste"
( cd backend/sinalacs_server && \
  SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e \
  SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/audit_chain_check.dart 2>&1 | grep -E 'OK|FALHA|quebra|cadeia' | sed 's/^/  /'; exit "${PIPESTATUS[0]}" ) \
  || { echo 'erro: a cadeia de auditoria do banco de teste não está íntegra' >&2; exit 1; }

echo 'E2E de limpeza remota: OK'
