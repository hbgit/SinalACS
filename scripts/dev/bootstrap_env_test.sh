#!/usr/bin/env bash
#
# Prova o acréscimo de DEV_ADMIN_PASSWORD do bootstrap_env.sh num .env existente.
# Trabalha numa árvore temporária (cópia do script e do .env.example): nunca
# toca o .env real.
set -euo pipefail
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
raiz_real="$(cd "$aqui/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
falha() { echo "FALHOU: $*" >&2; exit 1; }

preparar() { # <conteúdo do .env, via printf>
  rm -rf "$tmp/r"; mkdir -p "$tmp/r/scripts/dev" "$tmp/r/backend/sinalacs_server/config"
  cp "$aqui/bootstrap_env.sh" "$tmp/r/scripts/dev/"
  cp "$raiz_real/.env.example" "$tmp/r/.env.example"
  printf "$1" > "$tmp/r/.env"
}
rodar() { "$tmp/r/scripts/dev/bootstrap_env.sh" >/dev/null 2>&1; }

base='POSTGRES_PASSWORD=aaa\nTEST_DATABASE_PASSWORD=bbb\nJWT_SECRET=ccc'

# 1) sem newline final: o resto fica igual byte a byte e a variável nasce em linha própria.
preparar "$base"
rodar
head -c "${#base}" "$tmp/r/.env" >/dev/null
esperado="$(printf "$base")"
[[ "$(head -n 3 "$tmp/r/.env")" == "$esperado" ]] || falha 'as três linhas originais mudaram'
[[ "$(sed -n 3p "$tmp/r/.env")" == 'JWT_SECRET=ccc' ]] || falha 'a última variável foi colada'
[[ "$(sed -n 4p "$tmp/r/.env")" =~ ^DEV_ADMIN_PASSWORD=[0-9a-f]{64}$ ]] || falha 'DEV_ADMIN_PASSWORD fora de linha própria'
[[ "$(wc -l < "$tmp/r/.env")" -eq 5 ]] || falha 'esperava exatamente 5 linhas'

# 2) com newline final: mesmo resultado, sem linha em branco extra.
preparar "$base\n"
rodar
[[ "$(sed -n 4p "$tmp/r/.env")" =~ ^DEV_ADMIN_PASSWORD= ]] || falha 'com newline final: variável ausente'
[[ "$(wc -l < "$tmp/r/.env")" -eq 5 ]] || falha 'com newline final: linha em branco indevida'

# 3) já presente: nada muda.
preparar "$base\nDEV_ADMIN_PASSWORD=xyz\nTELEMETRY_PSEUDONYM_KEY=tt\n"
antes="$(cat "$tmp/r/.env")"
rodar
[[ "$(cat "$tmp/r/.env")" == "$antes" ]] || falha 'valor existente foi alterado'

# 4) TELEMETRY_PSEUDONYM_KEY (#83): acrescentada sem tocar nas outras; presente, intacta.
preparar "$base\nDEV_ADMIN_PASSWORD=xyz\n"
rodar
[[ "$(head -n 4 "$tmp/r/.env")" == "$(printf "$base\nDEV_ADMIN_PASSWORD=xyz")" ]] || falha 'telemetria: linhas originais mudaram'
[[ "$(sed -n 5p "$tmp/r/.env")" =~ ^TELEMETRY_PSEUDONYM_KEY=[0-9a-f]{64}$ ]] || falha 'TELEMETRY_PSEUDONYM_KEY não acrescentada'
antes="$(cat "$tmp/r/.env")"
rodar
[[ "$(cat "$tmp/r/.env")" == "$antes" ]] || falha 'TELEMETRY_PSEUDONYM_KEY existente foi alterada'

# 5) .env novo (#94): sem senha MQTT nenhuma, com os demais segredos preenchidos.
preparar ''
rm -f "$tmp/r/.env"
rodar
! grep -qE '^MQTT_(BACKEND|ACS)_PASSWORD=' "$tmp/r/.env" || falha '.env novo ainda traz senha MQTT'
grep -qE '^JWT_SECRET=[0-9a-f]{64}$' "$tmp/r/.env" || falha '.env novo sem JWT_SECRET'

# 6) .env antigo com as senhas MQTT: preservado como está (nada mais as lê).
preparar "$base\nMQTT_BACKEND_PASSWORD=m1\nMQTT_ACS_PASSWORD=m2\nDEV_ADMIN_PASSWORD=xyz\nTELEMETRY_PSEUDONYM_KEY=tt\n"
antes="$(cat "$tmp/r/.env")"
rodar
[[ "$(cat "$tmp/r/.env")" == "$antes" ]] || falha '.env antigo com senhas MQTT foi alterado'

echo 'ok: bootstrap_env_test.sh'
