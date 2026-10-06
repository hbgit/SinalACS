#!/usr/bin/env bash
#
# Ponta a ponta do RF14 no emulador: o ACS envia um aviso e ele chega à bandeja do
# aparelho, passando por backend -> Gorush -> FCM.
#
#   ./scripts/qa/push_e2e.sh              # caminho feliz
#   ./scripts/qa/push_e2e.sh --negativos  # + token falso/ios, revogação e Gorush parado
#   ./scripts/qa/push_e2e.sh --e2e-db --negativos  # idem, contra o banco de TESTE (sinalacs_e2e)
#
# Com --e2e-db a stack sobe por scripts/qa/e2e_stack.sh (banco de teste efêmero, sem
# login de desenvolvimento): o paciente entra por OTP real (relé local do código) e o
# ACS por matrícula e senha, ambos de fixtures geradas na hora. Nada é escrito no
# banco de desenvolvimento.
#
# Pré-requisitos: emulador `emulator-5554` (com Play Services e internet: Google Play ou
# `google_apis`), a chave da conta de serviço em
# infra/docker/gorush/credentials/fcm-service-account.json e o google-services.json em
# apps/patient/android/app/. Precisa de credenciais reais do projeto Firebase, então só roda
# onde elas existem: na máquina de quem as tem e no job `android-e2e` da CI, que as decodifica
# dos secrets (ver scripts/qa/ci_push_e2e.sh). Sai com 3 quando falta a chave.
#
# Nunca imprime a chave nem o token FCM.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"
# Controle de jobs: cada processo em segundo plano vira um grupo próprio, e `parar_arvore` mata o
# grupo inteiro (o `flutter test` é NETO do subshell que o lança; matar só o subshell o deixava vivo).
set -m
parar_arvore() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"

negativos=0
e2e_db=0
for arg in "$@"; do
  case "$arg" in
    --negativos) negativos=1 ;;
    --e2e-db) e2e_db=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

# -- guarda da chave ---------------------------------------------------------
key=infra/docker/gorush/credentials/fcm-service-account.json
instrucao='No console do Firebase: Configurações do projeto > Contas de serviço > Gerar nova chave privada.
Salve em infra/docker/gorush/credentials/fcm-service-account.json (modo 600) e confira que a API
"Firebase Cloud Messaging API (V1)" está ativada no projeto.'
[[ -f "$key" ]] || { echo "FALTA $key"; echo "$instrucao"; exit 3; }
git check-ignore -q "$key" || { echo "a chave NÃO está ignorada pelo git"; exit 3; }
[[ "$(stat -c %a "$key")" == 600 ]] || { echo "o modo da chave deve ser 600 (chmod 600 $key)"; exit 3; }
python3 - <<'PYEOF' || exit 3
import json, sys
try:
    k = json.load(open('infra/docker/gorush/credentials/fcm-service-account.json'))
    g = json.load(open('apps/patient/android/app/google-services.json'))
except FileNotFoundError as e:
    print('arquivo ausente:', e.filename); sys.exit(1)
assert k.get('type') == 'service_account', 'não é chave de conta de serviço'
assert k.get('project_id') == g['project_info']['project_id'], 'project_id difere do google-services.json'
assert k.get('client_email') and k.get('private_key'), 'chave incompleta'
# No CI o log é público: o project_id não é impresso lá. Nunca imprime a chave.
import os
print('chave ok para o projeto', '(oculto no CI)' if os.environ.get('GITHUB_ACTIONS') == 'true' else k['project_id'])
PYEOF

# O ambiente do shell pode trazer um GORUSH_CREDENTIALS_DIR que é um ARQUIVO (o Compose
# o prioriza sobre o .env e montaria o arquivo como /credentials: o Gorush cai no boot).
if [[ -n "${GORUSH_CREDENTIALS_DIR:-}" && "$GORUSH_CREDENTIALS_DIR" != "$repo_root/infra/docker/gorush/credentials" ]]; then
  echo "aviso: ignorando GORUSH_CREDENTIALS_DIR=$GORUSH_CREDENTIALS_DIR do ambiente (usa o diretório do repositório)"
fi
export GORUSH_CREDENTIALS_DIR="$repo_root/infra/docker/gorush/credentials"
export GORUSH_URL=http://gorush:8088

pg_user="$(grep '^POSTGRES_USER=' .env | cut -d= -f2)"
pg_db="$(grep '^POSTGRES_DB=' .env | cut -d= -f2)"
if [[ "$e2e_db" -eq 1 ]]; then
  psql_q() { ./scripts/qa/e2e_stack.sh psql "$1"; }
