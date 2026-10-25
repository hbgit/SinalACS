#!/usr/bin/env bash
#
# Trilha de auditoria completa do backoffice (issue #45) no emulador-5554,
# contra o BANCO DE TESTE.
#
#   ./scripts/qa/admin_auditoria_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/admin_auditoria_e2e.sh   # aparelho físico
#
# ATENÇÃO: substitui a stack de desenvolvimento pela de e2e (o container
# sinalacs-serverpod é o mesmo); ao fim, `docker compose up -d` volta a de
# desenvolvimento.
#
# Passo a passo manual (o que este script automatiza):
#   1. ./scripts/dev/bootstrap_env.sh            # só se ainda não houver .env
#      docker compose up -d                      # uma vez: gera os certificados do Traefik/Mosquitto
#   2. emulator -avd <avd> -no-snapshot &        # ou um aparelho físico com DEVICE=<serial>
#   3. ./scripts/qa/admin_auditoria_e2e.sh
#      - e2e_stack.sh up: Postgres sinalacs_e2e, backend, Traefik;
#      - seed com E2E_SEED_AUDIT_TRAIL=1: 60 linhas de auditoria sintéticas
#        encadeadas (bloco `auditTrail` do manifesto, passado ao teste por
#        --dart-define);
#      - relé (credenciais do admin em /admin e do coordenador em /coordenador,
#        uma vez cada) e adb reverse;
#      - o teste no aparelho; o script atende a linha marcadora dele:
#          E2E_ADULTERAR sequence=<n> -> guarda o `result` original da linha <n>
#                                        e faz `update audit_logs set result='x'`
#                                        como superusuário (`set local
#                                        session_replication_role = replica`:
#                                        o trigger append-only da #82 recusa o
#                                        UPDATE comum)
#                                        NO BANCO DE E2E (nunca no de dev);
#        o teste espera o servidor ver a linha `invalid` e segue;
#      - conferências no banco de teste (abaixo) e o verificador CLI: FALHA
#        (exit 1) com a linha adulterada e PASSA (exit 0) depois de restaurada;
#   4. docker compose up -d                      # volta à stack de desenvolvimento
#
# O que só o banco responde, conferido depois do teste: exatamente UMA linha
# `export`/`success` gravada no teste, com `resourceId` presente em
# `audit_exports`; UMA linha `export`/`denied` do coordenador; `audit_exports`
# com uma linha só e `filtersJson` só com chaves de filtro (nenhuma linha
# exportada). Nada é escrito no banco de desenvolvimento; o banco de e2e e o
# manifesto são apagados ao final.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

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
# Sem E2E_SEED_ADMIN_ALERTS/ALERT_ESCALATION: a trilha desta jornada tem só as
# linhas semeadas aqui e as que o próprio teste grava.
E2E_SEED_AUDIT_TRAIL=1 ./scripts/qa/e2e_stack.sh seed
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

# Toda escrita e leitura de banco deste script vai ao sinalacs_e2e, pelo
# e2e_stack.sh (container sinalacs-postgres-test) — nunca ao Postgres de dev.
sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }
# `|| true`: sob `set -e`/`pipefail` um `python3` sem saída derrubaria o script
# aqui, antes da mensagem de erro do assert que usa a variável.
fx() { python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));print(eval(sys.argv[1]))" "$1" || true; }
coord_id="$(fx "d['coordinator']['id']")"
staff_id="$(fx "d['staff']['id']")"
linhas="$(fx "d['auditTrail']['rows']")"
alvo="$(fx "d['auditTrail']['tamperSequence']")"
# Lidos AQUI, na raiz do repositório: dentro do `( cd apps/admin && … )` do
# teste o caminho relativo do manifesto não existe e o `fx` devolveria vazio
# (a 1ª execução real passou 0 ao teste por isso).
declare -A trilha
for chave in exportRows acsRows periodRows periodFirstSequence periodLastSequence; do
  trilha[$chave]="$(fx "d['auditTrail']['$chave']")"
  [[ "${trilha[$chave]}" =~ ^[0-9]+$ ]] || { echo "erro: auditTrail.$chave ausente no manifesto" >&2; exit 1; }
