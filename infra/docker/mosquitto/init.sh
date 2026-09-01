#!/bin/sh
set -eu

runtime_dir=/mosquitto/runtime
certs_dir="$runtime_dir/certs"
password_file="$runtime_dir/passwordfile"

mkdir -p "$certs_dir"

if [ ! -f "$certs_dir/ca.crt" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
    -keyout "$certs_dir/ca.key" \
    -out "$certs_dir/ca.crt" \
    -subj '/CN=sinalacs-local-ca'
  openssl req -newkey rsa:2048 -nodes \
    -keyout "$certs_dir/server.key" \
    -out "$certs_dir/server.csr" \
    -subj '/CN=mosquitto'
  openssl x509 -req -days 7 \
    -in "$certs_dir/server.csr" \
    -CA "$certs_dir/ca.crt" \
    -CAkey "$certs_dir/ca.key" \
    -CAcreateserial \
    -out "$certs_dir/server.crt"
fi

if [ ! -f "$password_file" ]; then
  mosquitto_passwd -b -c "$password_file" backend "${MQTT_BACKEND_PASSWORD:?MQTT_BACKEND_PASSWORD is required}"
  mosquitto_passwd -b "$password_file" acs-area-12 "${MQTT_ACS_PASSWORD:?MQTT_ACS_PASSWORD is required}"
fi

chmod 755 "$runtime_dir" "$certs_dir"
chmod 644 "$password_file" "$certs_dir"/*.crt "$certs_dir"/*.key