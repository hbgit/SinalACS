#!/usr/bin/env bash
#
# Telemetria dos eventos do PRD §1.3 (#83) no emulador-5554, contra o BANCO DE
# TESTE: alerta → ACK → visitas offline → reinício simulado → online → reenvio
# idempotente. O reinício é simulado (um SinalAcsApp novo no mesmo processo);
# "app morto entre attempt e result" só tem prova unitária.
#
#   ./scripts/qa/acs_telemetria_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/acs_telemetria_e2e.sh   # aparelho físico
#
# Sobe a stack de e2e (e2e_stack.sh), semeia as fixtures sintéticas (com o
# paciente `telemetry`, na microárea do ACS), sobe o relé (OTP + credencial do
# ACS) e roda integration_test/telemetry_e2e.dart. O broker fica fora do
# alcance do aparelho (o ACL não libera a microárea da fixture): o alerta chega
# pela reserva HTTP. O teste fala com o script por linhas marcadoras:
#   E2E_CORTAR_BACKEND    → `docker pause sinalacs-traefik` (a única rota do
#                           aparelho até o backend; o backend segue no ar)
#   E2E_RESTAURAR_BACKEND → `docker unpause sinalacs-traefik`
# O `cleanup` SEMPRE despausa o Traefik.
#
# Depois confere no banco o que só o servidor sabe: as contagens por evento, o
# reenvio sem duplicar, o UUID do paciente nunca cru, a visita ligada ao alerta
# e o relatório de bin/telemetry_report.dart sobre a janela da execução.
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
teste_pid=""
eco_pid=""
saida_teste="$(mktemp)"
cleanup() {
  docker unpause sinalacs-traefik >/dev/null 2>&1 || true
  if [[ -n "$teste_pid" ]]; then pkill -P "$teste_pid" 2>/dev/null || true; kill "$teste_pid" 2>/dev/null || true; fi
  [[ -n "$eco_pid" ]] && kill "$eco_pid" 2>/dev/null || true
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
# O broker fora do alcance do APARELHO: o alerta só chega pela reserva HTTP.
adb -s "$dev" reverse --remove tcp:8883 >/dev/null 2>&1 || true
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
paciente_id="$(fx "[p for p in d['patients'] if p['role']=='telemetry'][0]['id']")"
[[ "$paciente_id" =~ ^[0-9a-f-]{36}$ ]] || { echo 'erro: manifesto sem o paciente telemetry' >&2; exit 1; }
# Sem os blocos de credencial: as senhas chegam pelo relé, nunca pelo argv.
fixtures="$(python3 -c "import json;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);d.pop('acsB',None);d.pop('staff',None);d.pop('coordinator',None);print(json.dumps(d))")"

# A janela do relatório cobre a execução inteira (UTC, [início, fim)).
inicio="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "== telemetria no emulador"
( cd apps/acs && flutter pub get >/dev/null && flutter test integration_test/telemetry_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=E2E_FIXTURES="$fixtures" ) >"$saida_teste" 2>&1 &
teste_pid=$!
tail -n +1 -f --pid="$teste_pid" "$saida_teste" >&2 &
eco_pid=$!

cortado=false
restaurado=false
while kill -0 "$teste_pid" 2>/dev/null; do
  if [[ "$cortado" == false ]] && grep -q 'E2E_CORTAR_BACKEND' "$saida_teste"; then
    docker pause sinalacs-traefik >/dev/null
    echo "  [script] Traefik pausado ($(date +%T)); o backend segue no ar" >&2
    cortado=true
  fi
  if [[ "$restaurado" == false ]] && grep -q 'E2E_RESTAURAR_BACKEND' "$saida_teste"; then
    docker unpause sinalacs-traefik >/dev/null
    echo "  [script] Traefik de volta ($(date +%T))" >&2
    restaurado=true
  fi
  sleep 1
done
status=0
wait "$teste_pid" || status=$?
teste_pid=""
wait "$eco_pid" 2>/dev/null || true
eco_pid=""
[[ "$status" -eq 0 ]] || { echo "erro: a telemetria no emulador falhou (código $status)" >&2; exit 1; }
[[ "$cortado" == true && "$restaurado" == true ]] \
  || { echo "erro: o script não viu as linhas marcadoras (cortado=$cortado restaurado=$restaurado)" >&2; exit 1; }
grep -q 'E2E_TELEMETRIA_OK' "$saida_teste" || { echo 'erro: o teste terminou sem a linha E2E_TELEMETRIA_OK' >&2; exit 1; }
alerta_id="$(grep -o 'E2E_ALERTA id=[0-9a-f-]*' "$saida_teste" | tail -1 | sed 's/.*=//')"
[[ "$alerta_id" =~ ^[0-9a-f-]{36}$ ]] || { echo "erro: id de alerta inválido na linha marcadora ($alerta_id)" >&2; exit 1; }
fim="$(date -u -d '+1 minute' +%Y-%m-%dT%H:%M:%SZ)"

echo "== telemetria no banco de teste (alerta $alerta_id)"
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $(echo "$v" | tr '\n' ' ')"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$(echo "$2" | tr '\n' ' ')' ($1)" >&2; exit 1; }
  echo "    OK"
}
igual 'eventos por nome' "$(printf 'alert_received_acs|1\nalert_triggered|1\nsync_attempt|2\nsync_result|2\nvisit_registered|3')" \
  "SELECT \"eventName\", count(*) FROM telemetry_events GROUP BY 1 ORDER BY 1"
igual 'nenhum eventId duplicado depois do reenvio' t \
  "SELECT count(*) = count(DISTINCT \"eventId\") FROM telemetry_events"
igual 'UUID do paciente nunca cru' 0 \
  "SELECT count(*) FROM telemetry_events WHERE payload LIKE '%$paciente_id%' OR \"patientPseudonym\" = '$paciente_id'"
igual 'uma visita ligada ao alerta' 1 \
  "SELECT count(*) FROM telemetry_events WHERE \"eventName\"='visit_registered' AND \"alertId\" = '$alerta_id'"

echo "== relatório (telemetry_report.dart, $inicio → $fim)"
relatorio="$(cd backend/sinalacs_server && \
  SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 \
  SERVERPOD_DATABASE_NAME=sinalacs_e2e SERVERPOD_DATABASE_USER=postgres \
  SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/telemetry_report.dart --from "$inicio" --to "$fim" | tail -1)"
echo "  $relatorio"
RELATORIO="$relatorio" python3 - <<'EOF'
import json, os, sys
r = json.loads(os.environ["RELATORIO"])
falhas = 0
def conferir(chave, ok, esperado):
    global falhas
    print(f"  {chave}: {r.get(chave)!r} (esperado {esperado}) {'OK' if ok else 'FALHOU'}")
    if not ok: falhas += 1
conferir("eventualSyncRate", r.get("eventualSyncRate") == 1.0, "1.0")
conferir("interruptedAttempts", r.get("interruptedAttempts") == 0, "0")
conferir("alertLinkedVisits", r.get("alertLinkedVisits") == 1, "1")
conferir("perAttemptSuccessRate", r.get("perAttemptSuccessRate") == 0.5, "0.5 (3 de 6)")
conferir("medianAckLatencyMs", r.get("medianAckLatencyMs") is not None, "não nulo")
sys.exit(1 if falhas else 0)
EOF

echo "OK: telemetria do alerta ao reenvio, sem duplicar nem expor o paciente."
