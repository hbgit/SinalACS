#!/usr/bin/env bash
#
# Prova que um APK do ACS não leva chave privada de cliente (#94).
#
#   ./scripts/qa/acs_apk_no_client_key.sh --debug              # apps/acs/build/.../app-debug.apk
#   ./scripts/qa/acs_apk_no_client_key.sh --release            # apps/acs/build/.../app-release.apk
#   ./scripts/qa/acs_apk_no_client_key.sh --release caminho.apk
#
# Desde a #94 cada aparelho gera o próprio par de chaves e recebe o certificado
# do backend; o certificado compartilhado de desenvolvimento
# (assets/certs/acs_client.{crt,key}) deixou de existir. A guarda do Gradle
# (apps/acs/android/app/build.gradle.kts) barra um release com o arquivo
# acs_client.key no asset, mas olha a ÁRVORE, não o APK: este script olha o que
# de fato foi empacotado, e serve também para o debug, que a guarda não cobre.
#
# Três conferências, todas sobre o APK:
#   1. nenhuma entrada assets/certs/acs_client.* (nem .crt: o certificado
#      compartilhado não pode voltar por um asset esquecido de checkout antigo);
#   2. nenhuma entrada contém um bloco PEM de chave privada, e nenhuma tem nome
#      de contêiner de chave (.key, .pem, .p12, .pfx, .pk8, .jks, .bks,
#      .keystore) — cobre o DER, que não tem marcador de texto;
#   3. assets/certs/ tem exatamente dev_ca.crt e dev_rpc_ca.crt.
#
# Por que o PEM inteiro, e não a palavra "PRIVATE KEY": medido no app-debug.apk
# de 2026-10-28, a palavra sozinha aparece em libflutter.so (BoringSSL),
# libsqlcipher.so (OpenSSL), classes*.dex e kernel_blob.bin (as constantes
# '-----BEGIN PRIVATE KEY-----' do basic_utils, que o app usa para gerar o
# próprio par). São nomes de formato, não chaves; um grep pela palavra reprovaria
# todo APK. O que denuncia uma chave é o cabeçalho seguido do corpo em base64.
#
# Sai 1 nomeando cada entrada ofensora — nunca o conteúdo dela. Uma entrada
# que não pôde ser varrida (unzip -p falhou ou o grep errou) também sai 1: a
# conferência falha fechada, nunca diz OK sobre o que não leu. Sai 2 em uso
# errado ou APK ausente.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
saida_apk="$repo_root/apps/acs/build/app/outputs/flutter-apk"

uso() {
  echo 'uso: acs_apk_no_client_key.sh [--debug|--release] [caminho.apk]' >&2
  exit 2
}

modo=debug
apk=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)   modo=debug; shift ;;
    --release) modo=release; shift ;;
    -h|--help) sed -n '/^#/!q; 3,$p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        echo "erro: argumento desconhecido: $1" >&2; uso ;;
    *)         [[ -z "$apk" ]] || uso; apk="$1"; shift ;;
  esac
done
apk="${apk:-$saida_apk/app-$modo.apk}"

if [[ ! -f "$apk" ]]; then
  echo "erro: $apk não existe. Gere o APK antes (./scripts/dev/run_acs.sh --build, ou flutter build apk --release)." >&2
  exit 2
fi
if ! entradas="$(unzip -Z1 "$apk" 2>/dev/null)"; then
  echo "erro: $apk não é um zip legível." >&2
  exit 2
fi

ruim=0
reprova() { echo "REPROVADO: $*" >&2; ruim=1; }

# 1 e 2 (nome) — o nome da entrada basta.
while IFS= read -r e; do
  [[ -n "$e" ]] || continue
  if [[ "$e" =~ (^|/)assets/certs/acs_client\. ]]; then
    reprova "o APK leva o certificado compartilhado de desenvolvimento: $e"
  elif [[ "${e,,}" =~ \.(key|pem|p12|pfx|pk8|jks|bks|keystore)$ ]]; then
    reprova "o APK leva um arquivo com nome de chave: $e"
  fi
done <<<"$entradas"

# 3 — o conteúdo exato de assets/certs/ (os assets Flutter ficam sob
# assets/flutter_assets/ dentro do APK).
prefixo='assets/flutter_assets/assets/certs/'
certs="$(grep -F "$prefixo" <<<"$entradas" | grep -v '/$' | sed "s|^$prefixo||" | sort || true)"
esperado=$'dev_ca.crt\ndev_rpc_ca.crt'
if [[ "$certs" != "$esperado" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    grep -qxF "$f" <<<"$esperado" || reprova "assets/certs/ tem um arquivo a mais: $prefixo$f"
  done <<<"$certs"
  while IFS= read -r f; do
    grep -qxF "$f" <<<"$certs" || reprova "assets/certs/ não tem $f: $prefixo$f"
  done <<<"$esperado"
fi

# 2 (conteúdo) — cada entrada, descomprimida em fluxo. -z: o arquivo inteiro é
# um registro só (binários têm NUL, não quebra de linha que importe), então o
# cabeçalho e o corpo podem estar em linhas diferentes. Cabeçalhos opcionais
# (Proc-Type/DEK-Info do PEM tradicional cifrado) são aceitos entre os dois.
pem_chave='-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----\r?\n(?:[A-Za-z-]+: [^\r\n]*\r?\n)*(?:\r?\n)?[A-Za-z0-9+/=]{40,}'
varridas=0
while IFS= read -r e; do
  [[ -n "$e" && "$e" != */ ]] || continue
  # O unzip trata o nome como padrão: `[`, `*` e `?` viram classe literal.
  padrao="${e//\[/[[]}"; padrao="${padrao//\*/[*]}"; padrao="${padrao//\?/[?]}"
  # Falha FECHADA: só o exit 1 do grep ("nenhuma ocorrência") é aceito como
  # limpo. Um `|| true` aqui engolia também o exit 2 do grep (erro, p.ex. limite
  # de backtracking/JIT do PCRE numa entrada grande) e a falha do `unzip -p`
  # (entrada corrompida ou método não suportado): a contagem saía vazia, virava
  # 0 e o script dizia OK sobre uma entrada que nunca leu. O PIPESTATUS é lido
  # dentro da substituição (fora dela não existe) e vai na última linha.
  resultado="$(unzip -p "$apk" "$padrao" | grep -a -z -c -P -- "$pem_chave"; echo "status ${PIPESTATUS[*]}")"
  read -r _ st_unzip st_grep <<<"$(tail -n 1 <<<"$resultado")"
  n="$(head -n 1 <<<"$resultado")"
  if [[ "$st_unzip" != 0 || ! "$st_grep" =~ ^[01]$ ]]; then
    reprova "não foi possível varrer $e (unzip -p saiu $st_unzip, grep saiu $st_grep)"
    continue
  fi
  varridas=$((varridas + 1))
  [[ "$st_grep" == 1 ]] || reprova "o APK leva uma chave privada PEM dentro de: $e ($n ocorrência(s))"
done <<<"$entradas"

if [[ "$ruim" -ne 0 ]]; then
  echo "FALHOU — $apk leva material de chave de cliente (entradas acima; o conteúdo não é impresso)." >&2
  exit 1
fi
echo "OK — $apk ($modo): $varridas entradas varridas, nenhuma chave privada; assets/certs = dev_ca.crt, dev_rpc_ca.crt"
