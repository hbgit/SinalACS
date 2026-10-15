#!/usr/bin/env bash
#
# Gestão de contas do backoffice (issue #43) no emulador-5554, contra o BANCO DE
# TESTE.
#
#   ./scripts/qa/admin_acs_gestao_e2e.sh
#   DEVICE=0087014315 ./scripts/qa/admin_acs_gestao_e2e.sh   # aparelho físico
#
# Sobe a stack de e2e (e2e_stack.sh: banco sinalacs_e2e, sem login de
# desenvolvimento), semeia fixtures sintéticas — entre elas um coordenador do
# backoffice SEM MFA, com `staff_accounts."ubsId"` preenchido —, sobe o relé
# (que entrega a credencial do administrador em /admin e a do coordenador em
# /coordenador, uma única vez cada) e roda
# apps/admin/integration_test/admin_acs_gestao_e2e.dart no emulador: cadastro de
# ACS com a senha inicial mostrada uma vez, vínculo de microárea, redefinição da
# MFA do ACS e do coordenador, desativação do acesso — cada mutação conferida
# por RPC direto no servidor — e o escopo do papel `coordinator`.
#
# Depois confere no banco de teste o que só o servidor sabe: o ACS desativado ao
# fim, nenhum refresh token vivo dele, a MFA redefinida (colunas `totp*` nulas),
# o código de ativação novo do coordenador e as linhas de auditoria das
# escritas. Nada é escrito no banco de desenvolvimento; o banco de e2e e o
# manifesto são apagados ao final.
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
# Sem E2E_SEED_ADMIN_ALERTS: os 3 alertas do painel são do e2e do login, e o
# seed é compartilhado — sem eles o histograma do painel fica vazio aqui, que é
# o que os testes desta jornada não olham.
./scripts/qa/e2e_stack.sh seed
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

# `|| true`: sob `set -e`/`pipefail` um `python3` sem saída derrubaria o script
# aqui, antes da mensagem de erro do assert que usa a variável.
coord_matricula="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['coordinator']['matricula'])" || true)"

echo "== gestão de contas no emulador"
# `2>&1 | tee /dev/stderr`: a saída é capturada — o script lê a linha marcadora
# que o teste imprime com o nome e a matrícula do ACS criado — E continua
# aparecendo na tela, porque um e2e de vários minutos sem saída nenhuma parece
# travado. Com `pipefail`, o status que chega aqui é o do `flutter test`.
status=0
saida="$( ( cd apps/admin && flutter pub get >/dev/null && flutter test integration_test/admin_acs_gestao_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ ) 2>&1 | tee /dev/stderr )" || status=$?
[[ "$status" -eq 0 ]] || { echo "erro: a gestão de contas no emulador falhou (código $status)" >&2; exit 1; }

# Nome e matrícula do ACS criado saem do aparelho pela linha marcadora (o
# manifesto, com o id, fica no host). O `grep -o` tira qualquer prefixo que o
# repórter do `flutter test` ponha na linha; a partir daí a extração é campo a
# campo, e o nome tem espaços.
# `|| true`: sem correspondência o `grep` sai 1 e, com `pipefail`, mataria o
# script antes do diagnóstico logo abaixo — que é justamente quem diz o que
# faltou.
linha_marcadora="$(grep -o 'E2E_ACS_CRIADO .*' <<< "$saida" | tail -1 || true)"
[[ -n "$linha_marcadora" ]] \
  || { echo 'erro: o teste não informou a matrícula e o nome do ACS criado (linha E2E_ACS_CRIADO)' >&2; exit 1; }
matricula="$(sed -n 's/^E2E_ACS_CRIADO matricula=\([^ ]*\).*/\1/p' <<< "$linha_marcadora" | tail -1)"
nome="$(sed -n 's/^E2E_ACS_CRIADO matricula=[^ ]* nome=\(.*\)$/\1/p' <<< "$linha_marcadora" | tail -1)"
[[ -n "$matricula" && -n "$nome" ]] \
  || { echo "erro: linha marcadora ilegível: $linha_marcadora" >&2; exit 1; }

echo "== gestão de contas no banco de teste (ACS $matricula)"
sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
peloMenos() { # <descrição> <mínimo> <sql>
  local n; n="$(sql "$3")"
  echo "  $1: $n"
  [[ "$n" -ge "$2" ]] || { echo "erro: esperado >= $2 ($1)" >&2; exit 1; }
}

# O ACS continua desativado ao fim (a desativação é a última ação da jornada) e
# a flag é a razão de o login passar a recusar. `::text` porque o psql imprime
# booleano como `t`/`f` cru.
igual 'ACS desativado ao fim' 'false' \
  "select active::text from acs where \"enrollmentId\" = '$matricula'"
# Desativar revoga, na mesma transação, a família de refresh tokens da conta.
igual 'nenhum refresh token vivo do ACS criado' 0 \
  "select count(*) from acs_refresh_tokens t join users u on u.id = t.\"userId\" where u.name = '$nome' and t.\"revokedAt\" is null"
# A MFA do ACS foi redefinida: as quatro colunas `totp*` voltaram a nulo — nem
# segredo ativo, nem segredo pendente de uma ativação começada.
igual 'MFA do ACS criado redefinida (colunas totp* nulas)' 1 \
  "select count(*) from user_credentials uc join users u on u.id = uc.\"userId\" where u.name = '$nome' and uc.\"totpEnabledAt\" is null and uc.\"totpSecretEncrypted\" is null"
# O reset do coordenador emitiu um código de ativação novo pela tela, e o
# escopo do papel continua com UBS.
igual 'código de ativação emitido e escopo com UBS' 'true' \
  "select (\"activationCodeHash\" is not null and \"ubsId\" is not null)::text from staff_accounts where \"enrollmentId\" = '$coord_matricula'"
# A trilha das escritas da gestão: criação, vínculo, (des)ativação e as duas
# redefinições de MFA (o ACS e o coordenador) — cada uma uma linha.
peloMenos 'escritas da gestão auditadas' 5 \
  "select count(*) from audit_logs where \"resourceType\" in ('admin_acs','admin_staff') and \"actionType\" = 'write' and result in ('created','deactivated','micro_area_changed','mfa_reset')"
echo 'OK — gestão de contas do backoffice contra o banco de teste'
