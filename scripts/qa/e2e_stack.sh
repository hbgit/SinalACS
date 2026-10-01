#!/usr/bin/env bash
# Sobe/derruba a stack de e2e contra o banco de teste. Ver docker-compose.e2e.yml.
#   e2e_stack.sh up | seed | down | psql "<sql>"
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ -f .env ]] || { echo 'erro: rode ./scripts/dev/bootstrap_env.sh'; exit 1; }
set -a; source .env; set +a
unset GORUSH_CREDENTIALS_DIR   # o Compose o prioriza sobre o .env (ver PROGRESS.md)
export GORUSH_CREDENTIALS_DIR="$PWD/infra/docker/gorush/credentials"
dc() { docker compose --profile test --profile push -f docker-compose.yml -f docker-compose.e2e.yml "$@"; }
db=sinalacs_e2e
# `-e PGPASSWORD` sem valor herda do ambiente: a senha não aparece no argv (`ps`).
export PGPASSWORD="$TEST_DATABASE_PASSWORD"
pg() { docker exec -e PGPASSWORD sinalacs-postgres-test psql -U postgres -d "${2:-$db}" -Atc "$1"; }

case "${1:-}" in
  up)
    if docker ps --format '{{.Names}}' | grep -qx sinalacs-serverpod; then
      echo 'aviso: o backend em execução (sinalacs-serverpod) será substituído pelo de e2e; ao final, rode `docker compose up -d` para voltar à stack de desenvolvimento.' >&2
    fi
    log="$(mktemp)"; trap 'rm -f "$log"' EXIT
    falhou() { echo "erro: $1" >&2; tail -n 25 "$log" >&2; exit 1; }
    dc up -d postgres-test >"$log" 2>&1 || falhou 'o postgres-test não subiu'
    ok=0
    for _ in $(seq 1 60); do
      docker exec sinalacs-postgres-test pg_isready -U postgres -d sinalacs_test >/dev/null 2>&1 && { ok=1; break; }
      sleep 1
    done
    [[ "$ok" -eq 1 ]] || falhou 'o postgres-test não ficou pronto em 60 s' 
    # Recria o banco: cada execução parte de um banco vazio.
    dc stop serverpod >/dev/null 2>&1 || true
    pg "drop database if exists $db with (force)" postgres >/dev/null
    pg "create database $db" postgres >/dev/null
    # Só o backend e o relé; os seeds de desenvolvimento NÃO sobem (as fixtures vêm do `seed`).
    # Sem `--no-deps` o Compose sobe também o postgres de desenvolvimento; COM ele, os
    # certificados do Traefik e o passwordfile do Mosquitto precisam existir de uma subida
    # anterior da stack normal — a falta aparece aqui em vez de sumir.
    for f in infra/docker/traefik/runtime/certs/ca.crt; do
      [[ -f "$f" ]] || falhou "falta $f: suba a stack normal uma vez (docker compose up -d) para gerar os certificados"
    done
    dc up -d --build --force-recreate --no-deps serverpod gorush traefik mosquitto >"$log" 2>&1 \
      || falhou 'a subida do backend falhou'
    for _ in $(seq 1 90); do
      [[ "$(docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod 2>/dev/null)" == healthy ]] && exit 0
      sleep 2
    done
    echo 'erro: serverpod não ficou saudável' >&2; dc logs --tail 40 serverpod >&2; exit 1 ;;
  seed)
    ( cd backend/sinalacs_server && \
      SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 \
      SERVERPOD_DATABASE_NAME=$db SERVERPOD_DATABASE_USER=postgres \
      SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
      dart run bin/seed_e2e_fixtures.dart ../../.e2e/fixtures.json ) ;;
  down)
    # O manifesto (com a senha do ACS) sai primeiro: se o drop falhar, ele não sobra.
    rm -f .e2e/fixtures.json
    dc stop serverpod >/dev/null 2>&1 || true
    pg "drop database if exists $db with (force)" postgres >/dev/null
    echo 'A stack de e2e parou (o container sinalacs-serverpod é o mesmo da de desenvolvimento): rode `docker compose up -d` para voltar à de desenvolvimento.' ;;
  psql) pg "$2" ;;
  *) echo 'uso: e2e_stack.sh up|seed|down|psql "<sql>"'; exit 2 ;;
esac
