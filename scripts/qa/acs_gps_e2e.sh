#!/usr/bin/env bash
#
# Permissão de localização do ACS (RF12) no emulador-5554.
#
#   ./scripts/qa/acs_gps_e2e.sh                  # concedida: o app a enxerga (whileInUse)
#   ./scripts/qa/acs_gps_e2e.sh --sem-permissao  # negada: "indisponível", sem travar
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
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
[[ -f .env ]] || { echo 'erro: rode ./scripts/dev/bootstrap_env.sh'; exit 1; }
set -a; source .env; set +a   # MQTT_ACS_PASSWORD: o build do APK a exige
cd apps/acs

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
apk=build/app/outputs/flutter-apk/app-debug.apk
expect=granted
[[ "${1:-}" == --sem-permissao ]] && expect=denied
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

flutter build apk --debug --target=integration_test/geofence_gps_e2e.dart \
  --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
  --dart-define=EXPECT_PERMISSION="$expect" >/dev/null
adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true
adb -s "$dev" install -r "$apk" >/dev/null
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
