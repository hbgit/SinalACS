#!/usr/bin/env bash
#
# ACK do ACS B sobre um alerta que o ACS A já confirmou (issue #88), no
# emulador-5554, contra o BANCO DE TESTE. O aparelho entra como o SEGUNDO ACS
# da fixture (bloco `acsB`, mesma microárea); o A é simulado por SQL.
#
#   ./scripts/qa/acs_ack_segundo_acs_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/acs_ack_segundo_acs_e2e.sh   # aparelho físico
#
# Mesma montagem da #86 (acs_ack_concluido_e2e.sh): o broker fica INALCANÇÁVEL
# a partir do aparelho e o alerta é inserido por SQL, SEM acsId e sem linha no
# `alert_outbox`, então chega à tela só pela reserva HTTP. Quando o teste
# imprime `E2E_CONFIRMAR_NO_APARELHO_A id=<uuid>`, o script confirma o alerta
# no banco como o ACS A (status, acsId, acknowledgedAt e a entrega). O ACK do B
# precisa voltar `acknowledged` (decisão da #88, opção 1) e, no banco,
# `alerts.acsId` tem de continuar sendo o A — antes da correção vinha o B.
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
# O broker fora do alcance do APARELHO: sem este reverse, localhost:8883 no
# emulador não leva a lugar nenhum.
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
acs_id="$(fx "d['acs']['id']")"
acs_b_id="$(fx "d['acsB']['id']")"
area_id="$(fx "d['microAreaId']")"
main_id="$(fx "[p for p in d['patients'] if p['role']=='main'][0]['id']")"
[[ -n "$acs_id" && -n "$acs_b_id" && -n "$area_id" && -n "$main_id" ]] || { echo 'erro: manifesto de fixtures incompleto' >&2; exit 1; }
# Sem os blocos de credencial: as senhas chegam pelo relé, nunca pelo argv.
fixtures="$(python3 -c "import json;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);d.pop('acsB',None);d.pop('staff',None);d.pop('coordinator',None);print(json.dumps(d))")"

