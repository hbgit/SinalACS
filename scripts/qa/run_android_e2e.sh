#!/usr/bin/env bash
#
# Roda o E2E Android dentro do reactivecircus/android-emulator-runner no CI.
#
# Existe como script separado porque essa action executa cada linha do
# "script:" do workflow como um processo `sh -c` independente — um `if/fi`
# multi-linha quebra por falta do `fi` no mesmo processo, e `set -a; source
# .env; set +a` não propaga variáveis para os comandos seguintes, já que cada
# um roda isolado. Um único script bash evita as duas coisas.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

trap 'docker compose down' EXIT

if [[ -z "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  echo 'erro: GOOGLE_MAPS_API_KEY é obrigatória para o E2E Android.' >&2
  exit 1
fi

set -a
source .env
set +a

./scripts/qa/e2e.sh --emulator --keep
dart run scripts/qa/measure_latency.dart \
  --mqtt-password "$MQTT_ACS_PASSWORD" \
  --output build/qa/latency/metrics.json
