#!/usr/bin/env bash
#
# Resiliência da conexão MQTT do backend (issue #56) contra o BANCO DE TESTE,
# com alerta vermelho de verdade criado DURANTE a interrupção do broker.
#
#   ./scripts/qa/mqtt_resiliencia_e2e.sh                          # base + B + C
#   ./scripts/qa/mqtt_resiliencia_e2e.sh --com-pausa-do-backend   # + A (DIAGNÓSTICO)
#
# Opcional e manual (suíte de resiliência; não é job de CI nem check
# obrigatório). Não precisa de emulador.
#
# Cenários (cada um cria UM alerta vermelho pelo RPC do paciente da fixture,
# login OTP real via relé, com `apps/patient/tool/live_check.dart` — o mesmo
# caminho do `e2e.sh`/`patient_full_e2e.sh`, sem duplicar o login):
#   base  sem interrupção: prova que o caminho (RPC -> outbox -> broker) funciona
#         e aquece a compilação do `dart run`.
#   B     reinício do Mosquitto: `docker stop` do broker, alerta criado com o
#         broker parado, `docker start`. O backend recebe FIN/RST na hora.
#   C     broker fora da rede (`docker network disconnect`, descarta sem FIN/RST)
#         por PARTICAO s (padrão 100). DOIS alertas: um logo no começo
#         (C_INICIO, +ATRASO_C s, padrão 5 — o socket já está morto mas o
#         backend ainda não percebeu: é a janela da lacuna H5) e um perto do fim
#         (C_FIM, depois de o keepalive de 30 s ter derrubado a conexão).
#   A     (só com --com-pausa-do-backend; DIAGNÓSTICO, desligado por padrão)
#         `docker pause` do backend por PAUSA s (padrão 120); o alerta é criado
#         logo após o `unpause`. Antes da correção da #56 este cenário derrubava
#         o processo (Broken pipe); fica como diagnóstico, não como regressão
#         padrão, porque congelar o processo não é uma falha realista do broker.
#
# Em cada alerta, depois de restaurar a conexão, afirma:
#   (a) o backend NÃO reiniciou: no ar, `RestartCount == 0` e `StartedAt`
#       igual ao de antes do cenário;
#   (b) a linha do `alert_outbox` daquele alerta chega a `publishedAt IS NOT
#       NULL` em até ESPERA_PUBLICACAO s (padrão 120); só contagens via psql;
#   (c) o broker ENTREGA a mensagem daquele alerta a UM assinante QoS 1 de
#       sessão persistente (id fixo), iniciado ANTES dos alertas no container
#       do broker, com o usuário/certificado do backend. Ele registra, para
#       CADA mensagem recebida, só `hora alert_id` (sintético; nunca outro
#       campo do payload) num arquivo; cada cenário confere que o seu
#       alert_id aparece >= 1 vez e registra quantas (duplicata é reportada,
#       não é falha). Um assinante `-C 1` por consulta engolia a mensagem do
#       OUTRO alerta (o backoff do outbox entrega fora de ordem): ver
#       evidências, "Tarefa 9b-v". O assinante é relançado depois do
#       `docker stop` do B (o arquivo sobrevive ao stop/start). Prova a
#       entrega pelo broker, mais do que o carimbo do outbox (lacuna H5: o
#       outbox marcava publicado sem PUBACK).
#   O CARD NO APP DO ACS NÃO É VERIFICADO AQUI: as fixtures de e2e sorteiam a
#   microárea a cada execução, e este script não provisiona o certificado de
#   aparelho (CN = microárea, #94) que o app precisaria para lê-la.
#   O ciclo broker -> app do ACS fica com `integration_test/red_alert_cycle_test.dart`
#   (stack de desenvolvimento, `e2e.sh --emulator --full`).
#
# Variáveis: PAUSA, PARTICAO, ATRASO_C, ESPERA_PUBLICACAO, ART (artefatos).
#
# ATENÇÃO: substitui a stack de desenvolvimento pela de e2e (e2e_stack.sh; o
# container sinalacs-serverpod é o mesmo) e mexe em sinalacs-mosquitto (stop,
# desconexão da rede) e, com a flag, pausa sinalacs-serverpod. Não apaga
# volumes. O `trap` sempre: despausa o backend, religa o broker à rede com os
# aliases, garante o broker no ar, encerra o relé, apaga a sessão do assinante
# e o manifesto, `e2e_stack.sh down` e `docker compose up -d` (stack de
# desenvolvimento de volta, esperando o backend saudável).
#
# Sem nenhuma coluna protegida na saída: do banco só contagens e booleanos; o
# log do backend guardado em $ART é sanitizado (sem IP/host/porta nem código
# OTP).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

