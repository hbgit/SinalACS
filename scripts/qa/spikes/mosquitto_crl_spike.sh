#!/usr/bin/env bash
#
# Spike da CRL no Mosquitto 2.1.2 (eclipse-mosquitto:2), medido em 2026-10-27
# para a issue #94. Sobe um broker DESCARTÁVEL na porta 18883, com CA, folhas e
# CRL próprias num diretório temporário: não toca a stack de desenvolvimento.
#
#   bash scripts/qa/spikes/mosquitto_crl_spike.sh
#
# Não é teste de regressão (a CI não o roda): é a evidência das decisões do
# desenho do broker, que scripts/qa/mtls_invariants.sh passou a provar contra a
# stack real. As oito etapas e o que se mediu em cada uma:
#   1) A e B, emitidos pela CA, conectam (rc=0).
#   2) uma sessão longa de A (client id acs-dev-A) fica aberta.
#   3) A é revogado e a CRL regravada (tmp + mv) SEM recarga: A continua
#      conectando — o broker só lê a CRL no load ou no SIGHUP.
#   4) SIGHUP: A passa a ser recusado (rc != 0); B continua aceito.
#   5) a sessão longa de A, aberta antes da revogação, SOBREVIVE ao SIGHUP.
#   6) takeover: outro cliente conecta com o client id de A e a sessão de A cai.
#   7) A não reconecta.
#   8) CRL vazia/inválida + SIGHUP TERMINA o broker — por isso o sidecar
#      (infra/docker/mosquitto/crl_reload.sh) valida a CRL antes de sinalizar.
# Também mediu (fora das etapas): com use_identity_as_username o username passa
# a ser o CN e a senha/-u do CONNECT são ignorados; `pattern ... %u` casa com o
# CN; o $CONTROL não tem reload e o mosquitto_signal é só um `kill`.
set -euo pipefail
S="$(mktemp -d)"; mkdir -p "$S/certs/ca" "$S/conf"; cd "$S/certs"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout ca.key -out ca.crt -subj '/CN=dev-ca-aparelhos' >/dev/null 2>&1
touch ca/index.txt; echo 1000 > ca/serial; echo 1000 > ca/crlnumber
cat > ca/openssl.cnf <<CNF
[ca]
default_ca=d
[d]
dir=$S/certs/ca
database=\$dir/index.txt
new_certs_dir=\$dir
serial=\$dir/serial
crlnumber=\$dir/crlnumber
certificate=$S/certs/ca.crt
private_key=$S/certs/ca.key
default_md=sha256
default_days=2
default_crl_days=1
policy=p
[p]
commonName=supplied
[ext]
basicConstraints=CA:FALSE
keyUsage=digitalSignature
extendedKeyUsage=clientAuth
CNF
for d in A B; do openssl req -newkey rsa:2048 -nodes -keyout $d.key -out $d.csr -subj "/CN=device-$d" >/dev/null 2>&1; openssl ca -batch -config ca/openssl.cnf -extensions ext -in $d.csr -out $d.crt >/dev/null 2>&1; done
openssl ca -config ca/openssl.cnf -gencrl -out crl.pem 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj '/CN=localhost' >/dev/null 2>&1
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > server.ext
openssl x509 -req -days 2 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -extfile server.ext -out server.crt >/dev/null 2>&1
chmod 755 ca; chmod 644 ca/* ./*.crt ./*.key crl.pem; chmod 600 ca.key
cat > "$S/conf/mosquitto.conf" <<CONF
listener 18883 0.0.0.0
cafile /certs/ca.crt
certfile /certs/server.crt
keyfile /certs/server.key
crlfile /certs/crl.pem
tls_version tlsv1.3
require_certificate true
use_identity_as_username true
allow_anonymous false
log_dest stdout
log_type all
CONF
docker rm -f crl-spike crl-subA >/dev/null 2>&1 || true
trap 'docker rm -f crl-spike crl-subA >/dev/null 2>&1 || true; rm -rf "$S"' EXIT
docker run -d --name crl-spike -p 18883:18883 -v "$S/certs:/certs:ro" -v "$S/conf/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro" eclipse-mosquitto:2 >/dev/null; sleep 2
# rc != 0 é a recusa medida; `|| rc=$?` para o set -e não abortar o spike nela.
pub() { local rc=0; timeout 10 docker run --rm --network host -v "$S/certs:/c:ro" eclipse-mosquitto:2 mosquitto_pub -h localhost -p 18883 --cafile /c/ca.crt --cert /c/$1.crt --key /c/$1.key -t t/$1 -m x >/dev/null 2>&1 || rc=$?; echo "pub $1 rc=$rc"; }
echo "== 1) antes"; pub A; pub B
echo "== 2) sessão longa de A (client id acs-dev-A)"; docker run -d --name crl-subA --network host -v "$S/certs:/c:ro" eclipse-mosquitto:2 mosquitto_sub -h localhost -p 18883 --cafile /c/ca.crt --cert /c/A.crt --key /c/A.key -i acs-dev-A -t t/# -v >/dev/null; sleep 2
echo "== 3) revoga A, CRL tmp+mv, SEM reload"; openssl ca -config ca/openssl.cnf -revoke A.crt >/dev/null 2>&1; openssl ca -config ca/openssl.cnf -gencrl -out crl.pem.tmp 2>/dev/null; chmod 644 crl.pem.tmp; mv crl.pem.tmp crl.pem; pub A; pub B
echo "== 4) SIGHUP"; docker kill -s HUP crl-spike >/dev/null; sleep 2; pub A; pub B
echo "== 5) sessão longa de A viva?"; docker ps --filter name=crl-subA --format '{{.Status}}'
echo "== 6) takeover: B conecta com o client id de A"; timeout 10 docker run --rm --network host -v "$S/certs:/c:ro" eclipse-mosquitto:2 mosquitto_pub -h localhost -p 18883 --cafile /c/ca.crt --cert /c/B.crt --key /c/B.key -i acs-dev-A -t t/y -m takeover >/dev/null 2>&1 || true; sleep 2; docker ps -a --filter name=crl-subA --format '{{.Status}}'
echo "== 7) A reconecta?"; pub A
echo "== 8) CRL inválida + SIGHUP"; : > crl.pem.tmp; mv crl.pem.tmp crl.pem; docker kill -s HUP crl-spike >/dev/null; sleep 2; docker ps -a --filter name=crl-spike --format '{{.Status}}'; docker logs crl-spike 2>&1 | grep -i terminating || true
