#!/usr/bin/env bash
#
# Copia a CA de desenvolvimento do Mosquitto para o asset do app do ACS.
#
# O app precisa confiar no certificado auto-assinado do broker local. Como
# `SecurityContext.setTrustedCertificatesBytes` lê bytes (e não um caminho, que
# não existiria dentro do APK), a CA entra como asset Flutter.
#
# A CA é REGERADA pelo mosquitto-init, nunca versionada: tanto
# infra/docker/mosquitto/runtime/ quanto apps/acs/assets/certs/ estão no
# .gitignore. Rode este script sempre que subir a stack pela primeira vez ou
# depois de apagar o runtime/.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_ca="$repo_root/infra/docker/mosquitto/runtime/certs/ca.crt"
target_dir="$repo_root/apps/acs/assets/certs"
target_ca="$target_dir/dev_ca.crt"

if [[ ! -f "$source_ca" ]]; then
  echo "erro: $source_ca não existe." >&2
  echo "Suba a stack primeiro (docker compose up) para que o mosquitto-init gere a CA." >&2
  exit 1
fi

if ! openssl x509 -in "$source_ca" -noout -checkend 0 >/dev/null 2>&1; then
  echo "erro: a CA em $source_ca está expirada." >&2
  echo "Apague infra/docker/mosquitto/runtime/ e suba a stack de novo." >&2
  exit 1
fi

mkdir -p "$target_dir"
cp "$source_ca" "$target_ca"

echo "CA de desenvolvimento copiada para apps/acs/assets/certs/dev_ca.crt"
openssl x509 -in "$target_ca" -noout -subject -dates