com_pausa_do_backend=false
for arg in "$@"; do
  case "$arg" in
    --com-pausa-do-backend) com_pausa_do_backend=true ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/flutter/bin:$HOME/.pub-cache/bin"

BACK=sinalacs-serverpod
BROKER=sinalacs-mosquitto
PAUSA="${PAUSA:-120}"
PARTICAO="${PARTICAO:-100}"
ATRASO_C="${ATRASO_C:-5}"
ESPERA_PUBLICACAO="${ESPERA_PUBLICACAO:-120}"
ART="${ART:-$(mktemp -d "${TMPDIR:-/tmp}/mqtt_resiliencia.XXXXXX")}"
mkdir -p "$ART"
# Intervalo mínimo entre dois logins OTP do MESMO paciente (o servidor impõe 60 s).
INTERVALO_OTP=65
SUB_ID="qa-resiliencia-$$"
SUB_SH=/tmp/qa-resiliencia-$$.sh   # laço do assinante (idem)
SUB_LOG=/tmp/qa-resiliencia-$$.log # `hora alert_id` de cada entrega (idem)
RESTAURADO_EM=0                    # epoch da restauração do cenário corrente

relay_pid=""
rede=""
cleanup() {
  set +e
  docker unpause "$BACK" >/dev/null 2>&1
  if [[ -n "$rede" ]]; then
    docker network connect --alias mosquitto --alias "$BROKER" "$rede" "$BROKER" >/dev/null 2>&1
  fi
  [[ "$(docker inspect -f '{{.State.Running}}' "$BROKER" 2>/dev/null)" == true ]] || docker start "$BROKER" >/dev/null 2>&1
  # Sessão persistente do assinante: um CONNECT com sessão limpa a descarta.
  if [[ -n "$rede" ]]; then
    parar_assinante
    mqtt_sub -i "$SUB_ID" -t 'sinalacs/v1/qa/fim' -E >/dev/null 2>&1
    docker exec "$BROKER" rm -f "$SUB_SH" "$SUB_LOG" >/dev/null 2>&1
  fi
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null
  rm -f .e2e/fixtures.json   # primeiro: tem as senhas sintéticas, mesmo se o down falhar
  ./scripts/qa/e2e_stack.sh down >/dev/null 2>&1 \
    || echo 'aviso: e2e_stack.sh down falhou; o banco sinalacs_e2e pode ter sobrado' >&2
  echo '== volta da stack de desenvolvimento (docker compose up -d)'
  docker compose up -d >/dev/null 2>&1 || echo 'aviso: docker compose up -d falhou; rode-o à mão' >&2
  for _ in $(seq 1 60); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' "$BACK" 2>/dev/null)" == healthy ]] && break
    sleep 2
  done
  echo "  backend de desenvolvimento: $(docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' "$BACK" 2>/dev/null)"
  echo "artefatos em $ART"
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
rede=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$BROKER")

E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" python3 scripts/qa/otp_relay.py >/dev/null 2>&1 &
relay_pid=$!
for _ in $(seq 1 20); do
  curl -fs http://127.0.0.1:8765/now >/dev/null 2>&1 && break
  sleep 0.25
done
kill -0 "$relay_pid" 2>/dev/null || { echo 'erro: o relé não subiu' >&2; exit 1; }

area_id="$(python3 -c "import json;print(json.load(open('.e2e/fixtures.json'))['microAreaId'])")"
topico="sinalacs/v1/microareas/$area_id/alerts"
(cd apps/patient && dart pub get >/dev/null)

sql() { ./scripts/qa/e2e_stack.sh psql "$1"; }

# Remove IPs, host:porta, nomes de host e códigos OTP; mantém exceções e errno.
sanitiza() {
  sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?/<ip>/g; s/(address|host|port) = [^,)]+/\1 = <x>/g; s/(mosquitto|localhost)(:[0-9]+)?/<host>/g; s/sinalacs-backend-[0-9]+/sinalacs-backend-<id>/g; s/código de acesso: [0-9]{6}/código de acesso: <otp>/g'
}

