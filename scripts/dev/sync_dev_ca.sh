#!/usr/bin/env bash
#
# Copia as CAs de desenvolvimento para os assets dos apps.
#
# São DUAS CAs, e de propósito:
#   * a do Mosquitto assina o certificado do broker, e o app ACS a usa para o
#     MQTT em 8883;
#   * a do RPC assina o certificado que o Traefik apresenta em 443, e os dois
#     apps a usam para o HTTPS do backend (RNF04).
#
# `SecurityContext.setTrustedCertificatesBytes` lê bytes (e não um caminho, que
# não existiria dentro do APK), então as CAs entram como asset Flutter.
#
# Nenhuma das duas é versionada: infra/docker/mosquitto/runtime/,
# infra/docker/traefik/runtime/ e apps/*/assets/certs/ estão no .gitignore.
#
# ATENÇÃO à distinção, que o `init.sh` do RPC mediu e o do broker confirma: as
# duas CAs são PRESERVADAS entre subidas — só as folhas são regeradas —, então
# esta cópia continua válida enquanto a CA não expirar. A folha muda, mas o app
# confia na CA, não na folha. Rode este script sempre que subir a stack pela
# primeira vez ou depois de apagar um runtime/.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

copy_ca() {
  local source_ca="$1"
  local target_dir="$2"
  local target_ca="$3"
  local label="$4"

  if [[ ! -f "$source_ca" ]]; then
    echo "erro: $source_ca não existe." >&2
    echo "Suba a stack primeiro (docker compose up) para que as CAs sejam geradas." >&2
    exit 1
  fi

  if ! openssl x509 -in "$source_ca" -noout -checkend 0 >/dev/null 2>&1; then
    echo "erro: a CA em $source_ca está expirada." >&2
    echo "Apague o runtime correspondente e suba a stack de novo." >&2
    exit 1
  fi

  mkdir -p "$target_dir"
  cp "$source_ca" "$target_ca"
  echo "CA ($label) copiada para $target_ca"
  openssl x509 -in "$target_ca" -noout -subject -dates
}

for app in acs patient; do
  copy_ca \
    "$repo_root/infra/docker/mosquitto/runtime/certs/ca.crt" \
    "$repo_root/apps/$app/assets/certs" \
    "$repo_root/apps/$app/assets/certs/dev_ca.crt" \
    "MQTT"
  copy_ca \
    "$repo_root/infra/docker/traefik/runtime/certs/ca.crt" \
    "$repo_root/apps/$app/assets/certs" \
    "$repo_root/apps/$app/assets/certs/dev_rpc_ca.crt" \
    "RPC"
done
