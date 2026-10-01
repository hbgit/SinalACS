#!/usr/bin/env bash
#
# Teste completo do app do paciente no emulador-5554, contra o BANCO DE TESTE.
#
#   ./scripts/qa/patient_full_e2e.sh              # jornada + conexão + push (Gorush e FCM reais)
#   ./scripts/qa/patient_full_e2e.sh --sem-push   # só a jornada e a conexão (sem credenciais do FCM)
#
# O que faz: sobe a stack de e2e (scripts/qa/e2e_stack.sh: banco `sinalacs_e2e` no
# postgres-test, sem login de desenvolvimento), semeia fixtures geradas na hora (UUIDs e
# CPFs novos a cada execução), sobe o relé do código OTP e roda, no emulador:
#   - integration_test/full_journey_test.dart   (OTP, termos, triagem, alerta, status e
#                                                Meus dados, pela tela)
#   - tool/territory_check.dart (no host: o ACS lista os pacientes da microárea dele e não o de outra)
#   - integration_test/backend_connection_test.dart (RPC, determinismo, idempotência)
# Sem --sem-push, em seguida scripts/qa/push_e2e.sh --e2e-db --negativos (o aviso do ACS
# chega à bandeja pelo Gorush e FCM reais). Nada é escrito no banco de desenvolvimento;
# o banco de e2e e o manifesto (.e2e/fixtures.json) são apagados ao final.
#
# Pré-requisitos: emulador `emulator-5554` (para o push: Google Play e internet), o `.env`
# (./scripts/dev/bootstrap_env.sh) e, para o push, as credenciais descritas em push_e2e.sh.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"

push=1
for arg in "$@"; do
  case "$arg" in
    --sem-push) push=0 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

dev=emulator-5554
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

relay_pid=""
# O relé precisa ser ESTE processo: um relé antigo esquecido na porta responderia com código velho.
iniciar_rele() {
  if ss -ltn 2>/dev/null | grep -q '127.0.0.1:8765 '; then
    echo 'erro: a porta 8765 já está ocupada (relé antigo?). Encerre-o: pkill -f scripts/qa/otp_relay.py' >&2
    exit 1
  fi
  python3 scripts/qa/otp_relay.py >/dev/null 2>&1 &
  relay_pid=$!
  for _ in $(seq 1 20); do
    curl -fs http://127.0.0.1:8765/now >/dev/null 2>&1 && kill -0 "$relay_pid" 2>/dev/null && return 0
    sleep 0.25
  done
  echo 'erro: o relé do OTP não subiu' >&2
  exit 1
}
cleanup() {
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null || true
  rm -f .e2e/fixtures.json   # primeiro: o manifesto tem a senha do ACS, mesmo se o down falhar
  ./scripts/qa/e2e_stack.sh down >/dev/null 2>&1 \
    || echo 'aviso: e2e_stack.sh down falhou; o banco sinalacs_e2e pode ter sobrado' >&2
  echo 'A stack de desenvolvimento foi substituída pela de e2e: rode `docker compose up -d` para voltá-la.'
}
trap cleanup EXIT

echo "== stack de e2e (banco de teste)"
./scripts/qa/e2e_stack.sh up
./scripts/qa/e2e_stack.sh seed
./scripts/dev/sync_dev_ca.sh >/dev/null 2>&1 || true
adb -s "$dev" reverse tcp:8443 tcp:443 >/dev/null
adb -s "$dev" reverse tcp:8765 tcp:8765 >/dev/null
iniciar_rele

# Sem o bloco `acs`: a senha do ACS vai por ambiente, nunca pelo argv do flutter test
# (visível em `ps`) nem compilada no APK.
fixtures="$(python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);print(json.dumps(d))")"
echo "== jornada e conexão no emulador"
( cd apps/patient && flutter test integration_test/full_journey_test.dart integration_test/backend_connection_test.dart \
    -d "$dev" --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=E2E_FIXTURES="$fixtures" )

echo "== território (ACS institucional, no host)"
( cd apps/patient
  ACS_MATRICULA="$(python3 -c "import json;print(json.load(open('../../.e2e/fixtures.json'))['acs']['matricula'])")" \
  ACS_PASSWORD="$(python3 -c "import json;print(json.load(open('../../.e2e/fixtures.json'))['acs']['password'])")" \
  E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" dart run tool/territory_check.dart )

if [[ "$push" -eq 1 ]]; then
  # push_e2e.sh sobe a própria stack de e2e (fixtures novas): derruba esta antes.
  kill "$relay_pid" 2>/dev/null || true; relay_pid=""
  ./scripts/qa/e2e_stack.sh down >/dev/null 2>&1
  echo "== push (Gorush e FCM reais)"
  ./scripts/qa/push_e2e.sh --e2e-db --negativos
fi
echo 'OK — teste completo do app do paciente contra o banco de teste'
