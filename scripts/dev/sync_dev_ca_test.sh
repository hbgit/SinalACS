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
  mkdir -p "$raiz/apps/acs/assets/certs" "$raiz/apps/patient/assets/certs"
}
sem_tmp() { [[ -z "$(find "$1/apps" -name '*.tmp' 2>/dev/null)" ]]; }

echo "== caso 1: tudo certo copia as CAs e não cria acs_client.*"
monta "$tmp/ok"
SYNC_DEV_CA_ROOT="$tmp/ok" "$script" >/dev/null || falha "o sync falhou numa árvore válida"
for app in acs patient; do
  for ca in dev_ca.crt dev_rpc_ca.crt; do
    [[ -f "$tmp/ok/apps/$app/assets/certs/$ca" ]] || falha "$ca não foi copiada para $app"
  done
done
# Desde a #94 o certificado de cliente é por aparelho, emitido pelo backend: o
# sync não cria acs_client.* em app nenhum.
[[ -z "$(find "$tmp/ok/apps" -name 'acs_client.*')" ]] || falha "o sync criou acs_client.*: $(find "$tmp/ok/apps" -name 'acs_client.*')"
sem_tmp "$tmp/ok" || falha "sobrou .tmp no caminho feliz"
[[ -f "$tmp/ok/apps/admin/assets/certs/dev_rpc_ca.crt" ]] || falha "a CA do RPC não foi copiada para o admin"
[[ ! -e "$tmp/ok/apps/admin/assets/certs/dev_ca.crt" ]] || falha "o admin recebeu a CA do broker"

echo "== caso 2: remove acs_client.* legado de um checkout antigo"
monta "$tmp/legado"
legado="$tmp/legado/apps/acs/assets/certs"
echo 'certificado compartilhado (sintético)' >"$legado/acs_client.crt"
echo 'chave compartilhada (sintética)' >"$legado/acs_client.key"
SYNC_DEV_CA_ROOT="$tmp/legado" "$script" >"$tmp/saida" 2>&1 || falha "o sync falhou com o legado: $(cat "$tmp/saida")"
[[ ! -e "$legado/acs_client.crt" && ! -e "$legado/acs_client.key" ]] || falha "o acs_client.* legado continuou no asset"
grep -q 'acs_client' "$tmp/saida" || falha "a remoção do legado não foi anunciada"

echo "== caso 2b: com a CA do RPC errada nada muda — nem o legado é apagado"
monta "$tmp/errada"
cp "$tmp/errada/infra/docker/mosquitto/runtime/certs/ca.crt" "$tmp/errada/infra/docker/traefik/runtime/certs/ca.crt"
echo 'chave compartilhada (sintética)' >"$tmp/errada/apps/acs/assets/certs/acs_client.key"
if SYNC_DEV_CA_ROOT="$tmp/errada" "$script" >"$tmp/saida" 2>&1; then falha "aceitou a CA do broker no lugar da do RPC"; fi
grep -q "nada foi copiado" "$tmp/saida" || falha "a mensagem não diz que nada foi copiado: $(cat "$tmp/saida")"
[[ "$(find "$tmp/errada/apps" -type f)" == "$tmp/errada/apps/acs/assets/certs/acs_client.key" ]] \
  || falha "a árvore mudou apesar do erro: $(find "$tmp/errada/apps" -type f)"

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

echo "OK — sync_dev_ca.sh: CAs conferidas, sem acs_client.* (o legado é removido), nada muda no erro, sem .tmp"
