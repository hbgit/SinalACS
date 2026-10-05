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
#
# As três fases (conferir → preparar → renomear) existem porque a pergunta
# "copia ou não copia?" é do CONJUNTO, não de cada par. Conferir dentro do par —
# como este script fazia — deixa o estado misto: com a CA do RPC errada e a do
# broker certa, o laço copiava a do broker para o ACS, só então falhava no par
# do RPC, e imprimia "nada foi copiado" com um dos quatro assets já alterado.
# Quem relê a mensagem conclui que o asset está como estava. Medido: era o que
# acontecia.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Só o teste (sync_dev_ca_test.sh) sobrescreve: aponta para uma árvore temporária.
repo_root="${SYNC_DEV_CA_ROOT:-$repo_root}"

# Os seis temporários das fases 2 e 3. `mv` consome o seu; o que sobrar numa
# falha ou num Ctrl-C (o `trap EXIT` roda nos dois) é apagado aqui, para o asset
# nunca ficar ao lado de um `.tmp` meio escrito.
limpar_tmp() {
  rm -f "$repo_root"/apps/{acs,patient}/assets/certs/{dev_ca.crt,dev_rpc_ca.crt}.tmp \
        "$repo_root"/apps/acs/assets/certs/acs_client.{crt,key}.tmp
}
trap limpar_tmp EXIT

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
check_ca() {
  local source_ca="$1"
  local source_leaf="$2"
  local label="$3"

  if [[ ! -f "$source_ca" ]]; then
    echo "erro: $source_ca não existe — nada foi copiado." >&2
    echo "Suba a stack primeiro (docker compose up) para que as CAs sejam geradas." >&2
    exit 1
  fi

  # A folha é gerada pelo init.sh junto com a CA, no mesmo runtime/, então ela
  # existe em qualquer subida normal. Se não existir, não há como provar que a
  # CA é a certa — e é justamente essa prova que separa uma cópia boa de uma
  # que só vai falhar no handshake. Erro, e não cópia.
  if [[ ! -f "$source_leaf" ]]; then
    echo "erro: a folha $source_leaf não existe, então não dá para conferir se a CA de $label é a que assina o certificado em uso — nada foi copiado." >&2
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
}

# Prepara a cópia no `.tmp`, sem mexer ainda no asset. Quem renomeia é a fase 3.
stage_ca() {
  local source_ca="$1"
  local target_dir="$2"
  local target_ca="$3"

  mkdir -p "$target_dir"
  # temporário + mv, e não `cp` direto: `cp` trunca o destino antes de escrever,
  # então uma interrupção no meio (Ctrl-C, OOM) deixaria um .crt pela metade no
  # asset, e o app carregaria um "certificado" quebrado em vez de a cópia
  # anterior continuar valendo. Mesmo remédio que o init.sh do RPC aplicou na
  # folha. `mv` no mesmo diretório é rename: não há janela em que o asset não
  # exista.
  #
  # O `mv` fica para a fase 3 de propósito: assim um erro de I/O no TERCEIRO
  # `cp` (disco cheio) não deixa dois assets novos e dois velhos — os quatro
  # continuam como estavam, que é o estado que o erro declara.
  cp "$source_ca" "$target_ca.tmp"
}

# Fase 3 — renomear. `mv` no mesmo diretório é rename: não há janela em que o
# asset não exista, e nada aqui pode falhar por espaço ou por leitura da origem.
promote_ca() {
  local target_ca="$1"
  local label="$2"

  mv "$target_ca.tmp" "$target_ca"
  echo "CA ($label) copiada para $target_ca"
  openssl x509 -in "$target_ca" -noout -subject -dates
}

# Os dois pares e os quatro assets, numa tabela só: a mesma lista alimenta as
# três fases, então conferir, preparar e renomear não podem divergir.
# Formato: rótulo | runtime/ de origem | nome do arquivo no asset.
pares=(
  "MQTT|infra/docker/mosquitto/runtime/certs|dev_ca.crt"
  "RPC|infra/docker/traefik/runtime/certs|dev_rpc_ca.crt"
)

