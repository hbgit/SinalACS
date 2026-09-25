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

# GOOGLE_MAPS_API_KEY não é mais obrigatória: a CI roda só o smoke de cada app
# (e2e.sh --emulator, sem --full), e o map_flow_test.dart ficou fora dele. Se
# vier no ambiente, o e2e.sh ainda a repassa ao build do ACS.
if [[ -z "${GOOGLE_MAPS_API_KEY:-}" ]]; then
  echo 'aviso: GOOGLE_MAPS_API_KEY ausente — o mapa do ACS fica sem tiles.' >&2
fi

set -a
source .env
set +a

./scripts/qa/e2e.sh --emulator --keep
dart run scripts/qa/measure_latency.dart \
  --mqtt-password "$MQTT_ACS_PASSWORD" \
  --output build/qa/latency/metrics.json
