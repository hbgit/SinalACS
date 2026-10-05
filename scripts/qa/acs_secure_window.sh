#!/usr/bin/env bash
#
# A janela do app do ACS tem FLAG_SECURE no emulador-5554 (sem captura de tela,
# gravação nem miniatura nos recentes). A prova é a flag da janela segundo o
# WindowManager (`dumpsys window windows`, linha `fl=`), não a leitura do código.
#
#   ./scripts/qa/acs_secure_window.sh [--reinstalar]
#
# Aborta (exit 3) se o app já está instalado: reinstalar APAGA a fila de visitas
# offline (SQLCipher) e a chave do Keystore do app de desenvolvimento.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
reinstalar=0
for arg in "$@"; do
  case "$arg" in
    --reinstalar) reinstalar=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

instalado() { adb -s "$dev" shell pm list packages "$pkg" 2>/dev/null | grep -q "^package:$pkg\$"; }
if instalado && [[ "$reinstalar" -eq 0 ]]; then
  echo "erro: $pkg já está instalado em $dev; reinstalar APAGA a fila offline e a chave do Keystore." >&2
  echo "      Se for só o app de teste de uma execução anterior, rode com --reinstalar." >&2
  exit 3
fi

log="$(mktemp)"
instalamos=0
limpar() {
  rm -f "$log"
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT

if ! (cd apps/acs && flutter build apk --debug \
      --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" >"$log" 2>&1); then
  echo "erro: o build do APK falhou. Últimas linhas:" >&2
  tail -n 30 "$log" >&2
  exit 1
fi
if instalado; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
adb -s "$dev" install -r apps/acs/build/app/outputs/flutter-apk/app-debug.apk >/dev/null
instalamos=1
adb -s "$dev" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
# Espera a janela do app aparecer (até 40 s), em vez de dormir um tempo fixo.
dump=""
for _ in $(seq 1 40); do
  dump="$(adb -s "$dev" shell dumpsys window windows 2>/dev/null || true)"
  grep -q "^  Window #.*$pkg/" <<<"$dump" && break
  sleep 1
done

# Primeiro `fl=` do bloco da janela do app (a linha `pfl=` é de outra coisa). O
# dumpsys já está numa variável: o awk lê tudo, sem `exit` sobre um pipe (com
# `pipefail` isso podia matar o adb por SIGPIPE e abortar o script).
flags="$(awk -v pkg="$pkg" '
  /^  Window #/ { dentro = index($0, pkg "/") > 0 }
  dentro && /^ +fl=/ && !achou { print; achou = 1 }' <<<"$dump")"
if [[ -z "$flags" ]]; then
  echo "erro: a janela de $pkg não apareceu em dumpsys window (o app abriu?)." >&2
  exit 4
fi
if ! grep -qw SECURE <<<"$flags"; then
  echo "erro: a janela do ACS não tem FLAG_SECURE: $flags" >&2
  exit 1
fi
echo "OK — janela do ACS com FLAG_SECURE"
