#!/usr/bin/env bash
#
# Permissão de localização do ACS (RF12) no emulador-5554.
#
#   ./scripts/qa/acs_gps_e2e.sh                  # concedida: o app a enxerga (whileInUse)
#   ./scripts/qa/acs_gps_e2e.sh --sem-permissao  # negada: "indisponível", sem travar
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
    --sem-permissao) expect=denied ;;
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
instalamos=0
limpar() {
  rm -f "$log"
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT

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
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
  if [[ "$expect" == granted ]]; then
    adb -s "$dev" shell pm grant "$pkg" "android.permission.$p"
  else
    adb -s "$dev" shell pm revoke "$pkg" "android.permission.$p" || true
  fi
done

flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/geofence_gps_e2e.dart -d "$dev" \
  --use-application-binary="$apk" \
  --dart-define=EXPECT_PERMISSION="$expect"
echo "OK — permissão de localização em runtime ($expect); fix de GPS não verificado"
