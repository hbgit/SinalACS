#!/usr/bin/env bash
# Funções comuns aos scripts de captura no celular.
#
# adb NÃO está no PATH nesta máquina: fica em ~/Android/Sdk/platform-tools/.
# Todos os scripts fazem `source` deste arquivo em vez de repetir a descoberta.

set -euo pipefail

ADB="${ADB:-$HOME/Android/Sdk/platform-tools/adb}"
VIDEO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$VIDEO_DIR/.." && pwd)"
TAKES_DIR="$VIDEO_DIR/out/takes"

# Alvo do roteiro. Só é forçado quando o aparelho já não estiver nele — mexer
# na geometria de um celular que já está certo é risco sem ganho (e alguns
# aparelhos renderizam mal sob wm size forçado). Ver device_prepare.
TARGET_SIZE="1080x2400"
FORCED_GEOMETRY=0

die() { echo "erro: $*" >&2; exit 1; }
info() { echo "  → $*"; }

require_device() {
  [ -x "$ADB" ] || die "adb não encontrado em $ADB (defina ADB=/caminho/para/adb)"
  local n
  n="$("$ADB" devices | awk 'NR>1 && $2=="device"' | wc -l)"
  if [ "$n" -eq 0 ]; then
    "$ADB" devices >&2
    die "nenhum aparelho autorizado. Ligue o celular, ative a depuração USB e aceite o diálogo de autorização na tela."
  fi
  [ "$n" -eq 1 ] || die "$n aparelhos conectados; deixe apenas um (ou exporte ANDROID_SERIAL)."
  info "aparelho: $("$ADB" shell getprop ro.product.model | tr -d '\r')"
}

# Geometria e barra de status silenciosa. O modo demo fixa relógio e bateria e
# esconde notificações — menos ruído em quadro e tomadas reproduzíveis.
device_prepare() {
  local native
  native="$("$ADB" shell wm size | sed -n 's/.*: *//p' | tr -d '\r' | head -1)"
  if [ "$native" = "$TARGET_SIZE" ]; then
    info "aparelho já é $TARGET_SIZE nativo — nada a forçar"
  else
    info "forçando $TARGET_SIZE (nativo: $native)"
    "$ADB" shell wm size "$TARGET_SIZE"
    FORCED_GEOMETRY=1
  fi

  # NÃO PERTURBE é obrigatório, e não é o mesmo que o modo demo: o modo demo
  # esconde os ÍCONES da barra de status, mas não impede um banner heads-up de
  # aparecer por cima do app. Numa gravação de 2026-09-10 uma notificação
  # pessoal do WhatsApp entrou em quadro, com nome de contato e trecho da
  # mensagem — exatamente o que não pode ir para um vídeo de apresentação.
  info "Não Perturbe LIGADO (bloqueia banners heads-up em quadro)"
  "$ADB" shell cmd notification set_dnd priority >/dev/null 2>&1 \
    || "$ADB" shell settings put global zen_mode 1 >/dev/null 2>&1 || true
  sleep 1

  info "modo demo da barra de status (relógio 12:00, bateria 100%, sem notificações)"
  "$ADB" shell settings put global sysui_demo_allowed 1
  "$ADB" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  "$ADB" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200 >/dev/null
  "$ADB" shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
  "$ADB" shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null
}

# SEMPRE chamado por trap EXIT: deixar o celular do usuário em 1080x2400/420
# depois da gravação seria um estrago silencioso.
device_reset() {
  info "restaurando barra de status do aparelho"
  # Só desfaz o que este script mudou: um `wm size reset` gratuito
  # reconfiguraria um aparelho que já estava correto.
  if [ "$FORCED_GEOMETRY" = "1" ]; then
    info "restaurando geometria"
    "$ADB" shell wm size reset || true
  fi
  "$ADB" shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null || true
  info "Não Perturbe DESLIGADO"
  "$ADB" shell cmd notification set_dnd off >/dev/null 2>&1 \
    || "$ADB" shell settings put global zen_mode 0 >/dev/null 2>&1 || true
  # Se o modo avião foi ligado por cabo, desliga. Se a conexão já caiu, isto
  # falha silenciosamente — e aí só o usuário consegue desligar, na mão.
  "$ADB" shell cmd connectivity airplane-mode disable >/dev/null 2>&1 || true
}

# Sobre adb SEM FIO, ligar o modo avião derruba a própria conexão que estamos
# usando para controlar o aparelho: a gravação morre no meio e o celular fica
# em modo avião, exigindo intervenção manual. Só é seguro por cabo USB.
is_wireless() {
  local serial
  serial="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  case "$serial" in
    *_adb-tls-connect._tcp|*:[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

airplane_on() {
  # Override explícito, para gravar com rede ligada mesmo por cabo (onde o
  # modo avião funcionaria). Existe para que uma escolha do usuário não seja
  # sobrescrita pela autodetecção.
  if [ "${SKIP_AIRPLANE:-0}" = "1" ]; then
    info "modo avião PULADO por SKIP_AIRPLANE=1 (gravando com rede ligada)"
    AIRPLANE_SKIPPED=1
    return 0
  fi
  if is_wireless; then
    echo
    echo "  AVISO: aparelho conectado por adb SEM FIO."
    echo "  O modo avião cortaria esta conexão e abortaria a gravação, então"
    echo "  será PULADO. A cena do registro offline será gravada com rede ligada."
    echo "  Para a prova visual de 'sem rede', conecte por CABO USB e regrave."
    echo
    AIRPLANE_SKIPPED=1
    sleep 1
    return 0
  fi
  info "modo avião LIGADO (prova visual do offline-first)"
  "$ADB" shell cmd connectivity airplane-mode enable
  sleep 3
}

airplane_off() {
  [ "${AIRPLANE_SKIPPED:-0}" = "1" ] && return 0
  "$ADB" shell cmd connectivity airplane-mode disable
  sleep 3
}

tap()   { "$ADB" shell input tap "$1" "$2"; sleep "${3:-1.2}"; }
# `adb shell input text` quebra em espaços não escapados: "Paciente orientada"
# entra como só "Paciente". A convenção do comando é %s para espaço.
type_text() {
  local escaped="${1// /%s}"
  "$ADB" shell input text "$escaped"
  sleep "${2:-0.8}"
}

# screenrecord grava no aparelho e o arquivo é puxado depois; o limite de 3 min
# por gravação é folgado para os nossos blocos de 40 s e 50 s.
start_record() {
  local remote="/sdcard/$1.mp4"
  "$ADB" shell rm -f "$remote" 2>/dev/null || true
  "$ADB" shell screenrecord --bit-rate 12000000 --size "$TARGET_SIZE" --time-limit 180 "$remote" &
  RECORD_PID=$!
  RECORD_REMOTE="$remote"
  sleep 2   # screenrecord leva ~1 s para começar de fato
}

stop_record() {
  sleep 1
  "$ADB" shell pkill -INT screenrecord || true
  wait "$RECORD_PID" 2>/dev/null || true
  sleep 2   # deixa o encoder fechar o container
  mkdir -p "$TAKES_DIR"
  "$ADB" pull "$RECORD_REMOTE" "$TAKES_DIR/$1.mp4"
  "$ADB" shell rm -f "$RECORD_REMOTE"
  info "tomada salva em video/out/takes/$1.mp4"
}

screenshot() {
  mkdir -p "$(dirname "$2")"
  "$ADB" exec-out screencap -p > "$2"
  info "captura salva em $2"
}
