#!/usr/bin/env bash
#
# Validação ponta a ponta da conexão dos apps com o backend.
#
#   ./scripts/qa/e2e.sh            # sobe a stack, valida na VM, derruba
#   ./scripts/qa/e2e.sh --keep     # mantém a stack de pé ao final
#   ./scripts/qa/e2e.sh --emulator # inclui os testes de integração no emulador
#
# Sem --emulator, roda as verificações que não precisam de dispositivo
# (tool/live_check.dart dos dois apps), que já exercitam o RPC, o MQTT com TLS e
# a sincronização de visitas usando o código de rede real dos apps.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

keep_stack=0
run_emulator=0
for arg in "$@"; do
  case "$arg" in
    --keep) keep_stack=1 ;;
    --emulator) run_emulator=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

cleanup() {
  if [[ "$keep_stack" -eq 0 ]]; then
    echo
    echo '== derrubando a stack =='
    docker compose down
  fi
}
trap cleanup EXIT

# A configuração vem do .env, que não é versionado. Sem ele o docker compose já
# falharia, mas com uma mensagem no meio do build — melhor barrar antes e dizer
# o que fazer.
if [[ ! -f "$repo_root/.env" ]]; then
  echo 'erro: .env não existe.' >&2
  echo 'Rode ./scripts/dev/bootstrap_env.sh para gerar a configuração local.' >&2
  exit 1
fi

# As senhas do broker são geradas por máquina, então os apps não podem contar
# com o default compilado: o live_check recebe a senha real por argumento.
set -a
# shellcheck disable=SC1091
source "$repo_root/.env"
set +a

echo '== subindo a stack =='
docker compose up --build -d

echo '== aguardando o backend ficar saudável =='
for _ in $(seq 1 60); do
  status="$(docker inspect -f '{{.State.Health.Status}}' sinalacs-serverpod 2>/dev/null || echo starting)"
  [[ "$status" == healthy ]] && break
  sleep 2
done
if [[ "${status:-}" != healthy ]]; then
  echo 'erro: o backend não ficou saudável a tempo.' >&2
  docker compose logs --tail 40 serverpod >&2
  exit 1
fi

echo '== aplicando o seed de desenvolvimento =='
# Sem o seed, createRedAlert falha por chave estrangeira em alerts.patientId.
docker compose up database-seed

echo '== sincronizando a CA do broker para o app do ACS =='
./scripts/dev/sync_dev_ca.sh

echo
echo '== paciente: RPC (saúde, login, triagem, alerta, idempotência) =='
(cd apps/patient && dart pub get >/dev/null && dart run tool/live_check.dart)

echo
echo '== ACS: ciclo completo (RPC + MQTT/TLS + sincronização de visita) =='
(cd apps/acs && dart pub get >/dev/null && \
  dart run tool/live_check.dart --mqtt-password "$MQTT_ACS_PASSWORD")

if [[ "$run_emulator" -eq 1 ]]; then
  echo
  echo '== testes de integração no dispositivo =='
  # O emulador alcança o host da máquina por 10.0.2.2.
  (cd apps/patient && flutter test integration_test \
      --dart-define=SINALACS_HOST=http://10.0.2.2:8080/)
  (cd apps/acs && flutter test integration_test \
      --dart-define=SINALACS_HOST=http://10.0.2.2:8080/ \
      --dart-define=SINALACS_MQTT_HOST=10.0.2.2 \
      --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD")
fi

echo
echo 'OK — os apps falam com o backend.'
