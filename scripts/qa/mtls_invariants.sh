#!/usr/bin/env bash
#
# O broker MQTT exige certificado de cliente (mTLS) E mantém a senha.
#
#   ./scripts/qa/mtls_invariants.sh
#
# Precisa da stack de desenvolvimento no ar (docker compose up) e do .env.
# Quatro casos, cada um uma publicação de `mosquitto_pub` na porta 8883:
#   A) senha certa, SEM certificado de cliente             -> RECUSADO
#   B) senha certa + certificado assinado pela CA do broker -> ACEITO
#   C) senha certa + certificado de OUTRA CA                -> RECUSADO
#   D) certificado certo + senha errada                     -> RECUSADO
# Nenhum segredo é impresso.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_BACKEND_PASSWORD:?exporte MQTT_BACKEND_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

certs="$repo_root/infra/docker/mosquitto/runtime/certs"
for f in ca.crt backend.crt backend.key; do
  [[ -f "$certs/$f" ]] || { echo "erro: $certs/$f não existe (a stack subiu com o init.sh novo?)." >&2; exit 4; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Certificado "de fora": CA própria e uma folha dela, com o mesmo CN de um usuário real.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$tmp/fora-ca.key" -out "$tmp/fora-ca.crt" \
  -subj '/CN=ca-de-fora' >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$tmp/fora.key" -out "$tmp/fora.csr" -subj '/CN=backend' >/dev/null 2>&1
printf 'extendedKeyUsage=clientAuth\n' >"$tmp/fora.ext"
openssl x509 -req -days 2 -in "$tmp/fora.csr" -CA "$tmp/fora-ca.crt" -CAkey "$tmp/fora-ca.key" \
  -CAcreateserial -extfile "$tmp/fora.ext" -out "$tmp/fora.crt" >/dev/null 2>&1
chmod 644 "$tmp"/*

# Pré-condição: o broker responde a um handshake TLS. Sem isso, "recusado" nos
# casos abaixo seria vácuo (broker parado, porta errada).
if ! openssl s_client -connect localhost:8883 -CAfile "$certs/ca.crt" </dev/null >/dev/null 2>&1; then
  echo "erro: o broker não respondeu ao handshake TLS em localhost:8883 (docker compose up -d?)." >&2
  exit 4
fi

# publicar <senha> [--cert X --key Y]
# Códigos: 0 = aceito; 1 = recusado pelo broker (mosquitto_pub rodou e a saída
# traz a marca de recusa: conexão perdida no handshake TLS ou CONNACK negado);
# 2 = erro de infraestrutura (docker, timeout, imagem) — NUNCA conta como recusa.
# A senha vai pelo ambiente do processo do docker (`-e MQTT_PW`, só o nome), não
# pelo argv; a saída do mosquitto_pub é guardada, nunca impressa.
publicar() {
  local senha="$1"; shift
  local saida rc=0
  saida="$(MQTT_PW="$senha" timeout 20 docker run --rm --network host \
    -v "$certs:/c:ro" -v "$tmp:/f:ro" -e MQTT_PW eclipse-mosquitto:2 \
    sh -c 'mosquitto_pub -h localhost -p 8883 --cafile /c/ca.crt -u backend -P "$MQTT_PW" \
           -t sinalacs/v1/mtls/probe -m x '"$*" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  if [[ "$rc" -eq 5 || "$rc" -eq 7 ]] \
     && grep -qiE 'connection was lost|connection was refused|connection refused|not authori[sz]ed' <<<"$saida"; then
    return 1
  fi
  return 2
}

falhas=0
esperar() { # esperar <aceito|recusado> <nome> <comando...>
  local quer="$1" nome="$2" rc=0; shift 2
  "$@" || rc=$?
  case "$rc" in
    0) got=aceito ;;
    1) got=recusado ;;
    *) echo "erro: $nome — falha de infraestrutura (código $rc), não é recusa do broker." >&2; exit 4 ;;
  esac
  if [[ "$got" == "$quer" ]]; then echo "ok:    $nome ($got)"; else echo "FALHOU: $nome — esperava $quer, foi $got"; falhas=$((falhas + 1)); fi
}

esperar recusado "A) senha certa, sem certificado de cliente" publicar "$MQTT_BACKEND_PASSWORD"
esperar aceito   "B) senha certa + certificado da CA do broker" \
  publicar "$MQTT_BACKEND_PASSWORD" --cert /c/backend.crt --key /c/backend.key
esperar recusado "C) certificado de outra CA" \
  publicar "$MQTT_BACKEND_PASSWORD" --cert /f/fora.crt --key /f/fora.key
esperar recusado "D) certificado certo, senha errada" \
  publicar "senha-errada" --cert /c/backend.crt --key /c/backend.key

[[ "$falhas" -eq 0 ]] && echo "OK — o broker exige certificado de cliente e mantém a senha" || { echo "$falhas falha(s)"; exit 1; }
