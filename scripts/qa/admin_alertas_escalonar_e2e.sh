#!/usr/bin/env bash
#
# Escalonamento de alerta vermelho vencido e atualização quase em tempo real do
# backoffice (issue #44) no emulador-5554, contra o BANCO DE TESTE.
#
#   ./scripts/qa/admin_alertas_escalonar_e2e.sh
#   ./scripts/qa/admin_alertas_escalonar_e2e.sh --com-regressao-offline   # + jornada offline do ACS
#   DEVICE=0087014315 ./scripts/qa/admin_alertas_escalonar_e2e.sh         # aparelho físico
#
# ATENÇÃO: substitui a stack de desenvolvimento pela de e2e (o container
# sinalacs-serverpod é o mesmo) e PAUSA o backend por ~120 s no meio do teste.
# Ao fim, `docker compose up -d` volta a de desenvolvimento.
#
# Passo a passo manual (o que este script automatiza):
#   1. ./scripts/dev/bootstrap_env.sh            # só se ainda não houver .env
#      docker compose up -d                      # uma vez: gera os certificados do Traefik/Mosquitto
#   2. emulator -avd <avd> -no-snapshot &        # ou um aparelho físico com DEVICE=<serial>
#      adb wait-for-device && adb devices        # deve listar o emulador (serial padrão do DEVICE)
#   3. ./scripts/qa/admin_alertas_escalonar_e2e.sh
#      - e2e_stack.sh up: Postgres sinalacs_e2e, backend (RED_ALERT_ESCALATION_SECONDS=30,
#        docker-compose.e2e.yml), Mosquitto com mTLS, Gorush e Traefik;
#      - seed com E2E_SEED_ALERT_ESCALATION=1: um vermelho pendente disparado há 10 min
#        (já vencido) na UBS do coordenador sintético;
#      - relé (credencial do coordenador em /coordenador, uma vez) e adb reverse;
#      - o teste no aparelho; o script atende as linhas marcadoras dele:
#          E2E_DISPARAR_ALERTA -> (com o Painel aberto e parado) insere o alerta novo
#                                 (triggeredAt = NOW() + 20 s, o `freshLead` da fixture);
#          E2E_CORTAR_BACKEND  -> `docker pause sinalacs-serverpod` por 120 s e unpause;
#        e repete as linhas de evidência E2E_PAINEL_ATUALIZOU (Painel 1 -> 2 pelo
#        pulso, sem troca de aba) e E2E_BOTAO_APARECEU (atraso do botão após o prazo);
#      - conferências no banco de teste e a cadeia de auditoria.
#   4. docker compose up -d                      # volta à stack de desenvolvimento
#
# Por que pausar o backend e não cortar a rede do aparelho: o RPC chega ao
# emulador por `adb reverse` (o canal do adb, não o Wi-Fi/dados do Android), e
# `svc wifi disable` não o derruba. `docker pause` congela o processo: o
# Traefik segura ou recusa as chamadas, o pulso do app estoura o prazo de 20 s
# e o selo aparece; o `unpause` devolve o mesmo processo, com o mesmo banco e o
# mesmo segredo de JWT, então a sessão do coordenador segue válida.
#
# Depois confere no banco de teste o que só o servidor sabe: UMA linha
# `escalated:no_ack_timeout` e UMA `already_escalated:no_ack_timeout` do alerta
# novo, o alerta ainda `pending` com `escalatedBy` = coordenador, o outro
# vencido intocado, ao menos um `monitoring_session_start`, nenhuma linha
# `read` do pulso e um teto para as leituras do coordenador (ver `teto_leituras`),
# e a cadeia de auditoria íntegra. Nada é escrito no banco de desenvolvimento;
# o banco de e2e e o manifesto são apagados ao final.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