else
  psql_q() { docker exec sinalacs-postgres psql -U "$pg_user" -d "$pg_db" -Atc "$1"; }
fi
app=br.com.prismrr.sinalacs.patient
dev=emulator-5554
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

# -- stack -------------------------------------------------------------------
relay_pid=""
# O relé precisa ser ESTE processo: um relé antigo esquecido na porta responderia com código velho.
iniciar_rele() {
  if porta_ocupada 8765; then
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
if [[ "$e2e_db" -eq 1 ]]; then
  echo "== stack de e2e (banco de teste) com o Gorush"
  ./scripts/qa/e2e_stack.sh up
  ./scripts/qa/e2e_stack.sh seed
  iniciar_rele
  export ACS_MATRICULA ACS_PASSWORD E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json"
  ACS_MATRICULA="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['acs']['matricula'])")"
  ACS_PASSWORD="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['acs']['password'])")"
  # Sem o bloco `acs`: a senha do ACS vai por ambiente, nunca pelo argv do flutter test.
  e2e_fixtures="$(python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);d.pop('acsB',None);d.pop('staff',None);print(json.dumps(d))")"
else
  echo "== stack com o perfil push"
  docker compose --profile push up -d --build >/dev/null 2>&1
fi
for _ in $(seq 1 60); do
  [[ "$(docker compose --profile push ps serverpod gorush --format '{{.Status}}' 2>/dev/null | grep -c healthy)" -ge 2 ]] && break
  sleep 3
done
[[ "$(docker compose --profile push ps serverpod gorush --format '{{.Status}}' 2>/dev/null | grep -c healthy)" -ge 2 ]] \
  || { echo 'erro: serverpod e gorush não ficaram saudáveis'; docker compose --profile push ps; exit 1; }

adb -s "$dev" reverse tcp:8443 tcp:443 >/dev/null
adb -s "$dev" reverse tcp:8765 tcp:8765 >/dev/null
hold_pid=""
cleanup() {
  parar_arvore "$hold_pid"
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null || true
  docker compose --profile push start gorush >/dev/null 2>&1 || true
  psql_q 'delete from push_tokens' >/dev/null 2>&1 || true
  # O banco de e2e e o manifesto (com a senha do ACS) não sobram depois do teste.
  if [[ "$e2e_db" -eq 1 ]]; then
    rm -f .e2e/fixtures.json
    ./scripts/qa/e2e_stack.sh down >/dev/null 2>&1 || echo 'aviso: e2e_stack.sh down falhou; o banco sinalacs_e2e pode ter sobrado (docker exec sinalacs-postgres-test psql -U postgres -c "drop database sinalacs_e2e")' >&2
  fi
}
trap cleanup EXIT

send() { ( cd apps/acs && dart run tool/send_notice.dart --title "SinalACS e2e" --message "$1" 2>&1 | head -2 | tr '\n' ' '; echo "rc=${PIPESTATUS[0]}" ); }

# -- registro real, segurando o app instalado ----------------------------------
# `flutter test` desinstala o app ao terminar e o token FCM morre junto: o teste segura
# o app por PUSH_HOLD_SECONDS depois de registrar, e o envio acontece nesse intervalo.
echo "== registro do token FCM real (segura o app por 240 s)"
psql_q 'delete from push_tokens' >/dev/null
( cd apps/patient && flutter test integration_test/push_register_test.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=PUSH_HOLD_SECONDS=240 --dart-define=PUSH_E2E=1 \
    ${e2e_fixtures:+--dart-define=E2E_FIXTURES="$e2e_fixtures"} \
    > /tmp/push_e2e_hold.txt 2>&1 ) &
hold_pid=$!
for _ in $(seq 1 120); do
  [[ "$(psql_q 'select count(*) from push_tokens' 2>/dev/null | head -1)" -ge 1 ]] && break
  sleep 2
done
[[ "$(psql_q 'select count(*) from push_tokens' | head -1)" -ge 1 ]] \
  || { echo 'erro: o token não foi registrado (veja /tmp/push_e2e_hold.txt)'; exit 1; }
echo "tokens no banco: $(psql_q 'select count(*) from push_tokens' | head -1)"
# O servidor impõe 60 s entre dois pedidos de OTP do MESMO paciente: o registro acabou de
# pedir um, e as chamadas de consentimento abaixo precisam esperar a janela passar.
otp_last="$(date +%s)"
esperar_otp() {
  [[ "$e2e_db" -eq 1 ]] || return 0
  local falta=$(( otp_last + 65 - $(date +%s) ))
  (( falta > 0 )) && { echo "(aguardando ${falta}s: intervalo mínimo entre dois OTP do mesmo paciente)"; sleep "$falta"; }
  otp_last="$(date +%s)"
}

