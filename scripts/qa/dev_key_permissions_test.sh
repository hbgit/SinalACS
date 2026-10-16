#!/usr/bin/env bash
#
# As chaves das CAs de desenvolvimento (ca.key) só são lidas pelos init.sh, que
# rodam como root dentro do contêiner: ninguém mais precisa do bit de leitura.
# As demais chaves (server.key, backend.key, acs-area-12.key) são lidas por outro
# uid (o backend roda como uid 1000; o sync_dev_ca.sh, como o usuário do host) e
# ficam em 644 — decisão e motivo em PROGRESS.md. A folha do backend (#78) também.
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
# A folha do backend (Traefik → backend, issue #78) mora em runtime/backend/, o
# único diretório do RPC montado no container do backend: a chave dela fica em
# 644 (o backend lê como uid 1000), e a ca.key NUNCA pode estar ali.
bdir=infra/docker/traefik/runtime/backend
if [[ -d "$bdir" ]]; then
  [[ ! -e "$bdir/ca.key" ]] || { echo "ca.key presente em $bdir, que é montado no backend" >&2; ruim=1; }
  if [[ -f "$bdir/backend.key" ]]; then
    m="$(stat -c %a "$bdir/backend.key")"
    [[ "$m" == 644 ]] || { echo "backend.key em $m (esperado 644, o backend lê como uid 1000): $bdir/backend.key" >&2; ruim=1; }
  else
    echo "backend.key ausente em $bdir (o traefik-init da #78 rodou?)" >&2; ruim=1
  fi
fi
[[ "$ruim" -eq 0 ]] && echo "OK — ca.key em 600, folha do backend em 644 e sem ca.key ao lado"
exit "$ruim"
