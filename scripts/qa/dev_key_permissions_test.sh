#!/usr/bin/env bash
#
# As chaves das CAs de desenvolvimento (ca.key) só são lidas pelos init.sh, que
# rodam como root dentro do contêiner: ninguém mais precisa do bit de leitura.
# As demais chaves (server.key, backend.key, acs-area-12.key) são lidas por outro
# uid (o backend roda como uid 1000; o sync_dev_ca.sh, como o usuário do host) e
# ficam em 644 — decisão e motivo em PROGRESS.md. A folha do backend (#78) também.
# Desde a #90 há duas folhas de CLIENTE: traefik-client.key (600, só o Traefik, que
# roda como root) e healthcheck.key (644, lida pelo curl do healthcheck como uid
# 1000) — e as duas têm de ter EKU clientAuth (ver o bloco no fim).
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
# #90 — as DUAS folhas de cliente que o traefik-init emite para o mTLS da 8080:
# a do Traefik (runtime/certs/, lida só pelo Traefik, que roda como root → 600) e
# a do healthcheck (runtime/backend/, lida pelo curl do HEALTHCHECK como uid
# 1000 → 644). As duas têm de ser certificado de CLIENTE (EKU clientAuth): uma
# folha serverAuth reaproveitada por descuido é recusada pelo BoringSSL do
# backend e o Traefik devolve 5xx para todo app, sem dizer por quê. E a folha do
# backend continua sendo só de servidor.
eku() { openssl x509 -in "$1" -noout -ext extendedKeyUsage 2>/dev/null; }
tdir=infra/docker/traefik/runtime/certs
if [[ -d "$tdir" ]]; then
  if [[ -f "$tdir/traefik-client.key" ]]; then
    m="$(stat -c %a "$tdir/traefik-client.key")"
    [[ "$m" == 600 ]] || { echo "traefik-client.key em $m (esperado 600, só o Traefik, root, a lê): $tdir/traefik-client.key" >&2; ruim=1; }
    eku "$tdir/traefik-client.crt" | grep -q 'TLS Web Client Authentication' \
      || { echo "traefik-client.crt não é certificado de cliente (EKU sem clientAuth)" >&2; ruim=1; }
  else
    echo "traefik-client.key ausente em $tdir (o traefik-init da #90 rodou?)" >&2; ruim=1
  fi
fi
if [[ -d "$bdir" ]]; then
  if [[ -f "$bdir/healthcheck.key" ]]; then
    m="$(stat -c %a "$bdir/healthcheck.key")"
    [[ "$m" == 644 ]] || { echo "healthcheck.key em $m (esperado 644, o curl do healthcheck lê como uid 1000): $bdir/healthcheck.key" >&2; ruim=1; }
    eku "$bdir/healthcheck.crt" | grep -q 'TLS Web Client Authentication' \
      || { echo "healthcheck.crt não é certificado de cliente (EKU sem clientAuth)" >&2; ruim=1; }
  else
    echo "healthcheck.key ausente em $bdir (o traefik-init da #90 rodou?)" >&2; ruim=1
  fi
  if [[ -f "$bdir/backend.crt" ]] && eku "$bdir/backend.crt" | grep -q 'TLS Web Client Authentication'; then
    echo "backend.crt virou certificado de cliente (EKU com clientAuth): a folha do servidor não pode autenticar-se como cliente" >&2; ruim=1
  fi
fi
[[ "$ruim" -eq 0 ]] && echo "OK — ca.key em 600, folha do backend em 644 e sem ca.key ao lado; folhas de cliente (#90) com clientAuth, traefik-client.key 600 e healthcheck.key 644"
exit "$ruim"
