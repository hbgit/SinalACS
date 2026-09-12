#!/usr/bin/env bash
#
# Executa (ou compila) o app do ACS contra a stack local, com as credenciais
# desta máquina.
#
#   ./scripts/dev/run_acs.sh                    # flutter run no dispositivo padrão
#   ./scripts/dev/run_acs.sh -d emulator-5554   # argumentos extras vão para o flutter
#   ./scripts/dev/run_acs.sh --build            # flutter build apk --debug
#   ./scripts/dev/run_acs.sh --host http://192.168.0.10:8080/ --mqtt-host 192.168.0.10
#   ./scripts/dev/run_acs.sh --skip-ca          # não recopia a CA do broker
#
# Por que existe:
#   · SINALACS_MQTT_PASSWORD é resolvido em tempo de COMPILAÇÃO e não tem
#     default. O broker cria o usuário acs-area-12 com MQTT_ACS_PASSWORD, um
#     segredo aleatório POR MÁQUINA gerado por scripts/dev/bootstrap_env.sh:
#     nenhum valor embutido no código poderia acertá-lo. Sem este wrapper,
#     `flutter run` produz um app que nunca recebe alerta nenhum.
#   · A CA do broker é asset do APK (apps/acs/assets/certs/), regerada pelo
#     mosquitto-init e não versionada. Sem ela o build falha antes do TLS —
#     apps/acs/pubspec.yaml declara o diretório — e não haveria em quem confiar.
#
# A senha nunca é impressa. Ela viaja na linha de comando do flutter e fica
# visível em `ps` para outros usuários da MESMA máquina: aceitável em
# desenvolvimento, e é o que scripts/qa/e2e.sh já faz. Para endurecer, o
# caminho é --dart-define-from-file, que exige um arquivo temporário com trap
# de limpeza.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_dir="$repo_root/apps/acs"
env_file="$repo_root/.env"

# Defaults do emulador Android, que enxerga o host da máquina em 10.0.2.2.
host='http://10.0.2.2:8080/'
mqtt_host='10.0.2.2'
action='run'
skip_ca=0
flutter_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)      host="${2:?--host exige um valor}"; shift 2 ;;
    --mqtt-host) mqtt_host="${2:?--mqtt-host exige um valor}"; shift 2 ;;
    --build)     action='build'; shift ;;
    --skip-ca)   skip_ca=1; shift ;;
    -h|--help)   sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)          shift; flutter_args+=("$@"); break ;;
    *)           flutter_args+=("$1"); shift ;;
  esac
done

if ! command -v flutter >/dev/null 2>&1; then
  echo 'erro: flutter não encontrado no PATH.' >&2
  exit 1
fi

if [[ ! -f "$env_file" ]]; then
  echo 'erro: .env não existe.' >&2
  echo 'Rode ./scripts/dev/bootstrap_env.sh para gerar a configuração local.' >&2
  exit 1
fi

# Lê só a chave necessária, em vez de `source .env`: não há motivo para empurrar
# POSTGRES_PASSWORD e JWT_SECRET para dentro do Gradle e do daemon do Flutter.
# Uma variável já exportada tem precedência — é como se testa o caminho de
# credencial recusada sem editar o .env.
mqtt_password="${MQTT_ACS_PASSWORD:-$(grep -E '^MQTT_ACS_PASSWORD=' "$env_file" | head -1 | cut -d= -f2-)}"
# Usuário criado por infra/docker/mosquitto/init.sh.
mqtt_user="${MQTT_ACS_USER:-acs-area-12}"

if [[ -z "$mqtt_password" ]]; then
  echo 'erro: MQTT_ACS_PASSWORD está vazio no .env.' >&2
  echo 'Rode ./scripts/dev/bootstrap_env.sh --force para regerar os segredos.' >&2
  exit 1
fi

if [[ "$skip_ca" -eq 0 ]]; then
  if ! "$repo_root/scripts/dev/sync_dev_ca.sh"; then
    if [[ -f "$app_dir/assets/certs/dev_ca.crt" ]]; then
      echo 'aviso: a stack parece estar fora do ar; mantendo a CA já copiada.' >&2
    else
      echo 'erro: sem a CA do broker o app nem compila (pubspec declara assets/certs/).' >&2
      echo 'Suba a stack com `docker compose up` e rode de novo.' >&2
      exit 1
    fi
  fi
fi

defines=(
  "--dart-define=SINALACS_HOST=$host"
  "--dart-define=SINALACS_MQTT_HOST=$mqtt_host"
  "--dart-define=SINALACS_MQTT_USER=$mqtt_user"
  "--dart-define=SINALACS_MQTT_PASSWORD=$mqtt_password"
)

echo "ACS → $host   broker → $mqtt_host:8883 (usuário $mqtt_user)"
echo 'senha do broker .... lida do .env, não exibida'

cd "$app_dir"
if [[ "$action" == 'build' ]]; then
  exec flutter build apk --debug "${defines[@]}" "${flutter_args[@]}"
fi
exec flutter run "${defines[@]}" "${flutter_args[@]}"