# Assinante MQTT dentro do container do broker, com a folha `backend` da CA de
# aparelhos (#94; ACL `sinalacs/v1/#`), montada em /mosquitto/devices. Sem
# senha: o broker toma o CN do certificado como usuário. Não é a folha qa-tools
# porque as fixtures de e2e sorteiam a microárea, e a qa-tools só lê a do seed.
mqtt_sub() {
  docker exec "$BROKER" mosquitto_sub -h localhost -p 8883 \
    --cafile /mosquitto/certs/ca.crt --cert /mosquitto/devices/backend.crt --key /mosquitto/devices/backend.key \
    "$@"
}

# Assinante persistente: um laço no container do broker (reconecta se o
# mosquitto_sub sair) que grava `hora alert_id` de CADA mensagem. Só o
# alert_id é extraído; nenhum outro campo do payload chega ao arquivo.
parar_assinante() {
  docker exec "$BROKER" pkill -f "[q]a-resiliencia-$$" >/dev/null 2>&1 || true
}
iniciar_assinante() {
  parar_assinante
  mqtt_sub -c -i "$SUB_ID" -q 1 -t "$topico" -E >/dev/null   # cria a sessão
  docker exec -i "$BROKER" sh -c "cat > $SUB_SH" <<EOF
while :; do
  mosquitto_sub -h localhost -p 8883 \\
    --cafile /mosquitto/certs/ca.crt --cert /mosquitto/devices/backend.crt --key /mosquitto/devices/backend.key \\
    -c -i $SUB_ID -q 1 -t $topico -F '%p' 2>/dev/null |
  while IFS= read -r l; do
    case "\$l" in *'"alert_id":"'*) r=\${l#*'"alert_id":"'}; echo "\$(date +%s) \${r%%\"*}" >> $SUB_LOG ;; esac
  done
  sleep 1
done
EOF
  docker exec -d "$BROKER" sh "$SUB_SH"
  sleep 3   # conecta antes de o primeiro alerta existir
}
iniciar_assinante

# Entregas registradas do alerta $1: "<vezes> <hora da primeira>".
entregas_de() {
  docker exec "$BROKER" sh -c "grep -F ' $1' $SUB_LOG 2>/dev/null | awk 'NR==1{p=\$1} END{print NR+0, p+0}'" 2>/dev/null || echo '0 0'
}

estado_back() { docker inspect -f '{{.State.Running}} {{.State.StartedAt}} rc={{.RestartCount}}' "$BACK" 2>/dev/null || true; }
broker_no_ar() {
  for _ in $(seq 1 30); do
    [[ "$(docker inspect -f '{{.State.Running}}' "$BROKER")" == true ]] && return 0
    sleep 1
  done
  return 1
}

# Primeira conexão do backend ao broker depois de $1 (epoch, s); "n/a" se nenhuma.
reconectou_em() {
  local t0=$1 linha ts
  linha=$(docker logs -t --since "${t0%.*}" "$BROKER" 2>&1 | grep 'New client connected.*sinalacs-backend-' | head -1 || true)
  [[ -n "$linha" ]] || { echo n/a; return; }
  ts=$(date -d "${linha%% *}" +%s.%N)
  awk -v a="$ts" -v b="$t0" 'BEGIN{printf "%.1f", a-b}'
}

