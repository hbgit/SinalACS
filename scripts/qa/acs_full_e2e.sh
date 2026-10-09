#!/usr/bin/env bash
#
# Jornada completa do ACS no emulador-5554, contra o BANCO DE TESTE.
#
#   ./scripts/qa/acs_full_e2e.sh                # renovação do JWT forçada (renewSession)
#   ./scripts/qa/acs_full_e2e.sh --esperar-jwt  # espera o JWT de 15 min vencer de verdade (~16 min a mais)
#
# Sobe a stack de e2e (e2e_stack.sh: banco sinalacs_e2e, sem login de
# desenvolvimento), semeia fixtures sintéticas (UUIDs, CPFs e a senha do ACS
# novos a cada execução), sobe o relé (OTP + credencial do ACS, opt-in) e roda
# integration_test/full_journey_e2e.dart no emulador. Nada é escrito no banco
# de desenvolvimento; o banco e o manifesto são apagados ao final.
#
# O "offline" do e2e é SIMULADO: um decorator de teste recusa só as chamadas de envio de visita, e o gatilho de conectividade é alimentado por um StreamController (não é a rede do aparelho caindo).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

esperar_jwt=false
for arg in "$@"; do
  case "$arg" in
    --esperar-jwt) esperar_jwt=true ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$HOME/.pub-cache/bin"

dev=emulator-5554
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

relay_pid=""
saida_teste="$(mktemp)"
cleanup() {
  rm -f "$saida_teste"
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null || true
  [[ "$esperar_jwt" == true ]] && adb -s "$dev" shell svc power stayon false >/dev/null 2>&1 || true
  rm -f .e2e/fixtures.json   # primeiro: tem a senha do ACS, mesmo se o down falhar
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

# Sem os blocos de credencial (`acs`, `acsB`, `staff`, `coordinator`): as senhas chegam
# pelo relé, nunca pelo argv do flutter test nem no APK.
fixtures="$(python3 -c "import json;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);d.pop('acsB',None);d.pop('staff',None);d.pop('coordinator',None);print(json.dumps(d))")"
acs_id="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['acs']['id'])")"
acs_b_id="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['acsB']['id'])")"

# A espera real do JWT passa de 15 min: a tela não pode apagar (apagar = app em
# segundo plano = bloqueio por inatividade no meio do teste).
if [[ "$esperar_jwt" == true ]]; then
  adb -s "$dev" shell svc power stayon true
fi

echo "== jornada do ACS no emulador"
( cd apps/acs && flutter pub get >/dev/null && flutter test integration_test/full_journey_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
    --dart-define=E2E_FIXTURES="$fixtures" \
    --dart-define=E2E_ESPERAR_JWT="$esperar_jwt" ) 2>&1 | tee "$saida_teste"
[[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo 'erro: a jornada no emulador falhou' >&2; exit 1; }

# Refresh token no SERVIDOR (o teste no aparelho não alcança o banco): a linha
# com o deviceId do aparelho, a rotação, a revogação do "Sair" e a auditoria
# `refresh_granted` da renovação silenciosa e da retomada na partida.
echo "== refresh token no banco de teste"
sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }
exigir() { # <descrição> <mínimo> <sql>
  local n; n="$(sql "$3")"
  echo "  $1: $n"
  [[ "$n" -ge "$2" ]] || { echo "erro: esperado >= $2 ($1)" >&2; exit 1; }
}
exigir 'tokens emitidos com deviceId' 1 \
  "select count(*) from acs_refresh_tokens where \"userId\"='$acs_id' and length(\"deviceId\") > 0"
exigir 'tokens rotacionados' 2 \
  "select count(*) from acs_refresh_tokens where \"userId\"='$acs_id' and \"rotatedAt\" is not null"
exigir 'tokens revogados pelo Sair' 1 \
  "select count(*) from acs_refresh_tokens where \"userId\"='$acs_id' and \"revokedAt\" is not null"
exigir 'audit_logs refresh_granted' 2 \
  "select count(*) from audit_logs where \"userId\"='$acs_id' and \"resourceType\"='session_refresh' and result='refresh_granted'"
negados="$(sql "select count(*) from audit_logs where \"userId\"='$acs_id' and \"resourceType\"='session_refresh' and result like 'denied%'")"
echo "  audit_logs session_refresh negados: $negados"
[[ "$negados" -eq 0 ]] || { echo 'erro: houve renovação negada na jornada' >&2; exit 1; }

# Fila por dono (plano 2026-10-03): a visita que A deixou no aparelho subiu pelo
# envio diferido COM A AUTORIA DE A; a legada (banco v6 plantado no aparelho)
# subiu sem autor, transportada por B; a trilha registra os três eventos e os
# tokens de envio de A (fila zerou) e de B (wipe) foram revogados no servidor.
echo "== fila por dono, envio diferido e legado no banco de teste"
linha="$(grep -o 'E2E_FILA_POR_DONO .*' "$saida_teste" | tail -1)"
[[ -n "$linha" ]] || { echo 'erro: o teste da fila por dono não informou os ids' >&2; exit 1; }
campo() { sed -n "s/.* $1=\([0-9a-fA-F-]*\).*/\1/p" <<<"$linha"; }
visita_a="$(campo visita_a)"; legado="$(campo legado)"
[[ "$(campo acs_a)" == "$acs_id" ]] || { echo 'erro: A no aparelho não é o ACS da fixture' >&2; exit 1; }
[[ "$(campo acs_b)" == "$acs_b_id" ]] || { echo 'erro: B no aparelho não é o segundo ACS da fixture' >&2; exit 1; }
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
igual 'visita de A: acsId|authorship' "$acs_id|acs" \
  "select \"acsId\" || '|' || authorship from visits where \"localId\"='$visita_a'"
igual 'visita legada: acsId nulo|authorship|originDeviceId preenchido' 'nulo|legacyUnclaimed|true' \
  "select coalesce(\"acsId\"::text,'nulo') || '|' || authorship || '|' || (length(coalesce(\"originDeviceId\",'')) > 0)::text from visits where \"localId\"='$legado'"
exigir 'audit_logs visit_deferred_sync de A' 1 \
  "select count(*) from audit_logs where \"userId\"='$acs_id' and result='visit_deferred_sync'"
exigir 'audit_logs visit_legacy_sync (B transportou)' 1 \
  "select count(*) from audit_logs where \"userId\"='$acs_b_id' and result='visit_legacy_sync'"
exigir 'audit_logs visit_legacy_sync_item da visita legada' 1 \
  "select count(*) from audit_logs a join visits v on v.id = a.\"resourceId\" where v.\"localId\"='$legado' and a.result='visit_legacy_sync_item'"
exigir 'token de envio de A revogado (fila zerou)' 1 \
  "select count(*) from acs_upload_tokens where \"userId\"='$acs_id' and \"revokedAt\" is not null"
exigir 'token de envio de B revogado (wipe)' 1 \
  "select count(*) from acs_upload_tokens where \"userId\"='$acs_b_id' and \"revokedAt\" is not null"
igual 'tokens de envio de A ou B ainda ativos' 0 \
  "select count(*) from acs_upload_tokens where \"userId\" in ('$acs_id','$acs_b_id') and \"revokedAt\" is null and \"expiresAt\" > now()"
echo 'OK — jornada completa do ACS contra o banco de teste'
