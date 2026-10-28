#!/usr/bin/env bash
#
# Prova o acs_apk_no_client_key.sh sobre APKs de mentira: zips montados aqui,
# com e sem chave plantada. Hermético — sem Flutter, sem Gradle, sem Docker; só
# zip, unzip e openssl. A chave plantada é descartável e nasce neste teste.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$aqui/acs_apk_no_client_key.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

falha() { echo "FALHOU: $*" >&2; exit 1; }

# Uma chave PEM descartável, e um trecho do corpo dela para conferir que a
# saída do script nunca vaza o conteúdo.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$tmp/descartavel.key" 2>/dev/null
corpo="$(sed -n 2p "$tmp/descartavel.key" | cut -c1-24)"

# APK limpo: as duas CAs em assets/certs e binários com as CONSTANTES que um APK
# real carrega (medido no app-debug.apk de 2026-10-28: a BoringSSL do
# libflutter.so tem "RSA PRIVATE KEY" e o kernel_blob.bin tem as constantes PEM
# do basic_utils). Nenhuma delas é chave — o script não pode reprovar por elas.
monta() {
  local dir="$1"; rm -rf "$dir"
  mkdir -p "$dir/assets/flutter_assets/assets/certs" "$dir/lib/x86_64" "$dir/META-INF"
  echo 'ca do broker (sintética)' >"$dir/assets/flutter_assets/assets/certs/dev_ca.crt"
  echo 'ca do rpc (sintética)' >"$dir/assets/flutter_assets/assets/certs/dev_rpc_ca.crt"
  printf 'ANY PRIVATE KEY\0ENCRYPTED PRIVATE KEY\0RSA PRIVATE KEY\0' >"$dir/lib/x86_64/libflutter.so"
  printf "const BEGIN_PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----';\nconst END = '-----END PRIVATE KEY-----';\n" \
    >"$dir/assets/flutter_assets/kernel_blob.bin"
  echo 'assinatura' >"$dir/META-INF/CERT.RSA"
}
empacota() { local dir="$1" apk="$2"; rm -f "$apk"; (cd "$dir" && zip -qr "$apk" .); }

# roda <apk> [args...] → guarda saída e código; nunca aborta o teste.
roda() {
  local codigo=0
  "$script" "$@" >"$tmp/saida" 2>&1 || codigo=$?
  echo "$codigo"
}
espera() {
  local esperado="$1" caso="$2"; shift 2
  local obtido; obtido="$(roda "$@")"
  [[ "$obtido" == "$esperado" ]] || falha "$caso: esperado exit $esperado, veio $obtido: $(cat "$tmp/saida")"
  if grep -qF -- "$corpo" "$tmp/saida"; then falha "$caso: a saída vazou o conteúdo da chave"; fi
}

echo "== caso 1: APK limpo (com as constantes PEM que um APK real carrega) passa"
monta "$tmp/limpo"; empacota "$tmp/limpo" "$tmp/limpo.apk"
espera 0 "limpo" --debug "$tmp/limpo.apk"
espera 0 "limpo como release" --release "$tmp/limpo.apk"

echo "== caso 2: acs_client.key plantado em assets/certs é recusado e nomeado"
monta "$tmp/plantada"
cp "$tmp/descartavel.key" "$tmp/plantada/assets/flutter_assets/assets/certs/acs_client.key"
empacota "$tmp/plantada" "$tmp/plantada.apk"
espera 1 "chave plantada" --debug "$tmp/plantada.apk"
grep -q 'assets/flutter_assets/assets/certs/acs_client.key' "$tmp/saida" || falha "não nomeou a entrada: $(cat "$tmp/saida")"

echo "== caso 3: só o acs_client.crt legado (sem chave) também é recusado"
monta "$tmp/crt"
echo 'certificado compartilhado (sintético)' >"$tmp/crt/assets/flutter_assets/assets/certs/acs_client.crt"
empacota "$tmp/crt" "$tmp/crt.apk"
espera 1 "acs_client.crt" --debug "$tmp/crt.apk"
grep -q 'acs_client.crt' "$tmp/saida" || falha "não nomeou o acs_client.crt: $(cat "$tmp/saida")"

echo "== caso 4: chave PEM escondida dentro de um binário é recusada e nomeada"
monta "$tmp/binario"
{ printf '\x7fELF\0\0lixo binario\0'; cat "$tmp/descartavel.key"; printf '\0fim'; } >"$tmp/binario/lib/x86_64/libapp.so"
empacota "$tmp/binario" "$tmp/binario.apk"
espera 1 "chave no libapp.so" --release "$tmp/binario.apk"
grep -q 'lib/x86_64/libapp.so' "$tmp/saida" || falha "não nomeou o libapp.so: $(cat "$tmp/saida")"

echo "== caso 5: arquivo a mais em assets/certs é recusado"
monta "$tmp/extra"
echo 'outra ca (sintética)' >"$tmp/extra/assets/flutter_assets/assets/certs/outra.crt"
empacota "$tmp/extra" "$tmp/extra.apk"
espera 1 "certificado a mais" --debug "$tmp/extra.apk"
grep -q 'outra.crt' "$tmp/saida" || falha "não nomeou o arquivo a mais: $(cat "$tmp/saida")"

echo "== caso 6: falta uma das duas CAs em assets/certs"
monta "$tmp/falta"
rm "$tmp/falta/assets/flutter_assets/assets/certs/dev_rpc_ca.crt"
empacota "$tmp/falta" "$tmp/falta.apk"
espera 1 "CA ausente" --debug "$tmp/falta.apk"
grep -q 'dev_rpc_ca.crt' "$tmp/saida" || falha "não disse qual CA falta: $(cat "$tmp/saida")"

echo "== caso 7: contêiner de chave (.p12) fora de assets/certs é recusado"
monta "$tmp/p12"
mkdir -p "$tmp/p12/assets/flutter_assets/assets/outros"
head -c 64 /dev/urandom >"$tmp/p12/assets/flutter_assets/assets/outros/cliente.p12"
empacota "$tmp/p12" "$tmp/p12.apk"
espera 1 "p12" --debug "$tmp/p12.apk"
grep -q 'cliente.p12' "$tmp/saida" || falha "não nomeou o .p12: $(cat "$tmp/saida")"

echo "== caso 8: APK inexistente e argumento inválido saem 2"
espera 2 "APK inexistente" --debug "$tmp/nao-existe.apk"
espera 2 "argumento inválido" --qualquer "$tmp/limpo.apk"

echo "OK — acs_apk_no_client_key.sh: recusa chave, certificado legado e asset a mais; aceita o APK limpo; nunca imprime a chave"