regressao_offline=false
for arg in "$@"; do
  case "$arg" in
    --com-regressao-offline) regressao_offline=true ;;
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
pausado=false
saida_teste="$(mktemp)"
cleanup() {
  # Primeiro o backend: um script morto no meio do corte não pode deixá-lo
  # congelado (nem o `down` abaixo, nem a stack de dev o descongelariam).
  [[ "$pausado" == true ]] && docker unpause sinalacs-serverpod >/dev/null 2>&1 || true
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

echo "== stack de e2e (banco de teste, prazo do alerta vermelho de 30 s)"
./scripts/qa/e2e_stack.sh up
# Sem E2E_SEED_ADMIN_ALERTS: o painel desta jornada conta só os dois vermelhos
# do escalonamento (o vencido semeado e o novo inserido no meio do teste).
E2E_SEED_ALERT_ESCALATION=1 ./scripts/qa/e2e_stack.sh seed
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
# `|| true`: sob `set -e`/`pipefail` um `python3` sem saída derrubaria o script
# aqui, antes da mensagem de erro do assert que usa a variável.
fx() { python3 -c "import json,sys;d=json.load(open('.e2e/fixtures.json'));print(eval(sys.argv[1]))" "$1" || true; }
coord_id="$(fx "d['coordinator']['id']")"
acs_id="$(fx "d['acs']['id']")"
area_id="$(fx "d['microAreaId']")"
main_id="$(fx "[p for p in d['patients'] if p['role']=='main'][0]['id']")"
vencido_id="$(fx "d['escalationAlerts']['overdueId']")"
novo_id="$(fx "d['escalationAlerts']['freshId']")"
[[ -n "$coord_id" && -n "$vencido_id" && -n "$novo_id" && -n "$main_id" ]] \
  || { echo 'erro: o manifesto não tem o bloco escalationAlerts (seed antigo?)' >&2; exit 1; }

# O alerta novo, sintético, do paciente `main` na microárea das fixtures,
# inserido por SQL (não por `alerts.createRedAlert`, que exigiria login OTP do
# paciente e o MQTT) e só quando o teste pede: um alerta semeado ou criado
# "agora" antes do build e do login já estaria vencido quando a tela abrisse.
# O `triggeredAt` 20 s À FRENTE do relógio do banco (o `freshLead` de
# `E2eEscalationAlerts`) faz a janela "no prazo" durar 50 s depois do INSERT
# (I): o Painel o conta em ≤ I + 30 s (um pulso), a aba de Alertas abre em
# ≤ I + ~33 s com ele ainda sem botão, e o botão vem no 1º pulso depois de
# I + 50 s. Mesmas colunas do seed (bin/seed_e2e_fixtures.dart).
inserir_alerta_novo() {
  sql "insert into alerts (id, \"patientId\", \"acsId\", \"microAreaId\", \"triggeredAt\", \"riskLevel\", \"locationHash\", status, \"mqttTopic\", \"deviceId\", \"retryCount\", version) values ('$novo_id', '$main_id', '$acs_id', '$area_id', NOW() + interval '20 seconds', 'red', 'hash-e2e', 'pending', 'sinalacs/v1/microareas/$area_id/alerts', 'device-e2e', 0, 0)" >/dev/null
  echo "  [script] alerta novo inserido ($(date +%T))" >&2
}

# O corte: congela o backend pelo tempo que o teste pediu na linha marcadora
# (padrão 120 s; o selo pode levar ~80–90 s para aparecer depois do corte) e o
# devolve. `pausado` garante o unpause no cleanup.
cortar_backend() {
  local segundos
  segundos="$(grep -o 'E2E_CORTAR_BACKEND segundos=[0-9]*' "$saida_teste" | tail -1 | sed 's/.*=//')"
  [[ -n "$segundos" ]] || segundos=120
  docker pause sinalacs-serverpod >/dev/null
  pausado=true
  echo "  [script] backend pausado por ${segundos}s ($(date +%T))" >&2
  sleep "$segundos"
  docker unpause sinalacs-serverpod >/dev/null
  pausado=false
  echo "  [script] backend de volta ($(date +%T))" >&2
}

echo "== escalonamento e tempo real no emulador"
# O teste roda em segundo plano, com a saída num arquivo que o laço abaixo lê
# em tempo real (as linhas marcadoras) e que o `tail` ecoa na tela — um e2e de
# vários minutos sem saída parece travado.
( cd apps/admin && flutter pub get >/dev/null && flutter test integration_test/admin_alertas_escalonar_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=E2E_ALERTA_VENCIDO="$vencido_id" \
    --dart-define=E2E_ALERTA_NOVO="$novo_id" ) >"$saida_teste" 2>&1 &
teste_pid=$!
tail -n +1 -f --pid="$teste_pid" "$saida_teste" >&2 &
eco_pid=$!

disparado=false
cortado=false
while kill -0 "$teste_pid" 2>/dev/null; do
  if [[ "$disparado" == false ]] && grep -q 'E2E_DISPARAR_ALERTA id=' "$saida_teste"; then
    inserir_alerta_novo; disparado=true
  fi
  if [[ "$cortado" == false ]] && grep -q 'E2E_CORTAR_BACKEND segundos=' "$saida_teste"; then
    cortar_backend; cortado=true
  fi
  sleep 1
done
status=0
wait "$teste_pid" || status=$?
teste_pid=""
wait "$eco_pid" 2>/dev/null || true
eco_pid=""
[[ "$status" -eq 0 ]] || { echo "erro: o escalonamento no emulador falhou (código $status)" >&2; exit 1; }
[[ "$disparado" == true && "$cortado" == true ]] \
  || { echo "erro: o script não viu as linhas marcadoras (disparado=$disparado cortado=$cortado)" >&2; exit 1; }
grep -q 'E2E_ESCALONAMENTO_OK' "$saida_teste" \
  || { echo 'erro: o teste terminou sem a linha E2E_ESCALONAMENTO_OK' >&2; exit 1; }
grep -q 'E2E_PAINEL_ATUALIZOU atraso_ms=' "$saida_teste" \
  || { echo 'erro: o teste não provou o Painel atualizado pelo pulso (linha E2E_PAINEL_ATUALIZOU)' >&2; exit 1; }
grep -o 'E2E_PAINEL_ATUALIZOU atraso_ms=[-0-9]*' "$saida_teste" | tail -1 | sed 's/^/  /' || true
grep -o 'E2E_BOTAO_APARECEU atraso_ms=[-0-9]*' "$saida_teste" | tail -1 | sed 's/^/  /' || true

echo "== escalonamento no banco de teste (alerta $novo_id)"
igual() { # <descrição> <esperado> <sql>
  local v; v="$(sql "$3")"
  echo "  $1: $v"
  [[ "$v" == "$2" ]] || { echo "erro: esperado '$2' ($1)" >&2; exit 1; }
}
# Os resultados são os de AlertEscalationService: `escalated:<motivo>` na
# primeira vez e `already_escalated:<motivo pedido>` na repetição por RPC.
igual 'uma linha escalated:no_ack_timeout do alerta novo' 1 \
  "select count(*) from audit_logs where \"resourceType\" = 'admin_alert' and \"actionType\" = 'write' and \"resourceId\" = '$novo_id' and result = 'escalated:no_ack_timeout'"
igual 'uma linha already_escalated:no_ack_timeout do alerta novo' 1 \
  "select count(*) from audit_logs where \"resourceType\" = 'admin_alert' and \"actionType\" = 'write' and \"resourceId\" = '$novo_id' and result = 'already_escalated:no_ack_timeout'"
igual 'nenhuma outra escrita de escalonamento (nem recusa)' 2 \
  "select count(*) from audit_logs where \"resourceType\" = 'admin_alert' and \"actionType\" = 'write'"
igual 'as duas escritas são do coordenador' 'true' \
  "select bool_and(\"userId\" = '$coord_id')::text from audit_logs where \"resourceType\" = 'admin_alert' and \"actionType\" = 'write'"
# Escalonar não confirma: o alerta segue pendente, com quem e por quê.
igual 'alerta novo pendente, escalonado pelo coordenador, sem confirmação' 'true' \
  "select (status = 'pending' and \"escalatedAt\" is not null and \"escalatedBy\" = '$coord_id' and \"escalationReason\" = 'noAckTimeout' and \"acknowledgedAt\" is null)::text from alerts where id = '$novo_id'"
# Reforço (D2): o escalonamento enfileira UMA entrega no outbox; a repetição
# não enfileira outra. O alerta novo nasceu por SQL, sem entrega original.
igual 'um único reforço no outbox para o alerta novo' 1 \
  "select count(*) from alert_outbox where \"alertId\" = '$novo_id'"
igual 'o vencido semeado intocado (pendente, sem escalonamento)' 'true' \
  "select (status = 'pending' and \"escalatedAt\" is null and \"escalatedBy\" is null)::text from alerts where id = '$vencido_id'"
igual 'os dois vermelhos seguem abertos' 2 \
  "select count(*) from alerts where \"riskLevel\" = 'red' and status = 'pending'"

echo "== monitoramento no banco de teste"
peloMenos() { # <descrição> <mínimo> <sql>
  local n; n="$(sql "$3")"
  echo "  $1: $n"
  [[ "$n" -ge "$2" ]] || { echo "erro: esperado >= $2 ($1)" >&2; exit 1; }
}
peloMenos 'monitoring_session_start do coordenador' 1 \
  "select count(*) from audit_logs where \"userId\" = '$coord_id' and \"actionType\" = 'monitoring_session_start' and \"resourceType\" = 'admin_monitoring'"
# O pulso não grava `read`: nenhuma linha do recurso dele fora as recusas
# (uma recusa do pulso grava `read`/`admin_pulse`/`denied`, pelo
# AdminScopeResolver, e é contada à parte do que o pulso bem-sucedido faz).
igual 'nenhuma linha read do pulso' 0 \
  "select count(*) from audit_logs where \"resourceType\" = 'admin_pulse' and \"actionType\" = 'read' and \"result\" <> 'denied'"
# Tetos das leituras do coordenador, por recurso. Esperadas numa execução
# normal (o pulso não grava `read`; só montagens de tela, recargas da lista por
# mudança no pulso e o RPC direto do teste):
#   admin_indicators  3: Painel ao entrar, RPC do teste, volta ao Painel;
#   admin_alerts      7: Alertas ao abrir, recarga do vencimento do novo,
#                        recarga depois do escalonamento + a do pulso imediato
#                        (até 2), RPC do teste (2), Alertas de novo;
#   admin_micro_areas 2: cada montagem de Alertas (a recarga pelo pulso não relê);
#   admin_audit_logs  0: a jornada não abre a Auditoria.
# A execução dura ~6 min (~12 pulsos de 30 s): uma leitura por pulso estouraria
# qualquer um destes tetos, que só têm folga de 1 para um pulso repetido.
teto() { # <recurso> <teto>
  local n
  n="$(sql "select count(*) from audit_logs where \"userId\" = '$coord_id' and \"actionType\" = 'read' and \"resourceType\" = '$1'")"
  echo "  leituras $1 do coordenador: $n (teto $2)"
  [[ "$n" -le "$2" ]] || { echo "erro: $n leituras $1 > teto $2 (algo relê por pulso?)" >&2; exit 1; }
}
teto admin_indicators 4
teto admin_alerts 9
teto admin_micro_areas 3
teto admin_audit_logs 0
teto_leituras=16
n_leituras="$(sql "select count(*) from audit_logs where \"userId\" = '$coord_id' and \"actionType\" = 'read'")"
duracao="$(sql "select coalesce(extract(epoch from max(\"timestamp\") - min(\"timestamp\"))::int, 0) from audit_logs where \"userId\" = '$coord_id'")"
echo "  leituras auditadas do coordenador: $n_leituras em ${duracao}s (~$(( duracao / 30 )) pulsos); teto $teto_leituras (esperado 12)"
[[ "$n_leituras" -le "$teto_leituras" ]] \
  || { echo "erro: $n_leituras leituras > teto $teto_leituras (o pulso voltou a gravar read?)" >&2; exit 1; }

echo "== cadeia de auditoria"
( cd backend/sinalacs_server && set -a && source ../../.env && set +a && \
  SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e \
  SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/audit_chain_check.dart 2>&1 | grep -E 'cadeia|quebra|OK' )
echo 'OK — escalonamento e tempo real do backoffice contra o banco de teste'

if [[ "$regressao_offline" == true ]]; then
  # A jornada offline do ACS (fila por dono, envio diferido, 100 visitas em < 5 s)
  # no banco de teste, para provar que o #44 não regrediu o offline. Ela sobe e
  # derruba a própria stack de e2e e o próprio relé: o nosso sai antes.
  echo "== regressão offline (acs_full_e2e.sh)"
  kill "$relay_pid" 2>/dev/null || true
  wait "$relay_pid" 2>/dev/null || true
  relay_pid=""
  rm -f .e2e/fixtures.json
  ./scripts/qa/acs_full_e2e.sh
fi