adb -s "$dev" shell pm grant "$app" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb -s "$dev" shell cmd notification cancel_all >/dev/null 2>&1 || true
# FCM não mostra mensagem de notificação na bandeja com o app em primeiro plano.
adb -s "$dev" shell input keyevent KEYCODE_HOME
sleep 3

# -- caminho feliz --------------------------------------------------------------
echo "== envio do ACS"
saida="$(send 'Teste do Gorush')"
echo "$saida"
grep -q 'recipients=1 accepted=1' <<<"$saida" || { echo 'FALHOU: esperado recipients=1 accepted=1'; exit 1; }
# A entrega pelo FCM leva de 1 a dezenas de segundos: espera o texto aparecer em vez de
# dormir um tempo fixo (um `sleep` curto é uma corrida com a rede do emulador).
na_bandeja() { # $1 = texto que deve estar na bandeja do app; espera até 45 s
  local _ dump
  for _ in $(seq 1 45); do
    # Captura antes de filtrar: `grep -q` fecha o pipe no 1º achado, e sob `pipefail` o
    # SIGPIPE do `grep -A` viraria um "não achou" falso.
    dump="$(adb -s "$dev" shell dumpsys notification --noredact 2>/dev/null || true)"
    grep -A30 "pkg=$app" <<<"$dump" | grep -q "$1" && return 0
    sleep 1
  done
  return 1
}
na_bandeja 'SinalACS e2e' || { echo 'FALHOU: título não está na bandeja'; exit 1; }
na_bandeja 'Teste do Gorush' || { echo 'FALHOU: texto não está na bandeja'; exit 1; }
[[ "$(psql_q "select result from audit_logs where \"resourceType\"='community_notice' order by timestamp desc limit 1" | head -1)" == granted ]] \
  || { echo 'FALHOU: auditoria não é granted'; exit 1; }
echo 'caminho feliz: OK'

# -- casos negativos -------------------------------------------------------------
if [[ "$negativos" -eq 1 ]]; then
  echo "== token falso (android) + token ios, com o real vivo"
  for spec in "repeat('x',150)|android" "repeat('i',64)|ios"; do
    psql_q "insert into push_tokens (\"userId\",\"microAreaId\",token,platform,\"createdAt\",\"updatedAt\") select \"userId\",\"microAreaId\",${spec%%|*},'${spec##*|}',now(),now() from push_tokens limit 1" >/dev/null
  done
  saida="$(send 'Mistura real falso ios')"; echo "$saida"; sleep 8
  [[ "$(psql_q "select count(*) from push_tokens where token=repeat('x',150)" | head -1)" == 0 ]] || { echo 'FALHOU: o token falso não foi podado'; exit 1; }
  [[ "$(psql_q "select count(*) from push_tokens where platform='ios'" | head -1)" == 1 ]] || { echo 'FALHOU: a linha ios foi apagada'; exit 1; }
  na_bandeja 'Mistura real falso ios' || { echo 'FALHOU: o token real não recebeu'; exit 1; }
  echo 'token falso podado, ios mantido, token real recebeu: OK'

  echo "== Gorush parado, com tokens no banco"
  docker compose --profile push stop gorush >/dev/null 2>&1
  antes="$(psql_q 'select count(*) from push_tokens' | head -1)"
  saida="$(send 'Gorush parado')"; echo "$saida"
  grep -q 'rc=2' <<<"$saida" || { echo 'FALHOU: esperado rc=2'; exit 1; }
  grep -q 'Tente de novo' <<<"$saida" || { echo 'FALHOU: a mensagem deveria mandar tentar de novo'; exit 1; }
  [[ "$(psql_q 'select count(*) from push_tokens' | head -1)" == "$antes" ]] || { echo 'FALHOU: algum token foi apagado'; exit 1; }
  docker compose --profile push start gorush >/dev/null 2>&1
  echo 'Gorush parado: OK'

  echo "== revogar zera os destinatários"
  esperar_otp
  ( cd apps/patient && dart run tool/push_consent.dart --revoke 2>&1 | head -1 )
  [[ "$(psql_q 'select count(*) from push_tokens' | head -1)" == 0 ]] || { echo 'FALHOU: a revogação não apagou os tokens'; exit 1; }
  saida="$(send 'Depois de revogar')"; echo "$saida"
  grep -q 'recipients=0' <<<"$saida" || { echo 'FALHOU: esperado recipients=0'; exit 1; }
  esperar_otp
  ( cd apps/patient && dart run tool/push_consent.dart --grant 2>&1 | head -1 )
  echo 'revogação: OK'
fi

echo
echo 'OK — o aviso chegou ao emulador'
