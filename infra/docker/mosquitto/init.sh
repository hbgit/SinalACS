#!/bin/sh
set -eu

runtime_dir=/mosquitto/runtime
certs_dir="$runtime_dir/certs"
password_file="$runtime_dir/passwordfile"

mkdir -p "$certs_dir"

# Nomes pelos quais o broker é alcançado. O certificado PRECISA trazer todos
# como subjectAltName: `dart:io` valida o hostname contra o certificado, e o
# emulador Android alcança o host por 10.0.2.2 — não por "mosquitto", que só
# resolve dentro da rede do Compose. Sem SAN, a handshake TLS do app falha.
#
# Para validar em aparelho físico na LAN, exporte o IP da máquina:
#   MQTT_CERT_SAN_EXTRA='IP:192.168.0.10' docker compose up
san='DNS:mosquitto,DNS:localhost,IP:127.0.0.1,IP:10.0.2.2'
if [ -n "${MQTT_CERT_SAN_EXTRA:-}" ]; then
  san="$san,$MQTT_CERT_SAN_EXTRA"
fi

ca_days=3650
server_days=397

# Renova em vez de só criar. A versão anterior era idempotente por
# `if [ ! -f ]` com validade de 7 dias, o que significa que um certificado
# vencido nunca era substituído: o TLS parava de funcionar sozinho depois de
# uma semana, sem ninguém ter mexido em nada.
needs_ca=0
if [ ! -f "$certs_dir/ca.crt" ] || [ ! -f "$certs_dir/ca.key" ]; then
  needs_ca=1
elif ! openssl x509 -in "$certs_dir/ca.crt" -noout -checkend 2592000 >/dev/null 2>&1; then
  echo 'CA de desenvolvimento expira em menos de 30 dias; regerando.'
  needs_ca=1
fi

if [ "$needs_ca" -eq 1 ]; then
  echo 'Gerando CA de desenvolvimento...'
  openssl req -x509 -newkey rsa:2048 -nodes -days "$ca_days" \
    -keyout "$certs_dir/ca.key" \
    -out "$certs_dir/ca.crt" \
    -subj '/CN=sinalacs-local-ca'
  # A CA mudou, então o certificado do servidor assinado pela antiga não serve.
  rm -f "$certs_dir/server.crt" "$certs_dir/server.key" "$certs_dir/ca.srl"
fi

needs_server=0
if [ ! -f "$certs_dir/server.crt" ] || [ ! -f "$certs_dir/server.key" ]; then
  needs_server=1
elif ! openssl x509 -in "$certs_dir/server.crt" -noout -checkend 86400 >/dev/null 2>&1; then
  echo 'Certificado do broker expira em menos de 24h; regerando.'
  needs_server=1
elif ! openssl x509 -in "$certs_dir/server.crt" -noout -ext subjectAltName 2>/dev/null \
      | grep -q '10.0.2.2'; then
  echo 'Certificado do broker sem o SAN esperado; regerando.'
  needs_server=1
fi

if [ "$needs_server" -eq 1 ]; then
  echo "Gerando certificado do broker (SAN: $san)..."
  ext_file="$certs_dir/server.ext"
  cat > "$ext_file" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$san
EOF

  openssl req -newkey rsa:2048 -nodes \
    -keyout "$certs_dir/server.key" \
    -out "$certs_dir/server.csr" \
    -subj '/CN=mosquitto'
  openssl x509 -req -days "$server_days" \
    -in "$certs_dir/server.csr" \
    -CA "$certs_dir/ca.crt" \
    -CAkey "$certs_dir/ca.key" \
    -CAcreateserial \
    -extfile "$ext_file" \
    -out "$certs_dir/server.crt"

  rm -f "$ext_file" "$certs_dir/server.csr"
fi

# Regrava SEMPRE, em vez de só criar quando o arquivo falta.
#
# O arquivo é derivado das variáveis de ambiente, e recriá-lo é barato. Com o
# guard anterior (`if [ ! -f ]`), trocar a senha no .env não tinha efeito algum:
# o broker continuava aceitando apenas a senha antiga, e o backend e o app do
# ACS passavam a falhar na autenticação sem nenhuma pista do motivo — só se
# resolvia apagando runtime/ à mão, o que ninguém adivinha.
#
# O `:?` aborta se a variável faltar. Antes essa proteção era nominal, porque o
# docker-compose.yml sempre injetava um default embutido; agora o compose exige
# o valor do .env, então o guard passa a valer de verdade.
# `mosquitto_passwd -c` no Mosquitto 2.1 RECUSA sobrescrever um arquivo
# existente ("File exists"), então apagar antes é parte do "regravar sempre".
rm -f "$password_file"
mosquitto_passwd -b -c "$password_file" backend "${MQTT_BACKEND_PASSWORD:?MQTT_BACKEND_PASSWORD is required}"
mosquitto_passwd -b "$password_file" acs-area-12 "${MQTT_ACS_PASSWORD:?MQTT_ACS_PASSWORD is required}"

chmod 755 "$runtime_dir" "$certs_dir"
chmod 644 "$password_file" "$certs_dir"/*.crt "$certs_dir"/*.key
