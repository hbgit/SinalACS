#!/usr/bin/env bash
#
# Alerta vermelho concluído continua visível para a coordenação (issue #87,
# INV-03) no emulador-5554, contra o BANCO DE TESTE.
#
#   ./scripts/qa/admin_concluidos_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/admin_concluidos_e2e.sh   # aparelho físico
#
# ATENÇÃO: substitui a stack de desenvolvimento pela de e2e (o container
# sinalacs-serverpod é o mesmo). Ao fim, `docker compose up -d` volta a de
# desenvolvimento.
#
# Passo a passo manual (o que este script automatiza):
#   1. ./scripts/dev/bootstrap_env.sh            # só se ainda não houver .env
#      docker compose up -d                      # uma vez: gera os certificados do Traefik/Mosquitto
#   2. emulator -avd <avd> -no-snapshot &        # ou um aparelho físico com DEVICE=<serial>
#      adb wait-for-device && adb devices
#   3. ./scripts/qa/admin_concluidos_e2e.sh
#      - e2e_stack.sh up e seed com E2E_SEED_ADMIN_ALERTS=1: 3 alertas na microárea
#        do coordenador sintético (vermelho pendente, vermelho reconhecido, verde);
#      - relé (credencial do coordenador em /coordenador, uma vez) e adb reverse;
#      - o teste no aparelho; o script atende as linhas marcadoras dele, fazendo
#        o papel do ACS no banco (a mudança da #87 é de leitura; o que se prova é
#        que o Painel acompanha cada transição pelo pulso, sem toque):
#          E2E_RECONHECER id=<uuid>   -> pending -> acknowledged
#          E2E_CONCLUIR id=<uuid>     -> acknowledged -> resolved (resolvedAt = NOW())
#          E2E_CONCLUIR_SEM_MICROAREA -> insere um vermelho concluído sem microárea,
#                                        que só o administrador conta (#40)
#        e exige as evidências E2E_PAINEL_RECONHECIDO, E2E_PAINEL_CONCLUIDO e
#        E2E_ALERTAS_CONCLUIDO_OK;
#      - conferências no banco de teste e a cadeia de auditoria.
#   4. docker compose up -d                      # volta à stack de desenvolvimento
#
# Antes da correção da #87 o teste FALHA no 1º passo ("o Painel não tem a linha
# Concluídos"): é a reprodução da issue. Nada é escrito no banco de
# desenvolvimento; o banco de e2e e o manifesto são apagados ao final.
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
E2E_SEED_ADMIN_ALERTS=1 ./scripts/qa/e2e_stack.sh seed
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
fx() { python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));print(eval(sys.argv[1]))" "$1" || true; }
coord_id="$(fx "d['coordinator']['id']")"
acs_id="$(fx "d['acs']['id']")"
main_id="$(fx "[p for p in d['patients'] if p['role']=='main'][0]['id']")"
pendente_id="$(fx "d['adminAlertIds'][0]")"
reconhecido_id="$(fx "d['adminAlertIds'][1]")"
[[ -n "$coord_id" && -n "$acs_id" && -n "$main_id" && -n "$pendente_id" && -n "$reconhecido_id" ]] \
  || { echo 'erro: manifesto de fixtures incompleto (adminAlertIds?)' >&2; exit 1; }