# Mesmas colunas do seed (bin/seed_e2e_fixtures.dart). Nenhuma linha no
# alert_outbox: o despachante do backend nunca o publica no broker.
alerta_id=""
inserir_alerta() {
  alerta_id="$(grep -o 'E2E_DISPARAR_ALERTA id=[0-9a-f-]*' "$saida_teste" | tail -1 | sed 's/.*=//')"
  [[ "$alerta_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] \
    || { echo "erro: id de alerta inválido na linha marcadora ($alerta_id)" >&2; exit 1; }
  # "acsId" = NULL: pending é "ninguém confirmou" (#88).
  sql "insert into alerts (id, \"patientId\", \"acsId\", \"microAreaId\", \"triggeredAt\", \"riskLevel\", \"locationHash\", status, \"mqttTopic\", \"deviceId\", \"retryCount\", version) values ('$alerta_id', '$main_id', NULL, '$area_id', NOW(), 'red', 'hash-e2e', 'pending', 'sinalacs/v1/microareas/$area_id/alerts', 'device-e2e', 0, 0)" >/dev/null
  echo "  [script] alerta $alerta_id inserido ($(date +%T))" >&2
}

# O aparelho A confirma o recebimento: a linha fica como a do `alerts.acknowledge`
# do A (status, acsId, carimbos e a entrega; sem trilha: o que se confere é a
# trilha do ACK do aparelho B).
ack_a_em=""
confirmar_no_aparelho_a() {
  local id
  id="$(grep -o 'E2E_CONFIRMAR_NO_APARELHO_A id=[0-9a-f-]*' "$saida_teste" | tail -1 | sed 's/.*=//')"
  [[ "$id" == "$alerta_id" ]] || { echo "erro: id a confirmar ($id) não é o do alerta inserido ($alerta_id)" >&2; exit 1; }
  sql "begin; update alerts set status = 'acknowledged', \"acsId\" = '$acs_id', \"receivedAt\" = NOW(), \"acknowledgedAt\" = NOW() where id = '$alerta_id' and status = 'pending'; insert into alert_deliveries (\"alertId\", \"acsId\", \"acknowledgedAt\") values ('$alerta_id', '$acs_id', NOW()); commit;" >/dev/null
  ack_a_em="$(sql "select \"acknowledgedAt\" from alerts where id = '$alerta_id'")"
  [[ -n "$ack_a_em" ]] || { echo 'erro: a confirmação do aparelho A não gravou acknowledgedAt' >&2; exit 1; }
  echo "  [script] alerta $alerta_id confirmado no aparelho A ($(date +%T))" >&2
}

echo "== aparelho B (segundo ACS) confirma um alerta já confirmado pelo A (reserva HTTP: 30 s)"
( cd apps/acs && flutter pub get >/dev/null && flutter test integration_test/ack_by_second_acs_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=E2E_FIXTURES="$fixtures" ) >"$saida_teste" 2>&1 &
teste_pid=$!
tail -n +1 -f --pid="$teste_pid" "$saida_teste" >&2 &
eco_pid=$!

disparado=false
confirmado=false
while kill -0 "$teste_pid" 2>/dev/null; do
  if [[ "$disparado" == false ]] && grep -q 'E2E_DISPARAR_ALERTA id=' "$saida_teste"; then
    inserir_alerta; disparado=true
  fi
  if [[ "$disparado" == true && "$confirmado" == false ]] && grep -q 'E2E_CONFIRMAR_NO_APARELHO_A id=' "$saida_teste"; then
    confirmar_no_aparelho_a; confirmado=true
  fi
  sleep 1
done
status=0
wait "$teste_pid" || status=$?
teste_pid=""
wait "$eco_pid" 2>/dev/null || true
eco_pid=""
[[ "$status" -eq 0 ]] || { echo "erro: o teste no emulador falhou (código $status)" >&2; exit 1; }
[[ "$disparado" == true ]] || { echo 'erro: o script não viu a linha E2E_DISPARAR_ALERTA' >&2; exit 1; }
[[ "$confirmado" == true ]] || { echo 'erro: o script não viu a linha E2E_CONFIRMAR_NO_APARELHO_A' >&2; exit 1; }
for marca in E2E_ACK_B_OK; do
  grep -q "$marca" "$saida_teste" || { echo "erro: o teste terminou sem a linha $marca" >&2; exit 1; }
done

echo "== banco de teste (alerta $alerta_id)"
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
igual 'acsId segue o ACS A (quem confirmou primeiro)' "$acs_id" \
  "select \"acsId\" from alerts where id = '$alerta_id'"
igual 'acknowledgedAt não mudou' "$ack_a_em" \
  "select \"acknowledgedAt\" from alerts where id = '$alerta_id'"
igual 'status segue acknowledged' 'acknowledged' \
  "select status from alerts where id = '$alerta_id'"
igual 'duas entregas (A e B)' 2 \
  "select count(*) from alert_deliveries where \"alertId\" = '$alerta_id'"
igual 'a entrega do B existe' 1 \
  "select count(*) from alert_deliveries where \"alertId\" = '$alerta_id' and \"acsId\" = '$acs_b_id'"
igual 'uma linha ack_already_acknowledged do ACS B na trilha' 1 \
  "select count(*) from audit_logs where \"resourceType\" = 'alert' and \"resourceId\" = '$alerta_id' and result = 'ack_already_acknowledged' and \"userId\" = '$acs_b_id'"
igual 'nenhuma linha acknowledged na trilha' 0 \
  "select count(*) from audit_logs where \"resourceType\" = 'alert' and \"resourceId\" = '$alerta_id' and result = 'acknowledged'"
igual 'nada no alert_outbox: não veio pelo broker' 0 \
  "select count(*) from alert_outbox where \"alertId\" = '$alerta_id'"

echo "OK: o ACK do segundo ACS foi registrado (entrega e trilha) e o responsável do alerta continua sendo quem confirmou primeiro."
