#!/usr/bin/env bash
#
# Push e2e (Gorush e FCM reais) no CI — só se as credenciais existirem.
#
# Precisa de GOOGLE_APPLICATION_CREDENTIALS (chave da conta de serviço, decodificada pelo
# passo do workflow) e de apps/patient/android/app/google-services.json. Sem elas (PR de
# fork, secrets ausentes) avisa e sai com 0: o smoke do job continua valendo sozinho.
#
# O Gorush lê a chave de infra/docker/gorush/credentials/fcm-service-account.json
# (config.yml `key_path`), então a chave de GOOGLE_APPLICATION_CREDENTIALS é instalada ali
# com modo 600, que é o que o push_e2e.sh exige. Nunca imprime a chave.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

origem="${GOOGLE_APPLICATION_CREDENTIALS:-}"
google_services=apps/patient/android/app/google-services.json
destino=infra/docker/gorush/credentials/fcm-service-account.json
push="${PUSH_E2E_SCRIPT:-./scripts/qa/push_e2e.sh}"

if [[ -z "$origem" || ! -f "$origem" || ! -f "$google_services" ]]; then
  echo '::notice title=push e2e::sem a chave do FCM ou sem google-services.json (PR de fork ou secrets ausentes): push e2e pulado.'
  exit 0
fi

install -D -m 600 "$origem" "$destino"
# O Gorush (imagem com uid 1000) precisa ler esta chave 0600, que pertence ao usuário do
# runner (uid 1001): o container roda com o uid/gid de quem a instalou (docker-compose.yml).
export GORUSH_UID GORUSH_GID
GORUSH_UID="$(id -u)"
GORUSH_GID="$(id -g)"
exec "$push"
