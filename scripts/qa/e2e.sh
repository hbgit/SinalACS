#!/usr/bin/env bash
#
# Validação ponta a ponta da conexão dos apps com o backend.
#
#   ./scripts/qa/e2e.sh            # sobe a stack, valida na VM, derruba
#   ./scripts/qa/e2e.sh --keep     # mantém a stack de pé ao final
#   ./scripts/qa/e2e.sh --emulator # + smoke no emulador (integration_test/smoke_test.dart)
#   ./scripts/qa/e2e.sh --emulator --full # + TODA a bateria integration_test dos três apps
#
# --emulator sozinho é o que a CI roda: um arquivo, um teste e um APK por app
# (paciente e ACS). Cada arquivo de integration_test/ custa um build e um
# `adb install`, que é o que domina o tempo no emulador; o resto da bateria
# fica para --full, rodado à mão antes de mexer em rede, criptografia local ou
# mapa.
#
# Sem --emulator, roda as verificações que não precisam de dispositivo
# (tool/live_check.dart dos dois apps), que já exercitam o RPC sobre TLS, o MQTT
# com TLS e a sincronização de visitas usando o código de rede real dos apps.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

keep_stack=0
run_emulator=0
run_full=0
for arg in "$@"; do
  case "$arg" in
    --keep) keep_stack=1 ;;
    --emulator) run_emulator=1 ;;
    --full) run_full=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done
if [[ "$run_full" -eq 1 && "$run_emulator" -eq 0 ]]; then
  echo 'erro: --full só faz sentido junto com --emulator.' >&2
  exit 2
fi

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

# `adb install` falha de forma transiente e conhecida em emuladores sem
# aceleração de hardware (medido no runner da CI antes de o job habilitar o
# KVM: o boot logava "Linux VM where hardware acceleration is not available")
# com "cmd: Failure calling service package: Broken pipe (32)" — a instalação
# do APK cai no meio, sem relação com rede/certificado; uma segunda tentativa
# costuma passar. Só o `flutter test integration_test` (que reinstala o APK) é
# envolvido — o `docker compose`/seed acima não tem esse modo de falha.
#
# A nova tentativa acontece SÓ quando a saída tem "Broken pipe". Antes ela
# disparava em qualquer falha: um teste realmente vermelho rodava a suíte
# inteira duas vezes, e foi o que empurrou o job para além dos 60 min.
tentar_flutter_test() {
  local saida
  saida="$(mktemp)"
  if "$@" 2>&1 | tee "$saida"; then
    rm -f "$saida"
    return 0
  fi
  if ! grep -q 'Broken pipe' "$saida"; then
    rm -f "$saida"
    return 1
  fi
  rm -f "$saida"
  echo 'aviso: "Broken pipe" no adb install; tentando de novo.' >&2
  sleep 5
  "$@"
}

if [[ "$run_emulator" -eq 1 ]]; then
  echo
  # Smoke: um arquivo por app, que é um build e um `adb install` por app.
  # --full: a pasta inteira, como era antes, mais o admin (hermético, roda
  # sobre o MockAdminDataSource e não precisa da stack).
  if [[ "$run_full" -eq 1 ]]; then
    alvo_integracao=integration_test
    echo '== testes de integração no dispositivo (bateria completa) =='
  else
    alvo_integracao=integration_test/smoke_test.dart
    echo '== smoke de integração no dispositivo =='
  fi
  (cd apps/patient && flutter pub get >/dev/null)
  (cd apps/acs && flutter pub get >/dev/null)
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
  # emulador, então os `--dart-define` abaixo passam a apontar para
  # "localhost" — reencaminhado pelo adb — em vez de 10.0.2.2. `localhost` (não
  # `127.0.0.1`) porque é o Host que a regra do Traefik e o SAN dos dois
  # certificados (RPC e broker) já esperam — ver docker-compose.yml e os dois
  # `init.sh` em infra/docker/.
  #
  # A porta do RPC no lado do DISPOSITIVO não pode ser 443: medido, `adb
  # reverse` recusa abrir o listener nessa porta dentro do emulador ("cannot
  # bind listener: Permission denied") — Android não deixa um processo comum
  # ligar em porta privilegiada (<1024), nem para o próprio adbd. 8443 do lado
  # do dispositivo, encaminhado para os 443 reais do host, resolve sem tocar no
  # lado do host: a regra `Host(...)` do Traefik e a verificação de hostname
  # TLS comparam só o nome (`localhost`), nunca a porta, então uma porta
  # diferente no cliente não quebra nenhuma das duas. 8883 (MQTT) já não é
  # privilegiada, então mantém a mesma porta dos dois lados.
  adb -s emulator-5554 reverse tcp:8443 tcp:443
  adb -s emulator-5554 reverse tcp:8883 tcp:8883
  (cd apps/patient && tentar_flutter_test flutter test "$alvo_integracao" -d emulator-5554 \
      --dart-define=SINALACS_HOST=https://localhost:8443/)
  acs_cmd=(flutter test "$alvo_integracao" -d emulator-5554
    --dart-define=SINALACS_HOST=https://localhost:8443/
    --dart-define=SINALACS_MQTT_HOST=localhost
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD")
  if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
    acs_cmd+=(--dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY")
  fi
  (cd apps/acs && tentar_flutter_test "${acs_cmd[@]}")
  if [[ "$run_full" -eq 1 ]]; then
    (cd apps/admin && flutter pub get >/dev/null && \
      tentar_flutter_test flutter test integration_test -d emulator-5554)
  fi
fi

echo
echo 'OK — os apps falam com o backend.'