# Os ids vêm da saída do teste: só um UUID passa para o SQL.
uuid_da_marca() { # <marca>
  local id
  id="$(grep -o "$1 id=[0-9a-f-]*" "$saida_teste" | tail -1 | sed 's/.*id=//')"
  [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || { echo "erro: a marca $1 veio sem UUID válido ('$id')" >&2; exit 1; }
  echo "$id"
}
# O papel do ACS no banco (como a #86 fez em acs_ack_concluido_e2e.sh): a
# transição guardada pelo `WHERE status = …` é a mesma que o servidor exige.
reconhecer() {
  local id; id="$(uuid_da_marca E2E_RECONHECER)"
  sql "update alerts set status = 'acknowledged', \"receivedAt\" = NOW(), \"acknowledgedAt\" = NOW(), \"acsId\" = '$acs_id' where id = '$id' and status = 'pending'" >/dev/null
  echo "  [script] alerta $id reconhecido ($(date +%T))" >&2
}
concluir() {
  local id; id="$(uuid_da_marca E2E_CONCLUIR)"
  sql "update alerts set status = 'resolved', \"resolvedAt\" = NOW() where id = '$id' and status = 'acknowledged'" >/dev/null
  echo "  [script] alerta $id concluído ($(date +%T))" >&2
}
# Sem microárea: o coordenador não o enxerga, o administrador sim (#40). Sem
# linha no alert_outbox: nada é publicado.
concluir_sem_microarea() {
  sql "insert into alerts (\"patientId\", \"acsId\", \"microAreaId\", \"triggeredAt\", \"acknowledgedAt\", \"resolvedAt\", \"riskLevel\", \"locationHash\", status, \"mqttTopic\", \"deviceId\", \"retryCount\", version) values ('$main_id', '$acs_id', NULL, NOW() - interval '30 minutes', NOW() - interval '20 minutes', NOW(), 'red', 'hash-e2e', 'resolved', 'sinalacs/v1/microareas/x/alerts', 'device-e2e', 0, 0)" >/dev/null
  echo "  [script] vermelho concluído sem microárea inserido ($(date +%T))" >&2
}

echo "== alerta concluído no emulador"
( cd apps/admin && flutter pub get >/dev/null && flutter test integration_test/admin_concluidos_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=E2E_ALERTA_PENDENTE="$pendente_id" \
    --dart-define=E2E_ALERTA_RECONHECIDO="$reconhecido_id" ) >"$saida_teste" 2>&1 &
teste_pid=$!
tail -n +1 -f --pid="$teste_pid" "$saida_teste" >&2 &
eco_pid=$!

reconhecido=false
concluido=false
sem_microarea=false
while kill -0 "$teste_pid" 2>/dev/null; do
  if [[ "$reconhecido" == false ]] && grep -q 'E2E_RECONHECER id=' "$saida_teste"; then
    reconhecer; reconhecido=true
  fi
  if [[ "$concluido" == false ]] && grep -q 'E2E_CONCLUIR id=' "$saida_teste"; then
    concluir; concluido=true
  fi
  if [[ "$sem_microarea" == false ]] && grep -q 'E2E_CONCLUIR_SEM_MICROAREA' "$saida_teste"; then
    concluir_sem_microarea; sem_microarea=true
  fi
  sleep 1
done
status=0
wait "$teste_pid" || status=$?
teste_pid=""
wait "$eco_pid" 2>/dev/null || true
eco_pid=""
[[ "$status" -eq 0 ]] || { echo "erro: a jornada do alerta concluído no emulador falhou (código $status)" >&2; exit 1; }
[[ "$reconhecido" == true && "$concluido" == true && "$sem_microarea" == true ]] \
  || { echo "erro: o script não viu as linhas marcadoras (reconhecido=$reconhecido concluido=$concluido sem_microarea=$sem_microarea)" >&2; exit 1; }
for marca in E2E_PAINEL_RECONHECIDO E2E_PAINEL_CONCLUIDO; do
  grep -q "$marca atraso_ms=" "$saida_teste" \
    || { echo "erro: o teste não provou o Painel atualizado pelo pulso (linha $marca)" >&2; exit 1; }
  grep -o "$marca atraso_ms=[-0-9]*" "$saida_teste" | tail -1 | sed 's/^/  /' || true
done
grep -q 'E2E_ALERTAS_CONCLUIDO_OK' "$saida_teste" \
  || { echo 'erro: o teste terminou sem a linha E2E_ALERTAS_CONCLUIDO_OK' >&2; exit 1; }

echo "== o que só o banco de teste responde"
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
igual 'dois vermelhos concluídos (o da UBS e o sem microárea)' 2 \
  "select count(*) from alerts where \"riskLevel\" = 'red' and status = 'resolved'"
igual 'um deles sem microárea (invisível ao coordenador)' 1 \
  "select count(*) from alerts where \"riskLevel\" = 'red' and status = 'resolved' and \"microAreaId\" is null"
igual 'o concluído da UBS com resolvedAt e acknowledgedAt' 'true' \
  "select (\"resolvedAt\" is not null and \"acknowledgedAt\" is not null)::text from alerts where id = '$reconhecido_id'"
# O pulso não grava `read` (#44): nenhuma linha do recurso dele fora as recusas.
igual 'nenhuma linha read do pulso' 0 \
  "select count(*) from audit_logs where \"resourceType\" = 'admin_pulse' and \"actionType\" = 'read' and \"result\" <> 'denied'"
# Leitura e exibição: nada foi republicado ao ACS.
igual 'nada no outbox para os alertas da jornada' 0 \
  "select count(*) from alert_outbox where \"alertId\" in ('$pendente_id', '$reconhecido_id')"
peloMenos() { # <descrição> <mínimo> <sql>
  local n; n="$(sql "$3")"
  echo "  $1: $n"
  [[ "$n" -ge "$2" ]] || { echo "erro: esperado >= $2 ($1)" >&2; exit 1; }
}
peloMenos 'monitoring_session_start do coordenador' 1 \
  "select count(*) from audit_logs where \"userId\" = '$coord_id' and \"actionType\" = 'monitoring_session_start' and \"resourceType\" = 'admin_monitoring'"

echo "== cadeia de auditoria"
( cd backend/sinalacs_server && set -a && source ../../.env && set +a && \
  SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e \
  SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/audit_chain_check.dart 2>&1 | grep -E 'cadeia|quebra|OK' )
echo 'OK — alerta concluído visível para a coordenação (#87) contra o banco de teste'
