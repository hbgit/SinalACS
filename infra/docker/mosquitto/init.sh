#!/bin/sh
set -eu

runtime_dir=/mosquitto/runtime
certs_dir="$runtime_dir/certs"

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

# Até a #94 este bloco emitia, pela CA do servidor, as folhas de cliente
# `backend` e `acs-area-12` (esta compartilhada por todo aparelho) e o
# passwordfile do broker. Desde a #94 a identidade MQTT é o certificado da CA
# de aparelhos (bloco abaixo), sem senha: o broker não confia mais na CA do
# servidor para cliente. Apaga o que sobrou de uma stack anterior, para nenhuma
# ferramenta continuar lendo uma credencial que o broker já recusa.
rm -f "$certs_dir/backend.crt" "$certs_dir/backend.key" \
  "$certs_dir/acs-area-12.crt" "$certs_dir/acs-area-12.key" \
  "$runtime_dir/passwordfile"

# --- CA de aparelhos (#94) ----------------------------------------------------
#
# Uma SEGUNDA CA, separada da CA do broker acima: assina o certificado de
# cliente MQTT de cada aparelho do ACS. Quem a opera em tempo de execução é o
# backend (lib/src/infrastructure/pki/openssl_device_ca.dart), que lê ca.key e
# regrava crl.pem — por isso runtime/devices/ é montado no backend (rw) e a
# chave e o diretório pertencem ao uid do `USER app` da imagem do backend,
# medido 1000 em 2026-10-27 (`docker run --rm --entrypoint id <imagem>`).
#
# Além da CA, este bloco emite, pela mesma CA, a folha `backend` (o cliente MQTT
# do servidor) e a `qa-tools` (CN = UUID da microárea do seed, só para as
# ferramentas de QA na máquina; nunca é asset de app). A CRL inicial é vazia,
# vale 30 dias e é assinada pela CA; daí em diante quem a regrava é o backend.
devices_dir="$runtime_dir/devices"
app_uid=1000
device_ca_days=3650
device_leaf_days=397
qa_tools_cn='00000000-0000-4000-8000-000000000003'

mkdir -p "$devices_dir"

# Mesma regra de renovação da CA do broker: falta ou vence em menos de 30 dias.
needs_device_ca=0
if [ ! -f "$devices_dir/ca.crt" ] || [ ! -f "$devices_dir/ca.key" ]; then
  needs_device_ca=1
elif ! openssl x509 -in "$devices_dir/ca.crt" -noout -checkend 2592000 >/dev/null 2>&1; then
  echo 'CA de aparelhos expira em menos de 30 dias; regerando.'
  needs_device_ca=1
fi

if [ "$needs_device_ca" -eq 1 ]; then
  echo 'Gerando CA de aparelhos de desenvolvimento...'
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -days "$device_ca_days" \
    -keyout "$devices_dir/ca.key" \
    -out "$devices_dir/ca.crt" \
    -subj '/CN=sinalacs-dev-devices-ca' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'
  # Tudo o que a CA antiga assinou deixa de servir, inclusive a CRL.
  rm -f "$devices_dir/backend.crt" "$devices_dir/backend.key" \
    "$devices_dir/qa-tools.crt" "$devices_dir/qa-tools.key" \
    "$devices_dir/serial" "$devices_dir/crl.pem"
fi

# Folha de cliente pela CA de aparelhos: mesma regra do issue_client acima
# (falta, vence em 24 h ou não confere com a CA → regera). EC P-256, como as dos
# aparelhos. `serial` é o arquivo de serial do openssl para as folhas deste
# script; as dos aparelhos recebem a serial do backend.
issue_device_client() {
  name="$1"
  cn="$2"
  if [ -f "$devices_dir/$name.crt" ] && [ -f "$devices_dir/$name.key" ] \
     && openssl x509 -in "$devices_dir/$name.crt" -noout -checkend 86400 >/dev/null 2>&1 \
     && openssl verify -CAfile "$devices_dir/ca.crt" "$devices_dir/$name.crt" >/dev/null 2>&1; then
    return 0
  fi
  echo "Gerando certificado de cliente da CA de aparelhos para $name..."
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth\n' \
    > "$devices_dir/$name.ext"
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$devices_dir/$name.key" -out "$devices_dir/$name.csr" -subj "/CN=$cn"
  openssl x509 -req -days "$device_leaf_days" -in "$devices_dir/$name.csr" \
    -CA "$devices_dir/ca.crt" -CAkey "$devices_dir/ca.key" \
    -CAserial "$devices_dir/serial" -CAcreateserial \
    -extfile "$devices_dir/$name.ext" -out "$devices_dir/$name.crt"
  rm -f "$devices_dir/$name.csr" "$devices_dir/$name.ext"
}

issue_device_client backend backend
issue_device_client qa-tools "$qa_tools_cn"

# CRL inicial: só quando falta ou não confere com a CA (a CA mudou). NÃO é
# regravada a cada boot: depois do primeiro, quem a mantém é o backend, e
# sobrescrevê-la aqui por uma vazia desfaria revogações já publicadas.
if [ ! -f "$devices_dir/crl.pem" ] \
   || ! openssl crl -in "$devices_dir/crl.pem" -CAfile "$devices_dir/ca.crt" -noout >/dev/null 2>&1; then
  echo 'Gerando CRL inicial (vazia, 30 dias) da CA de aparelhos...'
  crl_work="$(mktemp -d)"
  : > "$crl_work/index.txt"
  echo '01' > "$crl_work/crlnumber"
  printf '[ ca ]\ndefault_ca = devices\n\n[ devices ]\ndatabase = %s/index.txt\ncrlnumber = %s/crlnumber\ndefault_md = sha256\ncrl_extensions = crl_ext\n\n[ crl_ext ]\nauthorityKeyIdentifier = keyid:always\n' \
    "$crl_work" "$crl_work" > "$crl_work/ca.cnf"
  openssl ca -gencrl -batch -config "$crl_work/ca.cnf" \
    -cert "$devices_dir/ca.crt" -keyfile "$devices_dir/ca.key" \
    -crldays 30 -out "$devices_dir/crl.pem.tmp"
  mv "$devices_dir/crl.pem.tmp" "$devices_dir/crl.pem"
  rm -rf "$crl_work"
fi

# Permissões (regra de PROGRESS.md: chave de CA em 600, o resto em 644). O
# diretório e a crl.pem são do uid do backend, que regrava a CRL por
# temporário + rename (precisa escrever no diretório); a ca.key também é dele,
# em 600 — só o backend (e este script, como root) a lê.
chown "$app_uid" "$devices_dir" "$devices_dir/ca.key" "$devices_dir/crl.pem"
chmod 755 "$devices_dir"
# O glob de .key nunca inclui a ca.key: nem por um instante ela fica 644 (M1).
for key in "$devices_dir"/*.key; do
  [ "$key" = "$devices_dir/ca.key" ] || chmod 644 "$key"
done
chmod 644 "$devices_dir"/*.crt "$devices_dir/crl.pem" "$devices_dir/serial"
chmod 600 "$devices_dir/ca.key"

chmod 755 "$runtime_dir" "$certs_dir"
chmod 644 "$certs_dir"/*.crt "$certs_dir"/*.key
# Exceção: a chave da CA só assina folhas, e quem a lê é este init.sh, como root.
# A server.key fica em 644 porque o broker a lê com outro uid (mosquitto, 1883)
# — regra medida em 2026-10-05; ver PROGRESS.md.
chmod 600 "$certs_dir/ca.key"
