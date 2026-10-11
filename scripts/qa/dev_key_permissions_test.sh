#!/usr/bin/env bash
#
# As chaves das CAs de desenvolvimento (ca.key) só são lidas pelos init.sh, que
# rodam como root dentro do contêiner: ninguém mais precisa do bit de leitura.
# As demais chaves (server.key, backend.key, acs-area-12.key) são lidas por outro
# uid (o backend roda como uid 1000; o sync_dev_ca.sh, como o usuário do host) e
# ficam em 644 — decisão e motivo em PROGRESS.md.
#
# Só confere o que a stack já gerou: sem runtime/, sai 0 avisando.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
dirs=(infra/docker/mosquitto/runtime/certs infra/docker/traefik/runtime/certs)
[[ -d "${dirs[0]}" || -d "${dirs[1]}" ]] || { echo "sem runtime/ (suba a stack antes); nada a conferir"; exit 0; }
ruim=0
for d in "${dirs[@]}"; do
  k="$d/ca.key"
  [[ -f "$k" ]] || continue
  m="$(stat -c %a "$k")"
  [[ "$m" == 600 ]] || { echo "ca.key em $m (esperado 600): $k" >&2; ruim=1; }
done
[[ "$ruim" -eq 0 ]] && echo "OK — ca.key em 600"
exit "$ruim"
