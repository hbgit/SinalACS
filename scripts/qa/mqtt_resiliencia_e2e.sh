#!/usr/bin/env bash
#
# Resiliência da conexão MQTT do backend (issue #56): cenários de DIAGNÓSTICO
# contra a stack local em execução (sinalacs-serverpod + sinalacs-mosquitto).
#
#   ./scripts/qa/mqtt_resiliencia_e2e.sh A [N]   # docker pause do backend por PAUSA s (padrão 120)
#   ./scripts/qa/mqtt_resiliencia_e2e.sh B [N]   # docker restart do Mosquitto
#   ./scripts/qa/mqtt_resiliencia_e2e.sh C [N]   # broker desconectado da rede por PARTICAO s (padrão 100)
#   ./scripts/qa/mqtt_resiliencia_e2e.sh todos   # A(5) + B(3) + C(3)
#
# Variáveis: PAUSA, PARTICAO, ART (diretório de artefatos; padrão em /tmp).
#
# O que mede por execução: estado e exit code do container do backend,
# FinishedAt (e se coincide com o unpause), RestartCount, se o processo segue
# vivo, tempo até o broker registrar um novo `sinalacs-backend-*` e o erro do
# log do backend SANITIZADO (sem host/porta/IP; ficam tipo de exceção, errno e
# nomes de quadros da pilha). Para execuções em que o backend cai, o log
# completo (sanitizado) vai para $ART/<cenario><n>.crash.log.
#
# ATENÇÃO: mexe em sinalacs-serverpod e sinalacs-mosquitto (pause, restart,
# desconexão da rede). O container do backend tem RestartPolicy=no: se o
# processo cair, ele NÃO volta sozinho; o script o religa com `docker start` e
# registra isso. NÃO cria alertas (isso é da Tarefa 10) e não apaga volumes.
# O `trap` sempre: unpause, reconecta o broker com o alias `mosquitto`,
# `docker compose up -d` e confere `docker compose ps`.
set -euo pipefail
cd "$(dirname "$0")/../.."

BACK=sinalacs-serverpod
BROKER=sinalacs-mosquitto
PAUSA="${PAUSA:-120}"
PARTICAO="${PARTICAO:-100}"
ART="${ART:-/tmp/mqtt_resiliencia.$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$ART"
REDE=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$BROKER")

# Remove IPs, host:porta e nomes de host do texto; mantém exceções, errno e quadros.
sanitiza() {
  sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?/<ip>/g; s/(address|host|port) = [^,)]+/\1 = <x>/g; s/(mosquitto|localhost)(:[0-9]+)?/<host>/g; s/sinalacs-backend-[0-9]+/sinalacs-backend-<id>/g'
}

restaura() {
  set +e
  docker unpause "$BACK" >/dev/null 2>&1
  docker network connect --alias mosquitto --alias "$BROKER" "$REDE" "$BROKER" >/dev/null 2>&1
  [ "$(docker inspect -f '{{.State.Running}}' "$BACK" 2>/dev/null)" = true ] || docker start "$BACK" >/dev/null 2>&1
  docker compose up -d >/dev/null 2>&1
  docker compose ps
}
trap restaura EXIT

estado() { docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}} fin={{.State.FinishedAt}} rc={{.RestartCount}}' "$BACK"; }

# Primeira conexão do backend ao broker depois de $1 (epoch, s); imprime segundos desde $1 ou "n/a".
reconectou_em() {
  local t0=$1 iso linha ts
  iso=${t0%.*}   # epoch inteiro: `--since` sem fuso seria lido no fuso local do cliente
  linha=$(docker logs -t --since "$iso" "$BROKER" 2>&1 | grep 'New client connected.*sinalacs-backend-' | head -1 || true)
  [ -n "$linha" ] || { echo n/a; return; }
  ts=$(date -d "${linha%% *}" +%s.%N)
  awk -v a="$ts" -v b="$t0" 'BEGIN{printf "%.1f", a-b}'
}

# Garante o backend de pé e conectado antes de cada execução.
prepara() {
  [ "$(docker inspect -f '{{.State.Running}}' "$BACK")" = true ] || { echo "backend parado; docker start (registrado)"; docker start "$BACK" >/dev/null; sleep 20; }
  docker unpause "$BACK" >/dev/null 2>&1 || true
  sleep 3
}

registra() { # cenario n t_evento
  local c=$1 n=$2 t0=$3 est vivo rec
  local desde=${t0%.*}
  est=$(estado)
  vivo=$(docker inspect -f '{{.State.Running}}' "$BACK")
  rec=$(reconectou_em "$t0")
  docker logs -t --since "$desde" "$BACK" 2>&1 | sanitiza > "$ART/$c$n.back.log" || true
  docker logs -t --since "$desde" "$BROKER" 2>&1 | sanitiza > "$ART/$c$n.broker.log" || true
  if [ "$vivo" != true ]; then docker logs "$BACK" 2>&1 | sanitiza > "$ART/$c$n.crash.log" || true; fi
  echo "RESULT $c$n vivo=$vivo $est reconectou_apos=${rec}s"
  grep -iE 'Unhandled|Exception|Error|errno|#[0-9]+ ' "$ART/$c$n.back.log" | head -12 | sed 's/^/  log: /' || true
}

cenario_A() { # pausa o backend
  local t0 t1
  prepara; t0=$(date +%s.%N)
  docker pause "$BACK" >/dev/null; sleep "$PAUSA"
  t1=$(date +%s.%N); docker unpause "$BACK" >/dev/null; echo "unpause_epoch=${t1%.*}"
  sleep 15
  registra A "$1" "$t0"
}
cenario_B() { # reinicia o broker
  local t0; prepara; t0=$(date +%s.%N)
  docker restart "$BROKER" >/dev/null
  for t in 5 10 20 40; do sleep "$t"; echo "  t+${t}s $(docker inspect -f '{{.State.Running}} rc={{.RestartCount}}' "$BACK")"; done
  registra B "$1" "$t0"
}
cenario_C() { # tira o broker da rede (descarta sem FIN/RST)
  local t0; prepara; t0=$(date +%s.%N)
  docker network disconnect "$REDE" "$BROKER"; sleep "$PARTICAO"
  echo "  durante: $(docker inspect -f '{{.State.Running}} rc={{.RestartCount}}' "$BACK")"
  docker network connect --alias mosquitto --alias "$BROKER" "$REDE" "$BROKER"
  echo "  alias: $(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$v.Aliases}}{{end}}' "$BROKER")"
  sleep 90
  registra C "$1" "$t0"
}

rodar() { local c=$1 n=$2 i; for i in $(seq "$n"); do echo "== $c$i"; "cenario_$c" "$i"; done; }

case "${1:-}" in
  A) rodar A "${2:-5}" ;;
  B) rodar B "${2:-3}" ;;
  C) rodar C "${2:-3}" ;;
  todos) rodar A 5; rodar B 3; rodar C 3 ;;
  *) echo "uso: $0 A|B|C [N] | todos" >&2; exit 2 ;;
esac
echo "artefatos em $ART"
