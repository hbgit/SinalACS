#!/usr/bin/env bash
#
# A build de release do ACS não sai com a chave de debug sem pedir.
#
#   ./scripts/qa/acs_release_signing.sh
#
# Três cenários, cada um uma build de release (~1 min):
#   1. sem chave de release e sem a licença de debug  -> a build FALHA, dizendo por quê;
#   2. com -Psinalacs.allowDebugSigning=true          -> assina com "Android Debug";
#   3. com um keystore descartável (criado aqui, em /tmp) por variáveis de ambiente
#                                                     -> assina com o CN do keystore.
# Nenhum segredo real é tocado: o keystore do cenário 3 nasce e morre neste script.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

if [[ -f apps/acs/android/key.properties ]]; then
  echo "erro: apps/acs/android/key.properties existe; ele mudaria o cenário 1. Mova-o para fora e rode de novo." >&2
  exit 3
fi
apksigner="$(ls "$HOME"/Android/Sdk/build-tools/*/apksigner | tail -1)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
apk=apps/acs/build/app/outputs/flutter-apk/app-release.apk
define="--dart-define=SINALACS_MQTT_PASSWORD=$MQTT_ACS_PASSWORD"

# O Gradle lê as variáveis SINALACS_KEYSTORE_* do ambiente; nos cenários 1 e 2 elas não existem.
construir() { (cd apps/acs && flutter build apk --release "$define" "$@"); }

echo "== cenário 1: sem chave de release =="
if saida="$( (unset SINALACS_KEYSTORE_PATH; construir) 2>&1)"; then
  echo "erro: a build de release passou sem chave de release." >&2
  exit 1
fi
grep -q "assinatura de release" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }

echo "== cenário 2: -Psinalacs.allowDebugSigning=true =="
construir -Psinalacs.allowDebugSigning=true >/dev/null
"$apksigner" verify --print-certs "$apk" | grep -q "CN=Android Debug" \
  || { echo "erro: o cenário 2 não assinou com a chave de debug." >&2; exit 1; }

echo "== cenário 3: keystore descartável por variáveis de ambiente =="
keytool -genkeypair -keystore "$tmp/teste.jks" -storepass senhateste -keypass senhateste \
  -alias teste -keyalg RSA -keysize 2048 -validity 2 -dname "CN=SinalACS Teste" >/dev/null 2>&1
SINALACS_KEYSTORE_PATH="$tmp/teste.jks" SINALACS_KEYSTORE_PASSWORD=senhateste \
SINALACS_KEY_ALIAS=teste SINALACS_KEY_PASSWORD=senhateste construir >/dev/null
"$apksigner" verify --print-certs "$apk" | grep -q "CN=SinalACS Teste" \
  || { echo "erro: o cenário 3 não assinou com o keystore informado." >&2; exit 1; }

echo "OK — release exige chave própria; debug só com licença explícita"
