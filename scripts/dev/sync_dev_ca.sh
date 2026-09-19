#!/usr/bin/env bash
#
# Copia as CAs de desenvolvimento para os assets dos apps.
#
# São DUAS CAs, e de propósito:
#   * a do Mosquitto assina o certificado do broker, e o app ACS a usa para o
#     MQTT em 8883;
#   * a do RPC assina o certificado que o Traefik apresenta em 443, e os dois
#     apps a usam para o HTTPS do backend (RNF04).
#
# `SecurityContext.setTrustedCertificatesBytes` lê bytes (e não um caminho, que
# não existiria dentro do APK), então as CAs entram como asset Flutter.
#
# Nenhuma das duas é versionada: infra/docker/mosquitto/runtime/,
# infra/docker/traefik/runtime/ e apps/*/assets/certs/ estão no .gitignore.
#
# ATENÇÃO à distinção, que o `init.sh` do RPC mediu e o do broker confirma: as
# duas CAs são PRESERVADAS entre subidas — só as folhas são regeradas —, então
# esta cópia continua válida enquanto a CA não expirar. A folha muda, mas o app
# confia na CA, não na folha. Rode este script sempre que subir a stack pela
# primeira vez ou depois de apagar um runtime/.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# A propriedade que interessa não é "a CA não expirou": é "esta CA é a que
# assina a folha que o app vai enfrentar". A guarda antiga
# (`openssl x509 -checkend 0`) só responde a primeira, e duas coisas passam por
# ela e são copiadas com exit 0 — as duas medidas:
#   * uma CA com validade 2030–2035: `-checkend` nunca olha o `notBefore`, então
#     uma CA que ainda não vale é aprovada como se valesse;
#   * a CA do broker no lugar da do RPC: são dois certificados válidos e não
#     expirados, e os dois apps quebrariam no TLS sem nada vermelho em lugar
#     nenhum.
# `openssl verify` cobre as duas de uma vez, porque valida a cadeia inteira
# contra a folha: CA errada, CA fora da própria janela de validade e CA
# expirada dão todas erro (exit 2). É o mesmo comando que prova que a cópia
# serve para o handshake.
copy_ca() {
  local source_ca="$1"
  local source_leaf="$2"
  local target_dir="$3"
  local target_ca="$4"
  local label="$5"

  if [[ ! -f "$source_ca" ]]; then
    echo "erro: $source_ca não existe." >&2
    echo "Suba a stack primeiro (docker compose up) para que as CAs sejam geradas." >&2
    exit 1
  fi

  # A folha é gerada pelo init.sh junto com a CA, no mesmo runtime/, então ela
  # existe em qualquer subida normal. Se não existir, não há como provar que a
  # CA é a certa — e é justamente essa prova que separa uma cópia boa de uma
  # que só vai falhar no handshake. Erro, e não cópia.
  if [[ ! -f "$source_leaf" ]]; then
    echo "erro: a folha $source_leaf não existe, então não dá para conferir se a CA de $label é a que assina o certificado em uso." >&2
    echo "Suba a stack primeiro (docker compose up) para que a folha seja gerada de novo." >&2
    exit 1
  fi

  local verify_err
  if ! verify_err="$(openssl verify -CAfile "$source_ca" "$source_leaf" 2>&1)"; then
    echo "erro: a CA de $label em $source_ca não assina a folha $source_leaf — nada foi copiado." >&2
    echo "$verify_err" >&2
    echo "Apague o runtime correspondente e suba a stack de novo." >&2
    exit 1
  fi

  mkdir -p "$target_dir"
  # temporário + mv, e não `cp` direto: `cp` trunca o destino antes de escrever,
  # então uma interrupção no meio (Ctrl-C, OOM) deixaria um .crt pela metade no
  # asset, e o app carregaria um "certificado" quebrado em vez de a cópia
  # anterior continuar valendo. Mesmo remédio que o init.sh do RPC aplicou na
  # folha. `mv` no mesmo diretório é rename: não há janela em que o asset não
  # exista.
  cp "$source_ca" "$target_ca.tmp"
  mv "$target_ca.tmp" "$target_ca"
  echo "CA ($label) copiada para $target_ca"
  openssl x509 -in "$target_ca" -noout -subject -dates
}

for app in acs patient; do
  copy_ca \
    "$repo_root/infra/docker/mosquitto/runtime/certs/ca.crt" \
    "$repo_root/infra/docker/mosquitto/runtime/certs/server.crt" \
    "$repo_root/apps/$app/assets/certs" \
    "$repo_root/apps/$app/assets/certs/dev_ca.crt" \
    "MQTT"
  copy_ca \
    "$repo_root/infra/docker/traefik/runtime/certs/ca.crt" \
    "$repo_root/infra/docker/traefik/runtime/certs/server.crt" \
    "$repo_root/apps/$app/assets/certs" \
    "$repo_root/apps/$app/assets/certs/dev_rpc_ca.crt" \
    "RPC"
done
