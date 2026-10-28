#!/usr/bin/env bash
#
# Certificado por aparelho (#94) no emulador-5554, contra o BANCO DE TESTE:
# emissão → conexão → dois aparelhos → limpeza remota → recusa.
#
#   ./scripts/qa/acs_device_cert_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/acs_device_cert_e2e.sh   # aparelho físico
#
# Três atores, conversando por linhas marcadoras lidas em tempo real:
#   · o emulador (apps/acs/integration_test/device_cert_e2e.dart): o ACS da
#     fixture entra pela tela, o feed emite o certificado deste aparelho e
#     conecta; o coordenador (relé `/coordenador`, MFA, TOTP) pede as limpezas;
#   · o segundo aparelho (apps/acs/tool/device_cert_second_device.dart, na VM):
#     o MESMO ACS com outro id de instalação, outro par EC, outro certificado;
#   · este script: o banco (`e2e_stack.sh psql`), o log do broker, a CRL e o
#     log do sidecar que a recarrega.
#
# Sequência e o que se confere:
#   1. E2E_CERT_PAINEL → UMA linha de device_certificates do aparelho do
#      emulador, CN = microárea da fixture, e a conexão no log do broker
#      (`New client connected ... as sinalacs-acs-<acs>-<aparelho> (... u'<microárea>')`);
#   2. a ferramenta sobe → E2E_DEV2_CONECTADO: segunda linha, outro aparelho,
#      outra serial, outra conexão no log do broker;
#   3. E2E_DISPARAR_ALERTA → o script insere o alerta e a entrega no
#      alert_outbox (a varredura de 10 s do backend a publica) → o emulador
#      mostra o cartão e a ferramenta imprime E2E_DEV2_ALERTA_RECEBIDO;
#   4. E2E_WIPE_DEV2_PEDIDO → E2E_DEV2_DERRUBADO em ≤ 5 s do `revokedAt`,
#      nenhuma volta sozinha, E2E_DEV2_RECONEXAO_RECUSADA; a linha revogada como
#      `wipe`, a serial na CRL (`openssl crl -text`) e o sidecar recarregando;
#   5. E2E_DISPARAR_ALERTA2 → o emulador ainda recebe pelo broker;
#   6. E2E_WIPE_DEV1_PEDIDO → fluxo da #81 na tela, a linha do emulador
#      revogada como `wipe` e a serial na CRL; E2E_CERT_OK → id novo, TERCEIRA
#      linha e conexão nova no log do broker;
#   7. trilha: device_cert_issued × 3, device_cert_revoked:wipe × 2 e a cadeia
#      de auditoria íntegra.
#
# Nenhuma chave, token ou senha é impresso: a ferramenta guarda a chave só em
# memória e lê a credencial do manifesto (E2E_FIXTURES_FILE), nunca do argv.
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
tool_pid=""
eco_pids=()
tmp="$(mktemp -d)"
saida_teste="$tmp/teste.out"
saida_tool="$tmp/dev2.out"
: >"$saida_teste"; : >"$saida_tool"
cleanup() {
  if [[ -n "$teste_pid" ]]; then pkill -P "$teste_pid" 2>/dev/null || true; kill "$teste_pid" 2>/dev/null || true; fi
  [[ -n "$tool_pid" ]] && kill "$tool_pid" 2>/dev/null || true
  for p in "${eco_pids[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$tmp"
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
# Sem o sidecar nenhuma revogação chega ao broker: o passo 4 não provaria nada.
[[ "$(docker inspect -f '{{.State.Running}}' sinalacs-mosquitto-crl-reload 2>/dev/null)" == true ]] \
  || { echo 'erro: o sidecar sinalacs-mosquitto-crl-reload não está rodando' >&2; exit 1; }
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
area_id="$(fx "d['microAreaId']")"
main_id="$(fx "[p for p in d['patients'] if p['role']=='main'][0]['id']")"
coord_id="$(fx "d['coordinator']['id']")"
[[ -n "$acs_id" && -n "$area_id" && -n "$main_id" && -n "$coord_id" ]] \
  || { echo 'erro: manifesto de fixtures incompleto' >&2; exit 1; }
# Sem os blocos de credencial: as senhas chegam pelo relé, nunca pelo argv.
fixtures="$(python3 -c "import json;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);d.pop('acsB',None);d.pop('staff',None);d.pop('coordinator',None);print(json.dumps(d))")"