# Cria um alerta vermelho como o paciente `main` da fixture (login OTP real).
# Define ALERTA_ID e ALERTA_PUBLICADO (o `published` da resposta do RPC).
ultimo_login=0
criar_alerta() { # <rótulo>
  local rotulo=$1 espera linha
  espera=$(( ultimo_login + INTERVALO_OTP - $(date +%s) ))
  if (( espera > 0 )); then echo "  [script] aguardando ${espera}s (intervalo do OTP)"; sleep "$espera"; fi
  ultimo_login=$(date +%s)
  ALERTA_ID=""; ALERTA_PUBLICADO=""
  ( cd apps/patient && E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" dart run tool/live_check.dart ) \
    >"$ART/$rotulo.live.log" 2>&1 || true
  linha="$(sed -n 's/.*alerta vermelho \.* \([0-9a-fA-F-]\{36\}\) (publicado=\([a-z]*\)).*/\1 \2/p' "$ART/$rotulo.live.log" | head -1)"
  ALERTA_ID="${linha%% *}"; ALERTA_PUBLICADO="${linha##* }"
  if [[ -z "$ALERTA_ID" ]]; then
    echo "erro: o alerta do cenário $rotulo não foi criado; fim do live_check:" >&2
    tail -n 8 "$ART/$rotulo.live.log" | sed 's/^/    /' >&2
    return 1
  fi
  echo "  [script] alerta $rotulo criado ($(date +%T)): $ALERTA_ID publicado_na_resposta=$ALERTA_PUBLICADO"
}

# (c) o broker entregou a mensagem do alerta $1 ao assinante persistente
# (>= 1 vez, até ESPERA_PUBLICACAO s). Define ENTREGAS e ATRASO_ENTREGA (s
# depois de RESTAURADO_EM).
recebido_no_broker() {
  local id=$1 fim r primeira
  ENTREGAS=0; ATRASO_ENTREGA=n/a
  fim=$(( $(date +%s) + ESPERA_PUBLICACAO ))
  while :; do
    r="$(entregas_de "$id")"
    ENTREGAS=${r%% *}; primeira=${r##* }
    if (( ENTREGAS >= 1 )); then
      ATRASO_ENTREGA=$(( primeira - ${RESTAURADO_EM%.*} ))
      return 0
    fi
    (( $(date +%s) < fim )) || return 1
    sleep 2
  done
}

falhas=()
resultados=()
conferir() { # <rótulo> <alertId> <estado antes> <t0 epoch>
  ENTREGAS=0; ATRASO_ENTREGA=n/a
  local rotulo=$1 id=$2 antes=$3 t0=$4 depois="" ok=true publicado=0 tentativas recebido=nao pendente t
  # (a) mesmo processo: no ar, mesmo StartedAt, RestartCount 0 (espera até 30 s).
  for _ in $(seq 1 30); do
    depois="$(estado_back)"
    [[ "$depois" == "$antes" ]] && break
    sleep 1
  done
  if [[ "$depois" != "$antes" || "$depois" != *" rc=0" || "$depois" != true\ * ]]; then
    ok=false
    echo "erro: [$rotulo] o backend reiniciou ou caiu (antes: $antes; agora: ${depois:-ausente}); fim do log:" >&2
    docker logs --tail 20 "$BACK" 2>&1 | sanitiza | sed 's/^/    /' >&2 || true
  fi
  # (b) outbox publicado (só contagem).
  for t in $(seq 1 "$ESPERA_PUBLICACAO"); do
    publicado="$(sql "select count(*) from alert_outbox where \"alertId\" = '$id' and \"publishedAt\" is not null")"
    [[ "$publicado" -ge 1 ]] && break
    sleep 1
  done
  tentativas="$(sql "select coalesce(max(attempts), -1) from alert_outbox where \"alertId\" = '$id'")"
  pendente="$(sql "select count(*) from alerts where id = '$id' and status = 'pending'")"
  [[ "$publicado" -ge 1 ]] || { ok=false; echo "erro: [$rotulo] outbox do alerta $id sem publishedAt após ${ESPERA_PUBLICACAO}s" >&2; }
  # (c) entrega pelo broker.
  if recebido_no_broker "$id"; then recebido=sim; else
    ok=false
    echo "erro: [$rotulo] o broker não entregou a mensagem do alerta $id ao assinante em ${ESPERA_PUBLICACAO}s" >&2
    [[ "$publicado" -ge 1 ]] && echo "  -> outbox marcado como publicado SEM entrega no broker: compatível com a lacuna H5 (sem PUBACK)" >&2
  fi
  docker logs -t --since "${t0%.*}" "$BACK" 2>&1 | sanitiza >"$ART/$rotulo.back.log" || true
  docker logs -t --since "${t0%.*}" "$BROKER" 2>&1 | sanitiza >"$ART/$rotulo.broker.log" || true
  local linha="RESULT $rotulo ok=$ok backend=[$depois] outbox_publicado=$publicado tentativas=$tentativas alerta_pendente=$pendente recebido_no_broker=$recebido entregas=$ENTREGAS atraso_entrega_apos_restauracao=${ATRASO_ENTREGA}s publicado_na_resposta=$ALERTA_PUBLICADO reconectou_apos=$(reconectou_em "$t0")s"
  echo "$linha"
  resultados+=("$linha")
  [[ "$ok" == true ]] || falhas+=("$rotulo")
  grep -iE 'Unhandled|Exception|errno|\[processo\]|adiada' "$ART/$rotulo.back.log" | head -8 | sed 's/^/  log: /' || true
}

