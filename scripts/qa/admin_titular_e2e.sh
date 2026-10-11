#!/usr/bin/env bash
#
# Atendimento a pedidos do titular (#42) pela tela do backoffice, no emulador-5554,
# contra o BANCO DE TESTE.
#
#   ./scripts/qa/admin_titular_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/admin_titular_e2e.sh   # aparelho físico
#
# Sobe a stack de e2e (e2e_stack.sh), semeia as fixtures sintéticas com dois pedidos
# do titular (E2E_SEED_DATA_REQUESTS=1: uma correção JÁ VENCIDA e uma exclusão com
# um token de push), sobe o relé (credencial do admin em /admin, uma vez) e roda
# apps/admin/integration_test/admin_titular_e2e.dart. Depois confere NO BANCO: os
# dois pedidos atendidos pelo admin, a nota cifrada, o titular excluído anonimizado
# (nome, cpfHash, push), alertas e consentimentos preservados, uma linha de auditoria
# por escrita e a cadeia de auditoria íntegra; e que a nota sintética não está nos
# logs do backend. Nada é escrito no banco de desenvolvimento; banco e manifesto são
# apagados ao final.
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
E2E_SEED_DATA_REQUESTS=1 ./scripts/qa/e2e_stack.sh seed
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

sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
fx() { python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));print(eval(sys.argv[1]))" "$1"; }
staff_id="$(fx "d['staff']['id']")"
main_id="$(fx "[p for p in d['patients'] if p['role']=='main'][0]['id']")"
excl_id="$(fx "[p for p in d['patients'] if p['role']=='chronic'][0]['id']")"
nome_original="$(sql "select name from users where id='$excl_id'")"
corr_req="$(sql "select id from data_subject_requests where \"userId\"='$main_id'")"
excl_req="$(sql "select id from data_subject_requests where \"userId\"='$excl_id'")"
consents_antes="$(sql "select count(*) from consent_logs where \"userId\"='$excl_id'")"
alertas_antes="$(sql "select count(*) from alerts where \"patientId\"='$excl_id'")"

echo "== atendimento no emulador"
status=0
( cd apps/admin && flutter pub get >/dev/null && flutter test integration_test/admin_titular_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ ) 2>&1 || status=$?
[[ "$status" -eq 0 ]] || { echo "erro: o atendimento no emulador falhou (código $status)" >&2; exit 1; }

echo "== conferência no banco de teste"
igual 'os dois pedidos atendidos pelo admin' '2|2' \
  "select count(*)::text || '|' || count(*) filter (where \"decidedBy\"='$staff_id' and \"decidedAt\" is not null)::text from data_subject_requests where status='completed'"
igual 'nota da correção gravada cifrada (não está em claro)' 'true' \
  "select (\"resolutionEncrypted\" is not null and \"resolutionEncrypted\" not like '%E2E-NOTA%')::text from data_subject_requests where id='$corr_req'"
igual 'titular excluído: nome anonimizado e cpfHash removed:' 'true|true' \
  "select (name <> '$nome_original')::text || '|' || (\"cpfHash\" like 'removed:%')::text from users where id='$excl_id'"
igual 'titular excluído: zero push_tokens e otp_challenges' '0|0' \
  "select (select count(*) from push_tokens where \"userId\"='$excl_id')::text || '|' || (select count(*) from otp_challenges where \"userId\"='$excl_id')::text"
# A anonimização acrescenta UMA recusa de push (segmentedPush) e não apaga nada.
igual 'consent_logs do titular excluído preservados (+1 recusa de push)' "$((consents_antes + 1))|1" \
  "select count(*)::text || '|' || count(*) filter (where purpose='segmentedPush' and action='denied')::text from consent_logs where \"userId\"='$excl_id'"
igual 'alertas do titular excluído preservados' "$alertas_antes" \
  "select count(*) from alerts where \"patientId\"='$excl_id'"
igual 'titular da correção intocado (nome e cpfHash)' 'true' \
  "select (name like 'Paciente E2E%' and \"cpfHash\" not like 'removed:%')::text from users where id='$main_id'"
# Escritas auditadas, uma por decisão: correção = in_review + completed; exclusão = completed.
igual 'auditoria das escritas (correção in_review,completed; exclusão completed)' 'in_review,completed|completed' \
  "select (select string_agg(result, ',' order by sequence) from audit_logs where \"resourceType\"='data_subject_request' and \"actionType\"='write' and \"resourceId\"='$corr_req') || '|' || (select string_agg(result, ',' order by sequence) from audit_logs where \"resourceType\"='data_subject_request' and \"actionType\"='write' and \"resourceId\"='$excl_req')"
igual 'escritas todas feitas pelo admin' 'true' \
  "select (count(*) = 3 and bool_and(\"userId\"='$staff_id'))::text from audit_logs where \"resourceType\"='data_subject_request' and \"actionType\"='write'"

echo "== cadeia de auditoria"
( cd backend/sinalacs_server && set -a && source ../../.env && set +a && \
  SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e \
  SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/audit_chain_check.dart 2>&1 | grep -E 'cadeia|quebra|OK' )

echo "== a nota e o texto do pedido não estão nos logs do backend"
if docker logs sinalacs-serverpod 2>&1 | grep -E 'E2E-NOTA|E2E-CORRECAO|E2E-EXCLUSAO' >/dev/null; then
  echo 'erro: texto sintético do titular apareceu nos logs do backend' >&2; exit 1
fi
echo '  nenhuma ocorrência'
echo 'OK — atendimento a pedidos do titular contra o banco de teste'
