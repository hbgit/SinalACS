#!/usr/bin/env bash
#
# Validação ponta a ponta da conexão dos apps com o backend.
#
#   ./scripts/qa/e2e.sh            # sobe a stack, valida na VM, derruba
#   ./scripts/qa/e2e.sh --keep     # mantém a stack de pé ao final
#   ./scripts/qa/e2e.sh --emulator # inclui os testes de integração no emulador
#
# Sem --emulator, roda as verificações que não precisam de dispositivo
# (tool/live_check.dart dos dois apps), que já exercitam o RPC sobre TLS, o MQTT
# com TLS e a sincronização de visitas usando o código de rede real dos apps.
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
existing_google_maps_api_key="${GOOGLE_MAPS_API_KEY:-}"
set -a
# shellcheck disable=SC1091
source "$repo_root/.env"
set +a
if [[ -n "$existing_google_maps_api_key" ]]; then
  GOOGLE_MAPS_API_KEY="$existing_google_maps_api_key"
fi

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

echo '== sincronizando as CAs (broker e RPC) para os dois apps =='
./scripts/dev/sync_dev_ca.sh

echo
echo '== RNF04/L-08: as invariantes de TLS na stack que acabou de subir =='
# Roda AQUI, com a stack de pé e antes dos apps, porque este é o único ponto do
# repositório em que a stack existe e ninguém ainda gastou tempo em dispositivo:
# sem esta linha a bateria só rodaria quando alguém lembrasse dela, e o job
# `android-e2e` da CI (que executa este script) passa a medir o requisito de
# graça. O `set -e` acima faz uma invariante vermelha derrubar o e2e — que é o
# que "o RNF04 está violado" tem de fazer.
./scripts/qa/tls_invariants.sh

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
  (cd apps/patient && flutter pub get >/dev/null)
  (cd apps/acs && flutter pub get >/dev/null)
  (cd apps/admin && flutter pub get >/dev/null)
  # Medido no runner da CI: o app falha ao falar com o RPC via 10.0.2.2:443 —
  # "Não foi possível falar com o servidor (-1)" (ServerpodClientException com
  # statusCode -1, o wrap genérico do cliente gerado para quando a conexão TCP
  # em si não se completa; um TLS/certificado ruim cai num catch diferente,
  # com outra mensagem) — mesmo com a stack saudável e os mesmos 443/8883 já
  # confirmados alcançáveis por localhost segundos antes, rodando no host (RNF04,
  # `tls_invariants.sh` e os dois `live_check.dart` acima). 10.0.2.2 é o alias
  # de gateway do NAT do emulador para o host; o que muda entre os dois
  # caminhos é justamente essa tradução de rede.
  #
  # `adb reverse` tunela pelo protocolo do próprio adb, sem depender da NAT do
  # emulador, então os dois `--dart-define` abaixo passam a apontar para
  # "localhost" — reencaminhado pelo adb — em vez de 10.0.2.2. `localhost` (não
  # `127.0.0.1`) porque é o Host que a regra do Traefik e o SAN dos dois
  # certificados (RPC e broker) já esperam — ver docker-compose.yml e os dois
  # `init.sh` em infra/docker/.
  adb -s emulator-5554 reverse tcp:443 tcp:443
  adb -s emulator-5554 reverse tcp:8883 tcp:8883
  (cd apps/patient && flutter test integration_test -d emulator-5554 \
      --dart-define=SINALACS_HOST=https://localhost/)
  acs_cmd=(flutter test integration_test -d emulator-5554
    --dart-define=SINALACS_HOST=https://localhost/
    --dart-define=SINALACS_MQTT_HOST=localhost
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD")
  if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
    acs_cmd+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
  fi
  (cd apps/acs && "${acs_cmd[@]}")
  (cd apps/admin && flutter test integration_test -d emulator-5554)
fi

echo
echo 'OK — os apps falam com o backend.'
