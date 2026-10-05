#!/usr/bin/env bash
#
# A build de release do ACS não sai com a chave de debug sem pedir.
#
#   ./scripts/qa/acs_release_signing.sh
#
# Quatro cenários, cada um uma build de release (~1 min):
#   1. sem chave de release e sem a licença de debug  -> a build FALHA, dizendo por quê;
#   2. com -Psinalacs.allowDebugSigning=true          -> assina com "Android Debug";
#   3. com um keystore descartável (criado aqui, em /tmp) por variáveis de ambiente
#                                                     -> assina com o CN do keystore;
#   4. com a chave privada de CLIENTE de desenvolvimento em assets/certs/ e sem a licença
#      -Psinalacs.allowDevClientKey=true               -> a build FALHA (a chave iria no APK).
# Nenhum segredo real é tocado: o keystore do cenário 3 nasce e morre neste script.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
# Hermético: o .env ou o ambiente do chamador não pode injetar uma chave de
# release nos cenários 1, 2 e 4. O cenário 3 as define por conta própria.
unset SINALACS_KEYSTORE_PATH SINALACS_KEYSTORE_PASSWORD SINALACS_KEY_ALIAS SINALACS_KEY_PASSWORD
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

if [[ -f apps/acs/android/key.properties ]]; then
  echo "erro: apps/acs/android/key.properties existe; ele mudaria o cenário 1. Mova-o para fora e rode de novo." >&2
  exit 3
fi
# Maior VERSÃO (sort -V), não a maior em ordem de texto: `9.0.0` > `34.0.0` por texto.
apksigner="$(ls -d "$HOME"/Android/Sdk/build-tools/*/ | sort -V | tail -1)apksigner"
[[ -x "$apksigner" ]] || { echo "erro: apksigner não encontrado em $HOME/Android/Sdk/build-tools" >&2; exit 4; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
apk=apps/acs/build/app/outputs/flutter-apk/app-release.apk
# O guard da chave de desenvolvimento (cenário 4) olha este arquivo. Se não existir
# (sync_dev_ca.sh não rodou), cria um marcador vazio e o remove no trap; se existir,
# é a chave real de dev e fica como está.
chave_dev=apps/acs/assets/certs/acs_client.key
chave_dev_criada=0
if [[ ! -e "$chave_dev" ]]; then
  mkdir -p "$(dirname "$chave_dev")"; : > "$chave_dev"; chave_dev_criada=1
fi
trap 'rm -rf "$tmp"; [[ "$chave_dev_criada" -eq 1 ]] && rm -f "$chave_dev"' EXIT
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
construir -Psinalacs.allowDebugSigning=true -Psinalacs.allowDevClientKey=true >/dev/null
"$apksigner" verify --print-certs "$apk" | grep -q "CN=Android Debug" \
  || { echo "erro: o cenário 2 não assinou com a chave de debug." >&2; exit 1; }

echo "== cenário 3: keystore descartável por variáveis de ambiente =="
keytool -genkeypair -keystore "$tmp/teste.jks" -storepass senhateste -keypass senhateste \
  -alias teste -keyalg RSA -keysize 2048 -validity 2 -dname "CN=SinalACS Teste" >/dev/null 2>&1
SINALACS_KEYSTORE_PATH="$tmp/teste.jks" SINALACS_KEYSTORE_PASSWORD=senhateste \
SINALACS_KEY_ALIAS=teste SINALACS_KEY_PASSWORD=senhateste construir -Psinalacs.allowDevClientKey=true >/dev/null
"$apksigner" verify --print-certs "$apk" | grep -q "CN=SinalACS Teste" \
  || { echo "erro: o cenário 3 não assinou com o keystore informado." >&2; exit 1; }

echo "== cenário 4: chave de cliente de desenvolvimento no release =="
if saida="$(construir -Psinalacs.allowDebugSigning=true 2>&1)"; then
  echo "erro: o release passou levando a chave de desenvolvimento." >&2
  exit 1
fi
grep -q "chave privada de desenvolvimento" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }

echo "== cenário 5: -Psinalacs.allowDebugSigning=false NÃO libera a assinatura de debug =="
if saida="$(construir -Psinalacs.allowDebugSigning=false -Psinalacs.allowDevClientKey=true 2>&1)"; then
  echo "erro: allowDebugSigning=false liberou a build de release sem chave." >&2
  exit 1
fi
grep -q "assinatura de release" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }

echo "OK — release exige chave própria; debug só com licença explícita; a chave de cliente de dev não vai no APK"