done
[[ -n "$coord_id" && -n "$staff_id" && -n "$linhas" && -n "$alvo" ]] \
  || { echo 'erro: o manifesto não tem o bloco auditTrail (seed sem E2E_SEED_AUDIT_TRAIL=1?)' >&2; exit 1; }
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
igual 'linhas semeadas na trilha' "$linhas" 'select count(*) from audit_logs'

# Verificador CLI contra o banco de e2e; devolve o código de saída.
cadeia_cli() {
  local codigo=0 saida
  saida="$( cd backend/sinalacs_server && set -a && source ../../.env && set +a && \
    SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e \
    SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
    dart run bin/audit_chain_check.dart 2>&1 )" || codigo=$?
  grep -E 'OK|FALHA' <<< "$saida" | sed 's/^/    /' >&2 || true
  echo "$codigo"
}
codigo="$(cadeia_cli)"
echo "  verificador CLI antes do teste: exit=$codigo"
[[ "$codigo" == 0 ]] || { echo 'erro: a cadeia semeada não passou no verificador CLI' >&2; exit 1; }

# A adulteração: só quando o teste pede, só no banco de e2e, guardando o valor
# original para restaurar depois.
original=""
adulterar() {
  local n
  n="$(grep -o 'E2E_ADULTERAR sequence=[0-9]*' "$saida_teste" | tail -1 | sed 's/.*=//')"
  [[ "$n" == "$alvo" ]] || { echo "erro: o teste pediu a sequence '$n', o manifesto diz '$alvo'" >&2; exit 1; }
  original="$(sql "select result from audit_logs where sequence = $n")"
  [[ -n "$original" ]] || { echo "erro: a linha $n não existe" >&2; exit 1; }
  sql "begin; set local session_replication_role = replica; update audit_logs set result = 'x' where sequence = $n; commit;" >/dev/null
  echo "  [script] linha $n adulterada no sinalacs_e2e (result '$original' -> 'x') ($(date +%T))" >&2
}

echo "== trilha de auditoria no emulador"
# O teste roda em segundo plano, com a saída num arquivo que o laço abaixo lê
# em tempo real (a linha marcadora) e que o `tail` ecoa na tela.
( cd apps/admin && flutter pub get >/dev/null && flutter test integration_test/admin_auditoria_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=E2E_AUDIT_ROWS="$linhas" \
    --dart-define=E2E_AUDIT_EXPORT_ROWS="${trilha[exportRows]}" \
    --dart-define=E2E_AUDIT_ACS_ROWS="${trilha[acsRows]}" \
    --dart-define=E2E_AUDIT_PERIOD_ROWS="${trilha[periodRows]}" \
    --dart-define=E2E_AUDIT_PERIOD_FIRST="${trilha[periodFirstSequence]}" \
    --dart-define=E2E_AUDIT_PERIOD_LAST="${trilha[periodLastSequence]}" \
    --dart-define=E2E_AUDIT_TAMPER_SEQUENCE="$alvo" ) >"$saida_teste" 2>&1 &
teste_pid=$!
tail -n +1 -f --pid="$teste_pid" "$saida_teste" >&2 &
eco_pid=$!

adulterado=false
while kill -0 "$teste_pid" 2>/dev/null; do
  if [[ "$adulterado" == false ]] && grep -q 'E2E_ADULTERAR sequence=' "$saida_teste"; then
    adulterar; adulterado=true
  fi
  sleep 1
done
status=0
wait "$teste_pid" || status=$?
teste_pid=""
wait "$eco_pid" 2>/dev/null || true
eco_pid=""
[[ "$status" -eq 0 ]] || { echo "erro: a trilha de auditoria no emulador falhou (código $status)" >&2; exit 1; }
[[ "$adulterado" == true ]] || { echo 'erro: o script não viu a linha E2E_ADULTERAR' >&2; exit 1; }
for marcador in E2E_CADEIA_INTEGRA E2E_FILTROS_OK E2E_ADULTERACAO_DETECTADA E2E_EXPORT_FEITO E2E_COORDENADOR_OK E2E_FIM; do
  grep -q "$marcador" "$saida_teste" || { echo "erro: o teste terminou sem a linha $marcador" >&2; exit 1; }