devices_dir=infra/docker/mosquitto/runtime/devices
uuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
campo() { sed -n "s/.* $2=\([0-9a-fA-F-]*\).*/\1/p" <<<" $1"; }

# esperar <arquivo> <texto fixo> <segundos> <pid vigiado> → a última linha que
# casa. Falha se o tempo acaba ou se o processo vigiado morre antes.
esperar() {
  local fim=$((SECONDS + $3))
  while :; do
    if grep -qF -- "$2" "$1"; then grep -F -- "$2" "$1" | tail -1; return 0; fi
    if ! kill -0 "$4" 2>/dev/null; then
      sleep 1; grep -qF -- "$2" "$1" && { grep -F -- "$2" "$1" | tail -1; return 0; }
      echo "erro: o processo terminou sem a linha '$2'" >&2; return 1
    fi
    (( SECONDS < fim )) || { echo "erro: '$2' não apareceu em $3 s" >&2; return 1; }
    sleep 0.5
  done
}

# conectou_no_broker <aparelho>: a conexão do client id do aparelho, com a
# identidade (u'…') = microárea da fixture, no log do broker (até 15 s).
conectou_no_broker() {
  local linha=""
  for _ in $(seq 1 30); do
    linha="$(docker logs sinalacs-mosquitto 2>&1 | grep -F 'New client connected' \
      | grep -F " as sinalacs-acs-$acs_id-$1 (" | grep -F "u'$area_id'" | tail -1 || true)"
    [[ -n "$linha" ]] && break
    sleep 0.5
  done
  [[ -n "$linha" ]] || { echo "erro: o broker não registrou a conexão do aparelho $1 com u'$area_id'" >&2; exit 1; }
  echo "  broker: ${linha#*: }"
}

# na_crl <serial hex>: a serial aparece entre as revogadas (até 15 s).
na_crl() {
  local alvo; alvo="$(tr 'A-F' 'a-f' <<<"$1" | sed 's/^0*//')"
  for _ in $(seq 1 30); do
    if openssl crl -in "$devices_dir/crl.pem" -noout -text 2>/dev/null \
        | sed -n 's/.*Serial Number: *//p' | tr 'A-F' 'a-f' | sed 's/^0*//' | grep -qx "$alvo"; then
      echo "  serial $1 na CRL (openssl crl -text)"
      return 0
    fi
    sleep 0.5
  done
  echo "erro: a serial $1 não está na CRL" >&2; exit 1
}

# sidecar_recarregou_desde <AAAA-MM-DDTHH:MM:SSZ>: uma linha "CRL recarregada
# (<data>)" do sidecar com data ≥ a dada (até 15 s).
sidecar_recarregou_desde() {
  local linha=""
  for _ in $(seq 1 30); do
    linha="$(docker logs sinalacs-mosquitto-crl-reload 2>&1 \
      | sed -n 's/^CRL recarregada (\(.*\))$/\1/p' | awk -v t="$1" '$0 >= t' | tail -1 || true)"
    [[ -n "$linha" ]] && break
    sleep 0.5
  done
  [[ -n "$linha" ]] || { echo "erro: o sidecar não logou 'CRL recarregada' desde $1" >&2; exit 1; }
  echo "  sidecar: CRL recarregada ($linha), revogação às $1"
}

# Mesmas colunas do seed (bin/seed_e2e_fixtures.dart), e a entrega no outbox
# com o envelope de AlertDelivery: a varredura do backend (10 s) a publica.
inserir_alerta() {
  local id="$1"
  [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] \
    || { echo "erro: id de alerta inválido na linha marcadora ($id)" >&2; exit 1; }
  local quando; quando="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  local payload="{\"version\":1,\"alert_id\":\"$id\",\"patient_id\":\"$main_id\",\"micro_area_id\":\"$area_id\",\"risk_level\":\"red\",\"location_hash\":\"hash-e2e\",\"triggered_at\":\"$quando\"}"
  sql "insert into alerts (id, \"patientId\", \"acsId\", \"microAreaId\", \"triggeredAt\", \"riskLevel\", \"locationHash\", status, \"mqttTopic\", \"deviceId\", \"retryCount\", version) values ('$id', '$main_id', '$acs_id', '$area_id', NOW(), 'red', 'hash-e2e', 'pending', 'sinalacs/v1/microareas/$area_id/alerts', 'device-e2e', 0, 0)" >/dev/null
  sql "insert into alert_outbox (\"alertId\", topic, payload, \"createdAt\", attempts, \"nextAttemptAt\") values ('$id', 'sinalacs/v1/microareas/$area_id/alerts', '$payload', now() at time zone 'utc', 0, now() at time zone 'utc')" >/dev/null
  echo "  [script] alerta $id inserido e enfileirado no outbox ($(date +%T))" >&2
}

echo "== segundo aparelho: compilando a ferramenta"
( cd apps/acs && flutter pub get >/dev/null && dart compile exe tool/device_cert_second_device.dart -o "$tmp/dev2" >/dev/null ) \
  || { echo 'erro: a ferramenta do segundo aparelho não compilou' >&2; exit 1; }

echo "== emulador: certificado por aparelho"
( cd apps/acs && flutter test integration_test/device_cert_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=E2E_FIXTURES="$fixtures" ) >"$saida_teste" 2>&1 &
teste_pid=$!
tail -n +1 -f --pid="$teste_pid" "$saida_teste" >&2 &
eco_pids+=($!)

# 1) Emissão e conexão do emulador.
painel="$(esperar "$saida_teste" 'E2E_CERT_PAINEL acs=' 420 "$teste_pid")"
dev1="$(campo "$painel" device)"; serial1="$(campo "$painel" serial)"
[[ "$(campo "$painel" acs)" == "$acs_id" ]] || { echo 'erro: o ACS no aparelho não é o da fixture' >&2; exit 1; }
[[ "$dev1" =~ $uuid && -n "$serial1" ]] || { echo 'erro: E2E_CERT_PAINEL sem aparelho ou serial' >&2; exit 1; }
echo "== 1) emulador: aparelho $dev1"
igual 'uma linha de device_certificates do emulador' 1 \
  "select count(*) from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev1'"
igual 'emulador: serial|CN = microárea da fixture|revogado|motivo' "$serial1|$area_id|false|-" "select serial || '|' || \"microAreaId\" || '|' || (\"revokedAt\" is not null)::text || '|' || coalesce(\"revocationReason\", '-') from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev1' and \"microAreaId\" = '$area_id'"
conectou_no_broker "$dev1"

# 2) O segundo aparelho do mesmo ACS.
echo "== 2) segundo aparelho (VM)"
E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" "$tmp/dev2" \
  --rpc-ca "$repo_root/infra/docker/traefik/runtime/certs/ca.crt" \
  --broker-ca "$repo_root/infra/docker/mosquitto/runtime/certs/ca.crt" >"$saida_tool" 2>&1 &
tool_pid=$!
tail -n +1 -f --pid="$tool_pid" "$saida_tool" | sed -u 's/^/  [dev2] /' >&2 &
eco_pids+=($!)
conectado="$(esperar "$saida_tool" 'E2E_DEV2_CONECTADO' 90 "$tool_pid")"
dev2="$(campo "$conectado" device)"; serial2="$(campo "$conectado" serial)"
[[ "$dev2" =~ $uuid && "$dev2" != "$dev1" && -n "$serial2" && "$serial2" != "$serial1" ]] \
  || { echo 'erro: o segundo aparelho não tem id e serial próprios' >&2; exit 1; }
igual 'duas linhas de device_certificates do ACS' 2 \
  "select count(*) from device_certificates where \"userId\" = '$acs_id'"
igual 'segundo aparelho: serial|CN|revogado|motivo' "$serial2|$area_id|false|-" "select serial || '|' || \"microAreaId\" || '|' || (\"revokedAt\" is not null)::text || '|' || coalesce(\"revocationReason\", '-') from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev2'"
conectou_no_broker "$dev2"

# 3) Um alerta para os dois.
echo "== 3) alerta para os dois aparelhos"
disparo="$(esperar "$saida_teste" 'E2E_DISPARAR_ALERTA id=' 240 "$teste_pid")"
alerta1="$(campo "$disparo" id)"
[[ "$(campo "$disparo" dev2)" == "$dev2" ]] || { echo 'erro: o coordenador viu outro segundo aparelho' >&2; exit 1; }
inserir_alerta "$alerta1"
esperar "$saida_tool" "E2E_DEV2_ALERTA_RECEBIDO $alerta1" 60 "$tool_pid" >/dev/null
esperar "$saida_teste" "E2E_ALERTA_NA_TELA id=$alerta1" 120 "$teste_pid" >/dev/null
echo "  o alerta $alerta1 chegou ao emulador e ao segundo aparelho"

# 4) Limpeza remota do segundo aparelho: derrubado, recusado, revogado.
echo "== 4) limpeza remota do segundo aparelho"
pedido2="$(esperar "$saida_teste" 'E2E_WIPE_DEV2_PEDIDO' 60 "$teste_pid")"
[[ "$(campo "$pedido2" device)" == "$dev2" ]] || { echo 'erro: o pedido não é do segundo aparelho' >&2; exit 1; }
derrubado="$(esperar "$saida_tool" 'E2E_DEV2_DERRUBADO at_ms=' 30 "$tool_pid")"
caiu_ms="$(sed -n 's/.*at_ms=\([0-9]*\).*/\1/p' <<<"$derrubado")"
revogado_ms="$(sql "select (extract(epoch from \"revokedAt\") * 1000)::bigint from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev2'")"
[[ -n "$caiu_ms" && -n "$revogado_ms" ]] || { echo 'erro: sem instante da queda ou da revogação' >&2; exit 1; }
atraso=$((caiu_ms - revogado_ms))
echo "  derrubado ${atraso} ms depois do revokedAt"
[[ "$atraso" -ge -1000 && "$atraso" -le 5000 ]] || { echo "erro: a derrubada não ficou em até 5 s ($atraso ms)" >&2; exit 1; }
recebido_linha="$(grep -nF "E2E_DEV2_ALERTA_RECEBIDO $alerta1" "$saida_tool" | head -1 | cut -d: -f1)"
derrubado_linha="$(grep -nF 'E2E_DEV2_DERRUBADO' "$saida_tool" | head -1 | cut -d: -f1)"
[[ "$recebido_linha" -lt "$derrubado_linha" ]] || { echo 'erro: o alerta não chegou ao segundo aparelho antes da derrubada' >&2; exit 1; }
esperar "$saida_tool" 'E2E_DEV2_RECONEXAO_RECUSADA' 60 "$tool_pid" | sed 's/^/  /'
status_tool=0; wait "$tool_pid" || status_tool=$?; tool_pid=""
[[ "$status_tool" -eq 0 ]] || { echo "erro: a ferramenta do segundo aparelho saiu com $status_tool" >&2; exit 1; }
! grep -qE 'E2E_DEV2_RECONECTOU|E2E_DEV2_RECONEXAO_ACEITA' "$saida_tool" \
  || { echo 'erro: o aparelho revogado voltou ao broker' >&2; exit 1; }
igual 'segundo aparelho revogado como wipe' "$serial2|$area_id|true|wipe" "select serial || '|' || \"microAreaId\" || '|' || (\"revokedAt\" is not null)::text || '|' || coalesce(\"revocationReason\", '-') from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev2' and \"revocationReason\" = 'wipe'"
na_crl "$serial2"
revogado_em="$(sql "select to_char(date_trunc('second', \"revokedAt\"), 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev2'")"
sidecar_recarregou_desde "$revogado_em"

# 5) O emulador segue recebendo.
echo "== 5) o emulador segue recebendo"
disparo2="$(esperar "$saida_teste" 'E2E_DISPARAR_ALERTA2 id=' 90 "$teste_pid")"
alerta2="$(campo "$disparo2" id)"
inserir_alerta "$alerta2"
esperar "$saida_teste" "E2E_ALERTA2_NA_TELA id=$alerta2" 150 "$teste_pid" >/dev/null
echo "  o alerta $alerta2 chegou ao emulador depois da revogação do outro aparelho"
igual 'os dois alertas publicados pelo outbox' 2 \
  "select count(*) from alert_outbox where \"alertId\" in ('$alerta1', '$alerta2') and \"publishedAt\" is not null"

# 6) Limpeza remota do emulador (#81) e reemissão.
echo "== 6) limpeza remota do emulador e reemissão"
pedido1="$(esperar "$saida_teste" 'E2E_WIPE_DEV1_PEDIDO' 60 "$teste_pid")"
[[ "$(campo "$pedido1" device)" == "$dev1" ]] || { echo 'erro: o pedido não é do emulador' >&2; exit 1; }
ok="$(esperar "$saida_teste" 'E2E_CERT_OK' 180 "$teste_pid")"
dev3="$(campo "$ok" novo)"; serial3="$(campo "$ok" serial)"
status=0; wait "$teste_pid" || status=$?; teste_pid=""
[[ "$status" -eq 0 ]] || { echo "erro: o teste no emulador falhou (código $status)" >&2; exit 1; }
[[ "$dev3" =~ $uuid && "$dev3" != "$dev1" && "$dev3" != "$dev2" ]] || { echo 'erro: o id novo da instalação é inválido' >&2; exit 1; }
igual 'emulador revogado como wipe' "$serial1|$area_id|true|wipe" "select serial || '|' || \"microAreaId\" || '|' || (\"revokedAt\" is not null)::text || '|' || coalesce(\"revocationReason\", '-') from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev1' and \"revocationReason\" = 'wipe'"
na_crl "$serial1"
igual 'três linhas de device_certificates do ACS' 3 \
  "select count(*) from device_certificates where \"userId\" = '$acs_id'"
igual 'id novo: serial|CN|revogado|motivo' "$serial3|$area_id|false|-" "select serial || '|' || \"microAreaId\" || '|' || (\"revokedAt\" is not null)::text || '|' || coalesce(\"revocationReason\", '-') from device_certificates where \"userId\" = '$acs_id' and \"deviceId\" = '$dev3'"
conectou_no_broker "$dev3"

# 7) Trilha.
echo "== 7) trilha de auditoria"
igual 'trilha device_cert_issued (pelo ACS)' 3 \
  "select count(*) from audit_logs where \"resourceType\" = 'device_certificate' and result = 'device_cert_issued' and \"userId\" = '$acs_id'"
igual 'trilha device_cert_revoked:wipe (pelo coordenador)' 2 \
  "select count(*) from audit_logs where \"resourceType\" = 'device_certificate' and result = 'device_cert_revoked:wipe' and \"userId\" = '$coord_id'"
igual 'nenhuma outra revogação na trilha' 2 \
  "select count(*) from audit_logs where \"resourceType\" = 'device_certificate' and result like 'device_cert_revoked%'"
( cd backend/sinalacs_server && \
  SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e \
  SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/audit_chain_check.dart 2>&1 | grep -E 'OK|FALHA|quebra|cadeia' | sed 's/^/  /'; exit "${PIPESTATUS[0]}" ) \
  || { echo 'erro: a cadeia de auditoria do banco de teste não está íntegra' >&2; exit 1; }

echo 'E2E do certificado por aparelho: OK'
