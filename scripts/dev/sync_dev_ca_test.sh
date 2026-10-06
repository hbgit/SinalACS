#!/usr/bin/env bash
#
# Prova o sync_dev_ca.sh numa árvore temporária (nunca toca nos assets reais).
# Não precisa de Docker nem de emulador: só do openssl.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$aqui/sync_dev_ca.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

falha() { echo "FALHOU: $*" >&2; exit 1; }

# CA + folha de servidor, tudo descartável.
gera_runtime() {
  local dir="$1"; mkdir -p "$dir"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/ca.key" -out "$dir/ca.crt" -days 2 -subj "/CN=ca-teste" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout "$dir/server.key" -out "$dir/server.csr" -subj "/CN=localhost" 2>/dev/null
  openssl x509 -req -in "$dir/server.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial -out "$dir/server.crt" -days 2 2>/dev/null
}
monta() {
  local raiz="$1"; rm -rf "$raiz"
  gera_runtime "$raiz/infra/docker/mosquitto/runtime/certs"
  gera_runtime "$raiz/infra/docker/traefik/runtime/certs"
  local m="$raiz/infra/docker/mosquitto/runtime/certs"
  openssl req -newkey rsa:2048 -nodes -keyout "$m/acs-area-12.key" -out "$m/c.csr" -subj "/CN=acs-area-12" 2>/dev/null
  openssl x509 -req -in "$m/c.csr" -CA "$m/ca.crt" -CAkey "$m/ca.key" -CAcreateserial -out "$m/acs-area-12.crt" -days 2 2>/dev/null
  mkdir -p "$raiz/apps/acs/assets/certs" "$raiz/apps/patient/assets/certs"
}
sem_tmp() { [[ -z "$(find "$1/apps" -name '*.tmp' 2>/dev/null)" ]]; }

echo "== caso 1: tudo certo copia os assets"
monta "$tmp/ok"
SYNC_DEV_CA_ROOT="$tmp/ok" "$script" >/dev/null || falha "o sync falhou numa árvore válida"
[[ -f "$tmp/ok/apps/acs/assets/certs/acs_client.key" ]] || falha "a chave do cliente não foi copiada"
[[ "$(stat -c %a "$tmp/ok/apps/acs/assets/certs/acs_client.key")" == 600 ]] || falha "a chave do cliente não está em 600"
sem_tmp "$tmp/ok" || falha "sobrou .tmp no caminho feliz"

echo "== caso 2: chave que não é o par do certificado é recusada antes de copiar"
monta "$tmp/par"
m="$tmp/par/infra/docker/mosquitto/runtime/certs"
openssl genrsa -out "$m/acs-area-12.key" 2048 2>/dev/null   # outra chave, mesmo certificado
if SYNC_DEV_CA_ROOT="$tmp/par" "$script" >"$tmp/saida" 2>&1; then falha "aceitou chave de outro par"; fi
grep -q "não é o par" "$tmp/saida" || falha "a mensagem não explicou o motivo: $(cat "$tmp/saida")"
grep -q "nada foi copiado" "$tmp/saida" || falha "a mensagem não diz que nada foi copiado"
[[ -z "$(find "$tmp/par/apps" -type f 2>/dev/null)" ]] || falha "algum asset foi copiado apesar do erro"

echo "== caso 3: falha no meio da publicação não deixa .tmp"
monta "$tmp/meio"
mkdir -p "$tmp/shim"
real="$(command -v openssl)"
# O `openssl x509 -subject` roda DEPOIS do primeiro `mv` (promote_ca): é a falha no meio.
cat >"$tmp/shim/openssl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "-subject" ]] && exit 1; done
exec "$real" "\$@"
EOF
chmod +x "$tmp/shim/openssl"
if PATH="$tmp/shim:$PATH" SYNC_DEV_CA_ROOT="$tmp/meio" "$script" >/dev/null 2>&1; then falha "o sync não falhou com o shim"; fi
sem_tmp "$tmp/meio" || falha "sobrou .tmp depois da falha no meio: $(find "$tmp/meio/apps" -name '*.tmp')"

echo "OK — sync_dev_ca.sh: par conferido, nada copiado no erro, sem .tmp"
