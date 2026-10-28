#!/usr/bin/env bash
#
# A build de release do ACS não sai com a chave de debug sem pedir.
#
#   ./scripts/qa/acs_release_signing.sh
#
# Seis cenários, cada um uma ou duas builds de release (~1 min cada):
#   1. sem chave de release e sem a licença de debug  -> a build FALHA, dizendo por quê;
#   2. com -Psinalacs.allowDebugSigning=true          -> assina com "Android Debug";
#   3. com um keystore descartável (criado aqui, em /tmp) por variáveis de ambiente
#                                                     -> assina com o CN do keystore;
#   4. com um assets/certs/acs_client.key PLANTADO     -> a build FALHA (a chave iria no APK);
#      sem ele                                         -> a build PASSA, e o APK é conferido por
#                                                         scripts/qa/acs_apk_no_client_key.sh;
#   5. -Psinalacs.allowDebugSigning=false              -> não libera a assinatura de debug;
#   6. -Psinalacs.allowScreenCapture=true              -> não vale em release.
#
# Desde a #94 não existe mais chave de cliente compartilhada (cada aparelho emite a
# própria), então nenhum cenário precisa de -Psinalacs.allowDevClientKey=true. A guarda
# do Gradle continua como regressão: o cenário 4 planta um arquivo de mentira no lugar
# da chave antiga para provar que ela ainda morde, e o apaga em seguida.
# Nenhum segredo real é tocado: o keystore do cenário 3 nasce e morre neste script, e a
# "chave" do cenário 4 é um texto sem material de chave.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
# Hermético: o .env ou o ambiente do chamador não pode injetar uma chave de
# release nos cenários 1, 2, 4, 5 e 6. O cenário 3 as define por conta própria.
unset SINALACS_KEYSTORE_PATH SINALACS_KEYSTORE_PASSWORD SINALACS_KEY_ALIAS SINALACS_KEY_PASSWORD

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
# A guarda do Gradle olha este arquivo. Um que já exista é sobra de um checkout
# anterior à #94 e faria os cenários 2 e 3 falharem pelo motivo errado: quem o
# apaga é o sync_dev_ca.sh, não este script (que não apaga o que não criou).
chave_dev=apps/acs/assets/certs/acs_client.key
if [[ -e "$chave_dev" ]]; then
  echo "erro: $chave_dev existe (sobra de antes da #94). Rode ./scripts/dev/sync_dev_ca.sh, que a remove, e rode de novo." >&2
  exit 3
fi
# O cenário 4 planta o arquivo; o trap o apaga mesmo se a build for interrompida.
trap 'rm -rf "$tmp"; rm -f "$chave_dev"' EXIT

# O Gradle lê as variáveis SINALACS_KEYSTORE_* do ambiente; nos cenários 1 e 2 elas não existem.
construir() { (cd apps/acs && flutter build apk --release "$@"); }

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

echo "== cenário 4: acs_client.key plantado FALHA o release; sem ele, PASSA =="
mkdir -p "$(dirname "$chave_dev")"
echo 'arquivo plantado pelo acs_release_signing.sh (não é chave)' >"$chave_dev"
if saida="$(construir -Psinalacs.allowDebugSigning=true 2>&1)"; then
  echo "erro: o release passou levando assets/certs/acs_client.key." >&2
  exit 1
fi
grep -q "chave privada de desenvolvimento" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }
rm -f "$chave_dev"
construir -Psinalacs.allowDebugSigning=true >/dev/null \
  || { echo "erro: sem o acs_client.key o release deveria passar." >&2; exit 1; }
./scripts/qa/acs_apk_no_client_key.sh --release "$apk"

echo "== cenário 5: -Psinalacs.allowDebugSigning=false NÃO libera a assinatura de debug =="
if saida="$(construir -Psinalacs.allowDebugSigning=false 2>&1)"; then
  echo "erro: allowDebugSigning=false liberou a build de release sem chave." >&2
  exit 1
fi
grep -q "assinatura de release" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }

echo "== cenário 6: -Psinalacs.allowScreenCapture=true NÃO vale em release =="
if saida="$(construir -Psinalacs.allowDebugSigning=true -Psinalacs.allowScreenCapture=true 2>&1)"; then
  echo "erro: o release aceitou allowScreenCapture=true." >&2
  exit 1
fi
grep -q "captura de tela" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }

echo "OK — release exige chave própria; debug só com licença explícita; um acs_client.key no asset barra o release e o APK sai sem chave de cliente"
