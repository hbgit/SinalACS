#!/usr/bin/env bash
#
# Gera a configuração local do SinalACS: `.env` e o `passwords.yaml` do
# Serverpod, ambos com segredos aleatórios desta máquina.
#
#   ./scripts/dev/bootstrap_env.sh           # cria o que faltar, preserva o resto
#   ./scripts/dev/bootstrap_env.sh --force   # recria, sobrescrevendo
#
# Por que existe:
#   · o repositório não traz `.env` nenhum, e o docker-compose.yml agora exige
#     um — cada segredo é `${VAR:?}`, então subir sem ele falha dizendo o que
#     falta, em vez de usar uma senha embutida no arquivo versionado;
#   · `backend/sinalacs_server/config/passwords.yaml` é gitignored e portanto
#     NÃO existe num clone limpo. Sem ele o Serverpod falha ao carregar a
#     config e chama exit(1); como o exit() do Dart não dá flush no stdout, a
#     mensagem se perde e a suíte de testes morre com exit 1 e zero linhas de
#     log. Era preciso recriar o arquivo à mão para rodar os testes.
#
# Nenhum valor gerado é impresso.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

env_file="$repo_root/.env"
env_example="$repo_root/.env.example"
passwords_file="$repo_root/backend/sinalacs_server/config/passwords.yaml"

force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v openssl >/dev/null 2>&1; then
  echo 'erro: openssl não encontrado — é ele que gera os segredos.' >&2
  exit 1
fi

secret() { openssl rand -hex 32; }

# --- .env ------------------------------------------------------------------
if [[ -f "$env_file" && "$force" -eq 0 ]]; then
  echo ".env já existe — preservado. Use --force para recriar."
else
  if [[ ! -f "$env_example" ]]; then
    echo "erro: $env_example não existe." >&2
    exit 1
  fi

  if [[ -f "$env_file" ]]; then
    backup="$env_file.bak.$(date +%Y%m%d%H%M%S)"
    cp "$env_file" "$backup"
    chmod 600 "$backup"
    echo "  .env anterior salvo em $(basename "$backup")"
  fi

  # Preenche cada chave de segredo vazia do modelo; o resto passa intacto,
  # para que comentários e defaults não-secretos continuem valendo.
  POSTGRES_PASSWORD="$(secret)" \
  TEST_DATABASE_PASSWORD="$(secret)" \
  MQTT_BACKEND_PASSWORD="$(secret)" \
  MQTT_ACS_PASSWORD="$(secret)" \
  JWT_SECRET="$(secret)" \
  awk '
    {
      split($0, kv, "=")
      key = kv[1]
      # Só mexe em linha "CHAVE=" sem valor, e só nas chaves de segredo.
      if ($0 ~ /^[A-Z_]+=$/ && ENVIRON[key] != "") {
        print key "=" ENVIRON[key]
      } else {
        print
      }
    }
  ' "$env_example" > "$env_file"

  chmod 600 "$env_file"
  echo "  .env gerado (POSTGRES_PASSWORD, TEST_DATABASE_PASSWORD,"
  echo "               MQTT_BACKEND_PASSWORD, MQTT_ACS_PASSWORD, JWT_SECRET)"
fi

# --- config/passwords.yaml -------------------------------------------------
# O valor PRECISA ser o mesmo TEST_DATABASE_PASSWORD do .env: é a senha do
# Postgres de teste (profile `test`, porta 9090) que o harness do Serverpod
# espera segundo config/test.yaml. Divergir traz de volta a falha silenciosa.
test_password="$(grep -E '^TEST_DATABASE_PASSWORD=' "$env_file" | head -1 | cut -d= -f2-)"
if [[ -z "$test_password" ]]; then
  echo 'erro: TEST_DATABASE_PASSWORD está vazio no .env.' >&2
  exit 1
fi

if [[ -f "$passwords_file" && "$force" -eq 0 ]]; then
  echo "config/passwords.yaml já existe — preservado. Use --force para recriar."
  stored="$(awk '/^test:/{f=1;next} /^[a-z]+:/{f=0} f && /database:/{print $2}' "$passwords_file" | tr -d "'\"")"
  if [[ "$stored" != "$test_password" ]]; then
    echo '  AVISO: a senha em passwords.yaml[test] NÃO bate com TEST_DATABASE_PASSWORD do .env.' >&2
    echo '         O harness de teste vai falhar sem log. Rode com --force para alinhar.' >&2
  fi
else
  mkdir -p "$(dirname "$passwords_file")"
  cat > "$passwords_file" <<YAML
# Gerado por scripts/dev/bootstrap_env.sh. Não versionado (.gitignore).
#
# A senha de `test` é a mesma do TEST_DATABASE_PASSWORD do .env, que alimenta o
# serviço postgres-test do docker-compose. Se as duas divergirem, o Serverpod
# falha ao carregar a config e a suíte morre sem log.
test:
  database: '$test_password'
YAML
  chmod 600 "$passwords_file"
  echo "  config/passwords.yaml gerado (bloco test:, alinhado com o .env)"
fi

# --- avisos ----------------------------------------------------------------
if [[ -d "$repo_root/pg_data" ]]; then
  echo
  echo 'AVISO: ./pg_data/ já existe de uma stack anterior.'
  echo '  POSTGRES_PASSWORD só vale na PRIMEIRA inicialização do volume, então o'
  echo '  banco continuará exigindo a senha antiga e o backend não vai conectar.'
  echo '  Para adotar a senha nova:  docker compose down && rm -rf pg_data/'
fi

echo
echo 'Pronto. Próximo passo: docker compose up --build'