cenario_base() {
  local antes t0; echo "== base (sem interrupção)"
  antes="$(estado_back)"; t0=$(date +%s.%N)
  criar_alerta base || { falhas+=(base); return; }
  RESTAURADO_EM=$ultimo_login
  conferir base "$ALERTA_ID" "$antes" "$t0"
}

cenario_B() {
  local antes t0; echo "== B (reinício do Mosquitto, alerta com o broker parado)"
  antes="$(estado_back)"; t0=$(date +%s.%N)
  docker stop "$BROKER" >/dev/null
  echo "  [script] broker parado ($(date +%T))"
  criar_alerta B || true
  docker start "$BROKER" >/dev/null
  broker_no_ar || echo "aviso: o broker não voltou em 30 s" >&2
  echo "  [script] broker de volta ($(date +%T))"
  RESTAURADO_EM=$(date +%s)
  iniciar_assinante   # a parada do broker matou o laço do assinante; o arquivo ficou
  [[ -n "$ALERTA_ID" ]] || { falhas+=(B); return; }
  conferir B "$ALERTA_ID" "$antes" "$t0"
}

cenario_C() {
  local antes t0 id_inicio pub_inicio id_fim="" pub_fim="" resto
  echo "== C (broker fora da rede por ${PARTICAO}s)"
  antes="$(estado_back)"; t0=$(date +%s.%N)
  docker network disconnect "$rede" "$BROKER"
  echo "  [script] broker fora da rede ($(date +%T))"
  sleep "$ATRASO_C"
  criar_alerta C_INICIO || true
  id_inicio="$ALERTA_ID"; pub_inicio="$ALERTA_PUBLICADO"
  # O segundo alerta sai perto do fim, depois do keepalive (30 s) ter acusado a queda.
  resto=$(( ${t0%.*} + PARTICAO - 15 - $(date +%s) ))
  (( resto > 0 )) && sleep "$resto"
  criar_alerta C_FIM || true
  id_fim="$ALERTA_ID"; pub_fim="$ALERTA_PUBLICADO"
  resto=$(( ${t0%.*} + PARTICAO - $(date +%s) ))
  (( resto > 0 )) && sleep "$resto"
  echo "  durante: backend [$(estado_back)]"
  docker network connect --alias mosquitto --alias "$BROKER" "$rede" "$BROKER"
  echo "  [script] broker de volta à rede ($(date +%T))"
  RESTAURADO_EM=$(date +%s)
  if [[ -n "$id_inicio" ]]; then ALERTA_PUBLICADO="$pub_inicio"; conferir C_INICIO "$id_inicio" "$antes" "$t0"; else falhas+=(C_INICIO); fi
  if [[ -n "$id_fim" ]]; then ALERTA_PUBLICADO="$pub_fim"; conferir C_FIM "$id_fim" "$antes" "$t0"; else falhas+=(C_FIM); fi
}

cenario_A() {
  local antes t0; echo "== A (DIAGNÓSTICO: docker pause do backend por ${PAUSA}s)"
  antes="$(estado_back)"; t0=$(date +%s.%N)
  docker pause "$BACK" >/dev/null
  sleep "$PAUSA"
  docker unpause "$BACK" >/dev/null
  echo "  [script] backend despausado ($(date +%T))"
  RESTAURADO_EM=$(date +%s)
  criar_alerta A || { falhas+=(A); return; }
  conferir A "$ALERTA_ID" "$antes" "$t0"
}

cenario_base
cenario_B
cenario_C
if [[ "$com_pausa_do_backend" == true ]]; then cenario_A; fi

echo "== resumo"
printf '%s\n' "${resultados[@]}"
echo "  entregas finais por alerta (assinante persistente; >1 = duplicata, não falha):"
docker exec "$BROKER" sh -c "awk '{n[\$2]++} END{for(i in n) print \"    \" i, n[i]}' $SUB_LOG" 2>/dev/null || true
echo "  (card no app do ACS: NÃO VERIFICADO por este script — ver cabeçalho)"
if (( ${#falhas[@]} > 0 )); then
  echo "FALHOU: ${falhas[*]}" >&2
  exit 1
fi
echo 'OK — o backend atravessou as quedas do broker sem reiniciar e entregou os alertas'
