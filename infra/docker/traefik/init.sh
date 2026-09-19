#!/bin/sh
#
# Gera a CA de desenvolvimento do RPC e o certificado do servidor que o
# Traefik apresenta em :443 (RNF04).
#
# CA PRÓPRIA, separada da do Mosquitto: aquela é consumida pelo broker, pelo
# asset do app ACS e pela conexão de saída do backend — três coisas que hoje
# funcionam e são validadas. Unificar as duas é uma limpeza possível, mas
# obrigaria a mexer no init.sh do broker e nos caminhos de runtime/ dele; o
# ganho não paga o risco num requisito que é aditivo.
#
# A CA é PRESERVADA entre subidas, e só o certificado do servidor é regerado a
# cada execução. O que os apps carregam como asset é a CA (copiada por
# scripts/dev/sync_dev_ca.sh): regerá-la a cada `docker compose up` invalidaria
# a cópia dentro do APK e o app passaria a falhar a validação TLS depois de um
# restart da stack, sem ninguém ter mexido em nada — o mesmo modo de falha que
# o init.sh do broker já corrigiu uma vez. Nada aponta para o certificado do
# servidor (o Traefik o lê no boot, e os clientes confiam na CA), então
# regerá-lo é barato e evita que uma mudança de SAN em RPC_CERT_SAN_EXTRA fique
# presa ao valor antigo.
#
# Uso: sh init.sh   (ou pelo serviço `traefik-init` do docker-compose.yml)
set -eu

# Diretório de runtime. Dentro do container é /certs — é o que o serviço
# `traefik-init` do docker-compose.yml monta a partir de
# infra/docker/traefik/runtime —, e o subdiretório `certs` é o que o Traefik
# monta em /certs. Mesma forma do runtime do Mosquitto, onde o init.sh escreve
# em runtime/certs/ e os consumidores montam essa pasta.
runtime_dir="/certs"
certs_subdir=certs
certs_dir="$runtime_dir/$certs_subdir"
mkdir -p "$certs_dir"

# Extensões de SAN. `10.0.2.2` é o host da máquina de desenvolvimento visto de
# dentro do emulador Android, e `localhost` cobre as ferramentas de QA que
# rodam na máquina. Para validar em aparelho físico na LAN:
#   RPC_CERT_SAN_EXTRA='IP:192.168.0.10' docker compose up
san="DNS:localhost,IP:127.0.0.1,IP:10.0.2.2"
if [ -n "${RPC_CERT_SAN_EXTRA:-}" ]; then
  san="$san,${RPC_CERT_SAN_EXTRA}"
fi

ca_days=3650
server_days=825

# Reaproveita a CA existente enquanto ela estiver legível e longe de vencer (30
# dias), como o init.sh do broker. Ver o cabeçalho sobre por que ela não é
# regerada a cada subida.
if [ -f "$certs_dir/ca.crt" ] && [ -f "$certs_dir/ca.key" ] \
   && openssl x509 -in "$certs_dir/ca.crt" -noout -checkend 2592000 >/dev/null 2>&1; then
  echo "CA de desenvolvimento do RPC reaproveitada de $certs_dir/ca.crt."
else
  echo 'Gerando CA de desenvolvimento do RPC...'
  openssl genrsa -out "$certs_dir/ca.key" 4096 2>/dev/null
  openssl req -x509 -new -nodes -key "$certs_dir/ca.key" -sha256 -days "$ca_days" \
    -subj "/C=BR/O=SinalACS Dev/CN=SinalACS Dev RPC CA" \
    -out "$certs_dir/ca.crt"
  # A CA mudou: o certificado do servidor assinado pela antiga não serve, e a
  # serial antiga não deve ser continuada.
  rm -f "$certs_dir/ca.srl" "$certs_dir/server.crt" "$certs_dir/server.key"
fi

openssl genrsa -out "$certs_dir/server.key" 2048 2>/dev/null
openssl req -new -key "$certs_dir/server.key" \
  -subj "/C=BR/O=SinalACS Dev/CN=sinalacs-rpc" \
  -out "$certs_dir/server.csr"

ext_file="$certs_dir/server.ext"
cat > "$ext_file" <<EXT
subjectAltName=$san
extendedKeyUsage=serverAuth
EXT

openssl x509 -req -in "$certs_dir/server.csr" \
  -CA "$certs_dir/ca.crt" -CAkey "$certs_dir/ca.key" -CAcreateserial \
  -out "$certs_dir/server.crt" -days "$server_days" -sha256 \
  -extfile "$ext_file" 2>/dev/null

rm -f "$certs_dir/server.csr" "$ext_file"

echo "CA do RPC e certificado do servidor prontos em $certs_dir (SAN: $san)."
openssl x509 -in "$certs_dir/server.crt" -noout -subject -dates -ext subjectAltName
