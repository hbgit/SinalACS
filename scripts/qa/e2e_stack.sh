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
pg() { docker exec -e PGPASSWORD="$TEST_DATABASE_PASSWORD" sinalacs-postgres-test psql -U postgres -d "${2:-$db}" -Atc "$1"; }

case "${1:-}" in
  up)
    if docker ps --format '{{.Names}}' | grep -qx sinalacs-serverpod; then
      echo 'aviso: o backend em execução (sinalacs-serverpod) será substituído pelo de e2e; ao final, rode `docker compose up -d` para voltar à stack de desenvolvimento.' >&2
    fi
    dc up -d postgres-test >/dev/null 2>&1
    until docker exec sinalacs-postgres-test pg_isready -U postgres -d sinalacs_test >/dev/null 2>&1; do sleep 1; done
    # Recria o banco: cada execução parte de um banco vazio.
    dc stop serverpod >/dev/null 2>&1 || true
    pg "drop database if exists $db with (force)" postgres >/dev/null
    pg "create database $db" postgres >/dev/null
    # Só o backend e o relé; os seeds de desenvolvimento NÃO sobem (as fixtures vêm do `seed`).
    dc up -d --build --force-recreate --no-deps serverpod gorush traefik mosquitto >/dev/null 2>&1
    for _ in $(seq 1 90); do
      [[ "$(docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod 2>/dev/null)" == healthy ]] && exit 0
      sleep 2
    done
    echo 'erro: serverpod não ficou saudável'; dc logs --tail 40 serverpod; exit 1 ;;
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
