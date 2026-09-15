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
#     `flutter run` produz um app que nunca recebe alerta nenhum — e desde
#     que apps/acs/android/app/build.gradle.kts ganhou a guarda, um
#     `flutter build apk` puro nem chega a compilar.
#   · A CA do broker é asset do APK (apps/acs/assets/certs/), regerada pelo
#     mosquitto-init e não versionada. Sem ela o build falha antes do TLS —
#     apps/acs/pubspec.yaml declara o diretório — e não haveria em quem confiar.
#
# A senha nunca é impressa e não trafega na linha de comando do flutter: vai
# num arquivo temporário lido por --dart-define-from-file, criado com 0600
# (mktemp) fora da árvore do repositório e apagado pelo trap abaixo — inclusive
# se o script for interrompido. scripts/qa/e2e.sh ainda passa a senha por
# --dart-define porque aquele caminho roda `flutter test`/`dart run`, não
# `flutter build`, e não passa pela guarda do Gradle.
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
    -h|--help)   sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
google_maps_api_key="${GOOGLE_MAPS_API_KEY:-$(grep -E '^GOOGLE_MAPS_API_KEY=' "$env_file" | head -1 | cut -d= -f2-)}"

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

# json_escape: escapa \ e " para o valor caber dentro de uma string JSON.
# Os valores hoje são hex (senha, gerada por bootstrap_env.sh) e host/URL sem
# aspas — não deveria haver o que escapar na prática, mas a função existe para
# não produzir um JSON inválido silenciosamente se isso mudar.
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# --dart-define-from-file em vez de --dart-define: a senha não pode aparecer
# no argv do flutter, visível em `ps` para outros usuários da mesma máquina.
# mktemp já cria com 0600 e fora da árvore do repositório. SEM `exec` nas
# chamadas de flutter abaixo: `exec` substitui o processo do shell e o trap
# nunca rodaria, deixando o arquivo com a senha esquecido em /tmp — trocaria
# uma exposição temporária por uma persistente, o oposto do que este passo
# quer.
defines_file="$(mktemp)"
trap 'rm -f "$defines_file"' EXIT INT TERM
cat > "$defines_file" <<JSON
{
  "SINALACS_HOST": "$(json_escape "$host")",
  "SINALACS_MQTT_HOST": "$(json_escape "$mqtt_host")",
  "SINALACS_MQTT_USER": "$(json_escape "$mqtt_user")",
  "SINALACS_MQTT_PASSWORD": "$(json_escape "$mqtt_password")",
  "GOOGLE_MAPS_API_KEY": "$(json_escape "$google_maps_api_key")"
}
JSON

echo "ACS → $host   broker → $mqtt_host:8883 (usuário $mqtt_user)"
echo 'senha do broker .... lida do .env, não exibida'

cd "$app_dir"
if [[ "$action" == 'build' ]]; then
  flutter build apk --debug --dart-define-from-file="$defines_file" "${flutter_args[@]}"
else
  flutter run --dart-define-from-file="$defines_file" "${flutter_args[@]}"
fi
