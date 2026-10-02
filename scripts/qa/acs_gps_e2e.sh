#!/usr/bin/env bash
#
# Permissão de localização do ACS (RF12) no emulador-5554.
#
#   ./scripts/qa/acs_gps_e2e.sh                  # concedida: o app a enxerga (whileInUse)
#   ./scripts/qa/acs_gps_e2e.sh --sem-permissao  # negada DE VEZ (o Geolocator reporta deniedForever): "indisponível", sem travar
#   ... --reinstalar                             # autoriza apagar um app já instalado
#
# O diálogo de permissão é do sistema e o integration_test não o toca: o APK é
# instalado já com a permissão concedida (ou revogada) por `pm` — e `pm grant`
# falha se o manifesto não a declara, que é o defeito que este script guarda.
# NÃO prova a chegada de um fix de GPS: neste AVD nada entrega posição ao app
# (ver o cabeçalho de integration_test/geofence_gps_e2e.dart).
# Roda por `flutter drive`: só ele aceita --use-application-binary (um
# `flutter test` reinstalaria o APK e perderia a concessão), e o APK é
# construído com o próprio teste como alvo.
# Não precisa da stack: o teste usa FakeAcsBackend.
# GUARDA: se o app do ACS já estiver instalado no emulador, o script aborta
# (exit 3) — reinstalar APAGA a fila de visitas offline (SQLCipher) e a chave do
# Keystore do app de desenvolvimento. `--reinstalar` autoriza. O script é dono
# do pacote enquanto roda e o remove ao sair, para a próxima rodada não esbarrar
# na própria guarda.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"
cd apps/acs

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
apk=build/app/outputs/flutter-apk/app-debug.apk
expect=granted
reinstalar=0
for arg in "$@"; do
  case "$arg" in
    --sem-permissao) expect=denied_forever ;;
    --reinstalar) reinstalar=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

instalado() { adb -s "$dev" shell pm list packages "$pkg" 2>/dev/null | grep -q "^package:$pkg\$"; }
if instalado && [[ "$reinstalar" -eq 0 ]]; then
  echo "erro: $pkg já está instalado em $dev." >&2
  echo "      Reinstalar APAGA a fila de visitas offline (SQLCipher) e a chave do Keystore deste aparelho." >&2
  echo "      Se for só o app de teste de uma execução anterior, rode de novo com --reinstalar." >&2
  exit 3
fi

log="$(mktemp)"
amostras=""
toques=""
amostrador=""
instalamos=0
limpar() {
  # Mata e ESPERA o tocador antes de apagar: o laço dele recria o arquivo de toques com `>>`.
  if [[ -n "$amostrador" ]]; then
    kill "$amostrador" 2>/dev/null || true
    wait "$amostrador" 2>/dev/null || true
  fi
  rm -f "$log" "$amostras" "$toques"
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# O EXPECT_PERMISSION é fixado AQUI, no build: o `flutter drive` abaixo usa o APK pronto
# (--use-application-binary) e não recompila, então um dart-define no drive não teria efeito.
if ! flutter build apk --debug --target=integration_test/geofence_gps_e2e.dart \
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
    --dart-define=EXPECT_PERMISSION="$expect" >"$log" 2>&1; then
  echo "erro: o build do APK falhou. Últimas linhas:" >&2
  tail -n 30 "$log" >&2
  exit 1
fi
if instalado; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
adb -s "$dev" install -r "$apk" >/dev/null
instalamos=1
# Toca em "Não permitir" no diálogo de permissão do sistema, se ele estiver na tela.
tocar_recusar() {
  local xml xy
  xml="$(adb -s "$dev" exec-out uiautomator dump /dev/tty 2>/dev/null || true)"
  # O XML vai por stdin (um dump grande estoura o argv) e toda falha aqui é engolida: o tocador
  # roda num subshell com `set -e`, e se ele morrer em silêncio o diálogo fica sem ninguém e o
  # teste espera para sempre.
  xy="$(printf '%s' "$xml" | python3 "$repo_root/scripts/qa/acha_botao_recusar.py" 2>/dev/null || true)"
  if [[ -n "$xy" ]]; then
    echo tap >>"$toques"
    adb -s "$dev" shell input tap $xy || true
  fi
  return 0
}

if [[ "$expect" == granted ]]; then
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
    adb -s "$dev" shell pm grant "$pkg" "android.permission.$p"
  done
else
  for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
    adb -s "$dev" shell pm revoke "$pkg" "android.permission.$p" || true
  done
fi

# O teste de widget do Flutter injeta toques no próprio Flutter e NÃO percebe um diálogo
# do sistema aberto por cima do app. Quem percebe é o foco da janela, amostrado durante a execução.
# No cenário `denied_forever` o diálogo é ESPERADO: o tocador abaixo o recusa, 2 vezes (as duas
# recusas que fixam a negação). O teste ainda faz um 3º pedido depois de abrir o painel, que com a
# negação fixada volta na hora, sem diálogo: se o diálogo reaparecesse, o tocador o recusaria de novo
# e a contagem passaria de $max_toques. A contagem é o que detecta isso; ela NÃO confere a flag
# USER_FIXED do Android.
intervalo="${GPS_E2E_INTERVALO:-1}"
max_toques=2
amostras="$(mktemp)"
toques="$(mktemp)"
amostrar() { adb -s "$dev" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus >>"$amostras" || true; }
if [[ "$expect" == granted ]]; then
  ( while true; do amostrar; sleep "$intervalo"; done ) &
else
  ( while true; do tocar_recusar; sleep "$intervalo"; done ) &
fi
amostrador=$!

drive_rc=0
limite="${GPS_E2E_TIMEOUT:-300}"
timeout "$limite" flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/geofence_gps_e2e.dart -d "$dev" \
  --use-application-binary="$apk" || drive_rc=$?
if [[ "$expect" == granted ]]; then amostrar; fi   # uma leitura final garante ao menos uma amostra
kill "$amostrador" 2>/dev/null || true; wait "$amostrador" 2>/dev/null || true; amostrador=""
if grep -q permissioncontroller "$amostras"; then
  echo "erro: o diálogo de permissão do sistema apareceu por cima do app durante o teste." >&2
  exit 1
fi
if [[ "$(wc -l <"$toques")" -gt "$max_toques" ]]; then
  echo "erro: o diálogo de permissão apareceu mais de $max_toques vezes: a permissão não ficou negada de vez." >&2
  exit 1
fi
if [[ "$drive_rc" -eq 124 ]]; then
  echo "erro: o flutter drive excedeu ${limite}s (um diálogo de permissão sem ninguém para recusá-lo?)." >&2
fi
if [[ "$drive_rc" -ne 0 ]]; then exit "$drive_rc"; fi
echo "OK — permissão de localização em runtime ($expect); fix de GPS não verificado"