done
grep -o 'E2E_CLIPBOARD caminho=[a-z]*' "$saida_teste" | tail -1 | sed 's/^/  /' || true

echo "== exportação e recusa no banco de teste"
igual 'uma linha export/success gravada no teste' 1 \
  "select count(*) from audit_logs where sequence > $linhas and \"actionType\" = 'export' and result = 'success'"
igual 'ela é do administrador, sobre admin_audit_logs, ligada a audit_exports' 'true' \
  "select (l.\"userId\" = '$staff_id' and l.\"resourceType\" = 'admin_audit_logs' and e.id is not null and e.\"requestedBy\" = l.\"userId\")::text from audit_logs l left join audit_exports e on e.id = l.\"resourceId\" where l.sequence > $linhas and l.\"actionType\" = 'export' and l.result = 'success'"
igual 'uma recusa export/denied do coordenador' 1 \
  "select count(*) from audit_logs where \"userId\" = '$coord_id' and \"actionType\" = 'export' and \"resourceType\" = 'admin_audit_export' and result = 'denied'"
igual 'nenhuma exportação do coordenador concluída' 0 \
  "select count(*) from audit_exports where \"requestedBy\" = '$coord_id'"
igual 'uma única linha em audit_exports' 1 'select count(*) from audit_exports'
igual 'audit_exports com o recorte do período e a cadeia quebrada no momento' "${trilha[periodRows]}|${trilha[periodFirstSequence]}|${trilha[periodLastSequence]}|broken|csv" \
  "select \"rowCount\" || '|' || \"firstSequence\" || '|' || \"lastSequence\" || '|' || \"chainState\" || '|' || format from audit_exports"
filtros="$(sql 'select "filtersJson" from audit_exports')"
python3 -c '
import json, sys
f = json.loads(sys.argv[1])
permitidas = {"actorEnrollmentId", "actorRole", "actionType", "resourceType", "result", "from", "to", "search"}
extras = set(f) - permitidas
assert not extras, f"chaves fora do filtro: {sorted(extras)}"
assert "from" in f and "to" in f, "sem período"
assert len(sys.argv[1]) < 512, "filtersJson grande demais para ser só filtro"
print("  filtersJson só com chaves de filtro:", sorted(f))
' "$filtros" || { echo 'erro: audit_exports.filtersJson não é só o filtro' >&2; exit 1; }

echo "== append-only no banco de e2e (#82)"
# O sinalacs_e2e é recriado a cada rodada, então o trigger aqui veio do
# definition.sql da última migração — o caminho de um banco novo.
if recusa="$(sql "update audit_logs set result = result where sequence = $alvo" 2>&1)"; then
  echo 'erro: o UPDATE comum deveria ser recusado pelo trigger append-only' >&2; exit 1
fi
[[ "$recusa" == *append-only* ]] || { echo "erro: a recusa não veio do trigger append-only: $recusa" >&2; exit 1; }
echo "  UPDATE comum recusado: ${recusa##*ERROR:  }"

echo "== cadeia de auditoria (verificador CLI)"
codigo="$(cadeia_cli)"
echo "  com a linha $alvo adulterada: exit=$codigo"
[[ "$codigo" == 1 ]] || { echo "erro: o verificador CLI deveria FALHAR (exit 1) com a cadeia adulterada; saiu $codigo" >&2; exit 1; }
sql "begin; set local session_replication_role = replica; update audit_logs set result = '$original' where sequence = $alvo; commit;" >/dev/null
echo "  [script] linha $alvo restaurada (result 'x' -> '$original')"
codigo="$(cadeia_cli)"
echo "  depois de restaurada: exit=$codigo"
[[ "$codigo" == 0 ]] || { echo "erro: o verificador CLI deveria PASSAR (exit 0) com a cadeia restaurada; saiu $codigo" >&2; exit 1; }
echo 'OK — trilha de auditoria do backoffice contra o banco de teste'
