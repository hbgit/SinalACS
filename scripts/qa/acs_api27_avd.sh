#!/usr/bin/env bash
#
# Cria/inicia um AVD em API 24–27 para provar o BiometricPrompt abaixo do
# prompt do sistema (API 28+). Usa google_apis quando existe (API 24–26); a 27 só tem default.
#
#   ./scripts/qa/acs_api27_avd.sh [--api 27] [--criar] [--iniciar]
set -euo pipefail

sdk="$HOME/Android/Sdk"
export PATH="$PATH:$sdk/cmdline-tools/latest/bin:$sdk/emulator:$sdk/platform-tools"

api=27; criar=0; iniciar=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api) api="${2:?--api exige 24..27}"; shift 2 ;;
    --criar) criar=1; shift ;;
    --iniciar) iniciar=1; shift ;;
    *) echo "uso: $0 [--api 24..27] [--criar] [--iniciar]" >&2; exit 2 ;;
  esac
done
[[ "$api" =~ ^2[4-7]$ ]] || { echo "API deve ser 24..27" >&2; exit 2; }

avd="sinalacs_api${api}"
# A API 27 não tem imagem google_apis (só default/AOSP); o BiometricPrompt não
# depende de Play Services, então o variante muda só onde é preciso.
variante=google_apis; [[ "$api" == 27 ]] && variante=default
img="system-images;android-${api};${variante};x86_64"

if [[ $criar -eq 1 ]]; then
  yes | sdkmanager --licenses >/dev/null || true
  sdkmanager "$img"
  echo no | avdmanager create avd -n "$avd" -k "$img" --force
fi
if [[ $iniciar -eq 1 ]]; then
  # Porta fixa 5556 para não colidir com o emulador-5554 dos outros scripts.
  nohup emulator -avd "$avd" -port 5556 -no-snapshot -no-audio >/dev/null 2>&1 &
  adb -s emulator-5556 wait-for-device
  until [[ "$(adb -s emulator-5556 shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; do sleep 2; done
  echo "emulator-5556 pronto (API $api)"
fi
