#!/usr/bin/env bash
#
# Executa (ou compila) o app do ACS contra a stack local, com as credenciais
# desta máquina.
#
#   ./scripts/dev/run_acs.sh                    # flutter run no dispositivo padrão
#   ./scripts/dev/run_acs.sh -d emulator-5554   # argumentos extras vão para o flutter
#   ./scripts/dev/run_acs.sh --build            # flutter build apk --debug
#   ./scripts/dev/run_acs.sh --host https://192.168.0.10/ --mqtt-host 192.168.0.10
#   ./scripts/dev/run_acs.sh --skip-ca          # não recopia as CAs para o asset
#
# Por que existe:
#   · SINALACS_MQTT_PASSWORD é resolvido em tempo de COMPILAÇÃO e não tem
#     default. O broker cria o usuário acs-area-12 com MQTT_ACS_PASSWORD, um
#     segredo aleatório POR MÁQUINA gerado por scripts/dev/bootstrap_env.sh:
#     nenhum valor embutido no código poderia acertá-lo. Sem este wrapper,
#     `flutter run` produz um app que nunca recebe alerta nenhum — e desde
#     que apps/acs/android/app/build.gradle.kts ganhou a guarda, um
#     `flutter build apk` puro nem chega a compilar.
#   · As DUAS CAs de desenvolvimento são asset do APK (apps/acs/assets/certs/),
#     copiadas pelo sync_dev_ca.sh e não versionadas: a do broker assina o
#     certificado do MQTT em 8883, a do RPC assina o do Traefik em 443. Sem elas
#     o build NÃO falha — sai verde e o APK vai sem certificado nenhum, com uma
#     única pista que ele imprime e ignora ("Error: unable to find directory
#     entry in pubspec.yaml"); o app só se denuncia depois, no handshake do TLS.
#     O `flutter analyze` é o único comando que reclama do diretório ausente —
#     é o que o pubspec declara —, e é por isso que a guarda abaixo confere as
#     duas cópias, uma a uma, contra a folha que está no runtime.
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
# O RPC é HTTPS na 443 (quem termina o TLS é o Traefik): a 8080 em texto claro
# deixou de ser publicada (RNF04/L-08), e um host em http aqui não conecta.
host='https://10.0.2.2/'
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
    # Intervalo sem número fixo: imprime da linha 3 até a primeira que não é
    # comentário. A faixa à mão (era '3,26p') cortava a última frase do texto
    # depois de qualquer edição no cabeçalho — e ninguém percebia, porque a
    # saída do --help não tem teste.
    -h|--help)   sed -n '/^#/!q; 3,$p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
# `|| true` dentro da substituição: sem a linha no .env, o `grep` sai 1, o
# `pipefail` propaga e este script inteiro morria com exit 1 e SAÍDA NENHUMA —
# um `--dart-define` ausente e opcional derrubando o wrapper de forma
# indistinguível de um erro de shell. Medido: `.env` sem `GOOGLE_MAPS_API_KEY=`.
# As outras duas leituras do .env têm guarda depois (a senha vazia é erro
# declarado); esta é a única opcional.
google_maps_api_key="${GOOGLE_MAPS_API_KEY:-$(grep -E '^GOOGLE_MAPS_API_KEY=' "$env_file" | head -1 | cut -d= -f2- || true)}"

if [[ -z "$mqtt_password" ]]; then
  echo 'erro: MQTT_ACS_PASSWORD está vazio no .env.' >&2
  echo 'Rode ./scripts/dev/bootstrap_env.sh --force para regerar os segredos.' >&2
  exit 1
fi

if [[ "$skip_ca" -eq 0 ]]; then
  if ! "$repo_root/scripts/dev/sync_dev_ca.sh"; then
    # Quem diz o que faltou é o próprio sync, logo acima: ele nomeia o
    # runtime/ de origem ausente, ou imprime o erro do openssl verify quando a
    # CA de lá não assina a folha. Aqui só se decide se dá para seguir.
    #
    # Existir não é ser o certo. Os três modos de falha do sync — CA de origem
    # ausente, folha de origem ausente e verify reprovado — dizem a mesma
    # coisa, "o runtime está errado ou não está lá", e nenhum deles é
    # transitório. A frase que justificava o fallback antigo ("as CAs são
    # PRESERVADAS entre subidas, então a cópia anterior continua valendo") é
    # verdadeira no caso comum e FALSA exatamente no caso para o qual o
    # fallback existia: o caminho de recuperação documentado — apagar o
    # runtime/ e subir de novo — faz o init.sh cunhar uma CA NOVA (o `needs_ca`
    # é verdadeiro quando o ca.key não está lá), e a cópia antiga no asset
    # deixa de valer. Medido: exit 0, mensagem tranquilizadora e um APK cuja CA
    # não verifica mais a folha do servidor — o handshake falha e o sintoma
    # aponta para o servidor.
    #
    # Seguir só é seguro com PROVA, e a prova é a mesma pergunta que o sync
    # faz — "esta CA assina a folha do runtime?" —, feita entre o ASSET e o
    # runtime em vez de dentro do runtime. Sem runtime não há o que provar, e
    # aí é erro. O escopo é o asset DESTE app: é ele que o build leva.
    sem_prova=()
    for par in 'MQTT:dev_ca.crt:infra/docker/mosquitto/runtime/certs' \
               'RPC:dev_rpc_ca.crt:infra/docker/traefik/runtime/certs'; do
      IFS=':' read -r label asset_name runtime_rel <<< "$par"
      if [[ ! -f "$app_dir/assets/certs/$asset_name" ]]; then
        sem_prova+=("$asset_name ($label): não está no asset")
      elif [[ ! -f "$repo_root/$runtime_rel/ca.crt" || ! -f "$repo_root/$runtime_rel/server.crt" ]]; then
        sem_prova+=("$asset_name ($label): $runtime_rel/ não tem o par CA+folha")
      elif ! openssl verify -CAfile "$app_dir/assets/certs/$asset_name" \
             "$repo_root/$runtime_rel/server.crt" >/dev/null 2>&1; then
        sem_prova+=("$asset_name ($label): não assina a folha de $runtime_rel/")
      fi
    done
    if (( ${#sem_prova[@]} > 0 )); then
      echo 'erro: não dá para provar que as CAs já copiadas no asset ainda valem:' >&2
      printf '  · %s\n' "${sem_prova[@]}" >&2
      echo 'Suba a stack com `docker compose up` (o erro acima, do sync, diz o que falta) e rode de novo.' >&2
      echo 'Para dispensar a checagem de propósito — assumindo o risco de um APK que não valida o TLS —, use --skip-ca.' >&2
      exit 1
    fi
    echo 'aviso: o sync falhou, mas a CA no asset foi conferida contra a folha do runtime e continua valendo; seguindo com ela.' >&2
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