# Fase 1 — conferir os DOIS pares de origem antes de copiar QUALQUER um dos
# QUATRO assets (cada par alimenta os dois apps). É o que faz a mensagem "nada
# foi copiado" ser verdadeira em todos os caminhos de erro.
for par in "${pares[@]}"; do
  IFS='|' read -r label runtime_rel _ <<< "$par"
  check_ca \
    "$repo_root/$runtime_rel/ca.crt" \
    "$repo_root/$runtime_rel/server.crt" \
    "$label"
done

# mTLS do broker: o ACS também apresenta um certificado de CLIENTE
# (acs-area-12, emitido pelo init.sh do Mosquitto). Mesma prova da CA: a folha
# tem de ser assinada pela CA do broker que está em runtime/, senão o handshake
# falha no app sem nada vermelho em lugar nenhum. **Só desenvolvimento**: a
# chave privada vira asset gitignorado (o guard do Gradle barra um release com
# ela dentro).
mqtt_certs="$repo_root/infra/docker/mosquitto/runtime/certs"
acs_assets="$repo_root/apps/acs/assets/certs"
for f in acs-area-12.crt acs-area-12.key; do
  if [[ ! -f "$mqtt_certs/$f" ]]; then
    echo "erro: $mqtt_certs/$f não existe — nada foi copiado." >&2
    echo "Suba a stack primeiro (docker compose up) para que o certificado de cliente seja gerado." >&2
    exit 1
  fi
done
if ! verify_err="$(openssl verify -CAfile "$mqtt_certs/ca.crt" "$mqtt_certs/acs-area-12.crt" 2>&1)"; then
  echo "erro: a CA do broker não assina o certificado de cliente $mqtt_certs/acs-area-12.crt — nada foi copiado." >&2
  echo "$verify_err" >&2
  exit 1
fi
# O certificado ser da CA não prova que a chave é o par dele: uma chave regerada
# sem o certificado passaria no `verify` e o handshake mTLS falharia no app sem
# nada vermelho em lugar nenhum. Compara a chave pública dos dois.
pub_crt="$(openssl x509 -in "$mqtt_certs/acs-area-12.crt" -noout -pubkey)"
pub_key="$(openssl pkey -in "$mqtt_certs/acs-area-12.key" -pubout 2>/dev/null || true)"
if [[ -z "$pub_key" || "$pub_crt" != "$pub_key" ]]; then
  echo "erro: $mqtt_certs/acs-area-12.key não é o par do certificado acs-area-12.crt — nada foi copiado." >&2
  echo "Apague infra/docker/mosquitto/runtime e suba a stack de novo para regerar o par." >&2
  exit 1
fi

# Fase 2 — preparar os quatro (nada visível ainda para quem lê o asset).
for app in acs patient; do
  for par in "${pares[@]}"; do
    IFS='|' read -r _ runtime_rel asset_name <<< "$par"
    stage_ca \
      "$repo_root/$runtime_rel/ca.crt" \
      "$repo_root/apps/$app/assets/certs" \
      "$repo_root/apps/$app/assets/certs/$asset_name"
  done
done

# Cliente do ACS: temporário + mv, igual às CAs. A chave nasce 600 (umask) e
# o chmod é explícito para não depender dele.
mkdir -p "$acs_assets"
(umask 077; cp "$mqtt_certs/acs-area-12.key" "$acs_assets/acs_client.key.tmp")
chmod 600 "$acs_assets/acs_client.key.tmp"
cp "$mqtt_certs/acs-area-12.crt" "$acs_assets/acs_client.crt.tmp"

# Fase 3 — publicar os quatro.
for app in acs patient; do
  for par in "${pares[@]}"; do
    IFS='|' read -r label runtime_rel asset_name <<< "$par"
    promote_ca \
      "$repo_root/apps/$app/assets/certs/$asset_name" \
      "$label"
  done
done

mv "$acs_assets/acs_client.crt.tmp" "$acs_assets/acs_client.crt"
mv "$acs_assets/acs_client.key.tmp" "$acs_assets/acs_client.key"
echo "Certificado de cliente do ACS (mTLS) copiado para $acs_assets/acs_client.{crt,key}"
openssl x509 -in "$acs_assets/acs_client.crt" -noout -subject -dates
