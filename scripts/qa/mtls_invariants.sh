#!/usr/bin/env bash
#
# O broker MQTT identifica cada cliente pelo CERTIFICADO (#94): CA de aparelhos,
# CRL recarregada por sidecar, username = CN e ACL por microárea. Sem senha.
#
#   ./scripts/qa/mtls_invariants.sh
#
# Precisa da stack de desenvolvimento no ar (docker compose up -d), com os
# serviços mosquitto e mosquitto-crl-reload. Cada caso é uma conexão real na
# 8883 (mosquitto_pub/mosquitto_sub em contêiner, rede do host):
#   A) sem certificado de cliente                              -> RECUSADO
#   B) `backend`, folha da CA de aparelhos                      -> ACEITO
#   C) folha de OUTRA CA, com o mesmo CN `backend`              -> RECUSADO
#   D) o certificado compartilhado antigo (CN acs-area-12, CA do servidor),
#      emitido AQUI na hora com runtime/certs/ca.key            -> RECUSADO
#   E) dois aparelhos A e B (CA de aparelhos, CN = microárea do seed, SAN URI
#      por aparelho): ambos aceitos; A é revogado (CRL nova, temporário + mv) e
#      o sidecar grava crl.loaded = sha256 dessa CRL em ≤ 10 s -> A RECUSADO,
#      B ACEITO, e a assinatura longa de B aberta antes da recarga continua
#      recebendo
#   F) o caminho do backend (Task 7a): A tem sessão aberta com RECONEXÃO
#      AUTOMÁTICA (laço `while true` de mosquitto_sub, como o mqtt_client do
#      app); a sessão sobrevive ao SIGHUP; só depois do marcador o script
#      conecta como `backend` com o client id de A (takeover) -> o laço de A
#      tenta reconectar e NENHUMA conexão de A entra no broker em 10 s
#   G) ACL: o aparelho da microárea X com `-u backend` NÃO publica no tópico de
#      alertas (o username do CONNECT é ignorado) e não recebe nada de outra
#      microárea, enquanto recebe o seu (controle positivo publicado pelo backend)
#   H) estático: a crl.pem do backend verifica contra a CA de aparelhos (e não
#      contra outra) e o nextUpdate está a ≥ 7 dias
#   I) o sidecar não derruba o broker: (i) lixo na crl.pem; (ii) CRL VÁLIDA de
#      outra CA — nos dois ele recusa, não sinaliza, não toca em crl.loaded, o
#      broker segue de pé e B e `backend` seguem aceitos
# Em todo grupo o primeiro caso é positivo: um "recusado" sem controle positivo
# antes seria verdade por acidente (broker parado, arquivo ilegível).
#
# A crl.pem é copiada no início e restaurada pelo `trap` de saída, com recarga
# pelo sidecar, para o broker voltar à CRL do backend mesmo se o script falhar.
# O backend também regrava a crl.pem sozinho (no boot e a cada 24 h); a chance
# de isso cair dentro dos ~1–2 min deste script é desprezível, mas, se cair, o
# caso afetado falha em vez de passar por acidente.
#
# As chaves das duas CAs (600, root/uid 1000) são lidas só dentro de contêiner
# como root, pela imagem do backend (sinalacs/server:local, que traz openssl):
# no host o usuário pode não ter leitura. Nenhuma chave ou segredo é impresso.
#
# Códigos de saída: 0 = tudo certo; 1 = algum caso falhou; 4 = falha de
# infraestrutura (docker, arquivos ausentes, broker fora) — nunca é recusa.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

certs="$repo_root/infra/docker/mosquitto/runtime/certs"
devices="$repo_root/infra/docker/mosquitto/runtime/devices"
broker=sinalacs-mosquitto
sidecar=sinalacs-mosquitto-crl-reload
img_mqtt=eclipse-mosquitto:2
img_openssl=sinalacs/server:local
app_uid=1000
# CN dos aparelhos = UUID da microárea do seed (o mesmo da folha qa-tools).
area_x='00000000-0000-4000-8000-000000000003'
topico_x="sinalacs/v1/microareas/$area_x/alerts"
topico_outra='sinalacs/v1/microareas/outra/alerts'
sufixo="mtls-$$"
marcador="$devices/crl.loaded"
id_a="sinalacs-acs-qa-$sufixo-A"
id_b="sinalacs-acs-qa-$sufixo-B"

infra() { echo "erro: $*" >&2; exit 4; }

for f in "$certs/ca.crt" "$devices/ca.crt" "$devices/crl.pem" "$devices/backend.crt" \
         "$devices/backend.key" "$devices/qa-tools.crt" "$devices/qa-tools.key"; do
  [[ -f "$f" ]] || infra "$f não existe (a stack subiu com o init.sh da #94?)."
done
docker image inspect "$img_openssl" >/dev/null 2>&1 \
  || infra "a imagem $img_openssl não existe (docker compose up --build)."

# Pré-condição: o broker responde a um handshake TLS. Sem isso, "recusado" nos
# casos abaixo seria vácuo (broker parado, porta errada).
if ! openssl s_client -connect localhost:8883 -CAfile "$certs/ca.crt" </dev/null >/dev/null 2>&1; then
  infra 'o broker não respondeu ao handshake TLS em localhost:8883 (docker compose up -d?).'
fi
inicio_broker="$(docker inspect -f '{{.State.StartedAt}}' "$broker" 2>/dev/null)" \
  || infra "o contêiner $broker não existe."

tmp="$(mktemp -d)"
mkdir -p "$tmp/novos"
crl_copiada=0
assinantes=()

# Linhas do log do sidecar que contêm $1 (para esperar uma linha NOVA).
log_sidecar_conta() { { docker logs "$sidecar" 2>&1 || true; } | grep -cF "$1" || true; }

# gravar_crl <arquivo em $tmp>: grava na crl.pem real como o backend faz —
# temporário no mesmo diretório + mv (o sidecar vê inode/mtime novos), dono uid
# do backend e 644. Como root em contêiner: no host o diretório é do uid 1000.
gravar_crl() {
  timeout 60 docker run --rm --user root -v "$devices:/d" -v "$tmp:/f:ro" \
    --entrypoint sh "$img_openssl" -c \
    "cp /f/$1 /d/crl.pem.tmp && chown $app_uid /d/crl.pem.tmp && chmod 644 /d/crl.pem.tmp && mv /d/crl.pem.tmp /d/crl.pem"
}

# esperar_log_sidecar <texto> <antes> <segundos>: 0 quando o sidecar logou uma
# linha nova com o texto; 1 se não logou no prazo.
esperar_log_sidecar() {
  local i
  for ((i = 0; i < $3 * 4; i++)); do
    [[ "$(log_sidecar_conta "$1")" -gt "$2" ]] && return 0
    sleep 0.25
  done
  return 1
}

# O marcador do sidecar (Task 7a): sha256 da crl.pem que ele acabou de
# sinalizar, gravado por temporário + mv depois do SIGHUP.
marcador_atual() { tr -d '[:space:]' <"$marcador" 2>/dev/null || true; }
sha_de() { sha256sum "$1" | cut -d' ' -f1; }

# esperar_marcador <arquivo em $tmp> <segundos>: 0 quando crl.loaded tem o
# sha256 do arquivo; 1 se não teve no prazo.
esperar_marcador() {
  local quer i
  quer="$(sha_de "$tmp/$1")"
  for ((i = 0; i < $2 * 4; i++)); do
    [[ "$(marcador_atual)" == "$quer" ]] && return 0
    sleep 0.25
  done
  return 1
}

# marcador_inalterado <valor anterior>: 0 se crl.loaded ainda tem o valor.
marcador_inalterado() { [[ -n "$1" && "$(marcador_atual)" == "$1" ]]; }

restaurar_crl() {
  local antes
  antes="$(log_sidecar_conta 'CRL recarregada')"
  if ! gravar_crl crl-original.pem; then
    echo "AVISO: não consegui restaurar $devices/crl.pem; a cópia ficou em $tmp/crl-original.pem." >&2
    return 1
  fi
  esperar_log_sidecar 'CRL recarregada' "$antes" 15 \
    || echo 'AVISO: a CRL original foi restaurada, mas o sidecar não logou a recarga em 15 s.' >&2
}

limpar() {
  local rc=$?
  local c
  for c in "${assinantes[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  # Sem a restauração, o temporário fica: ele guarda a única cópia da CRL original.
  if [[ "$crl_copiada" -eq 1 ]] && ! restaurar_crl; then
    exit 4
  fi
  rm -rf "$tmp"
  exit "$rc"
}
trap limpar EXIT

cp "$devices/crl.pem" "$tmp/crl-original.pem"
crl_copiada=1

# --- material de teste -------------------------------------------------------
# "De fora": CA própria (no host, é nossa), uma folha dela com CN `backend` e uma
# CRL válida dela (Grupo I-ii).
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 2 \
  -keyout "$tmp/fora-ca.key" -out "$tmp/fora-ca.crt" -subj '/CN=ca-de-fora' >/dev/null 2>&1
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "$tmp/fora.key" -out "$tmp/fora.csr" -subj '/CN=backend' >/dev/null 2>&1
printf 'basicConstraints=CA:FALSE\nextendedKeyUsage=clientAuth\n' >"$tmp/cliente.ext"
openssl x509 -req -days 2 -in "$tmp/fora.csr" -CA "$tmp/fora-ca.crt" -CAkey "$tmp/fora-ca.key" \
  -set_serial "0x$(openssl rand -hex 8)" -extfile "$tmp/cliente.ext" -out "$tmp/fora.crt" >/dev/null 2>&1
: >"$tmp/fora-index.txt"
echo 01 >"$tmp/fora-crlnumber"
printf '[ca]\ndefault_ca = fora\n[fora]\ndatabase = %s\ncrlnumber = %s\ndefault_md = sha256\n' \
  "$tmp/fora-index.txt" "$tmp/fora-crlnumber" >"$tmp/fora.cnf"
openssl ca -gencrl -batch -config "$tmp/fora.cnf" -cert "$tmp/fora-ca.crt" -keyfile "$tmp/fora-ca.key" \
  -crldays 30 -out "$tmp/crl-fora.pem" >/dev/null 2>&1
printf 'isto não é uma CRL\n' >"$tmp/lixo.pem"

# CA temporária do `openssl ca` para a CA de aparelhos: índice próprio, só com os
# aparelhos A e B deste script. `unique_subject = no` porque os dois têm o mesmo
# CN (a microárea), como dois aparelhos reais do mesmo ACS.
: >"$tmp/index.txt"
openssl rand -hex 8 >"$tmp/serial"
echo 1000 >"$tmp/crlnumber"
cat >"$tmp/aparelhos.cnf" <<'CNF'
[ ca ]
default_ca = aparelhos
[ aparelhos ]
database = /f/index.txt
new_certs_dir = /f/novos
serial = /f/serial
crlnumber = /f/crlnumber
certificate = /d/ca.crt
private_key = /d/ca.key
default_md = sha256
default_days = 2
default_crl_days = 1
unique_subject = no
policy = livre
[ livre ]
commonName = supplied
[ folha_A ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
subjectAltName = URI:urn:sinalacs:device:qa-mtls-A
[ folha_B ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
subjectAltName = URI:urn:sinalacs:device:qa-mtls-B
CNF

# Um só contêiner root emite: D (CA do SERVIDOR, runtime/certs/ca.key) e os
# aparelhos A e B (CA de aparelhos), já com a CRL que revoga A pronta — ela só
# vale quando for gravada na crl.pem (Grupo E).
if ! timeout 120 docker run --rm --user root -v "$certs:/s:ro" -v "$devices:/d:ro" -v "$tmp:/f" \
  --entrypoint sh "$img_openssl" -c "
    set -e; cd /f
    openssl req -newkey rsa:2048 -nodes -keyout compartilhado.key -out compartilhado.csr -subj /CN=acs-area-12
    openssl x509 -req -days 1 -in compartilhado.csr -CA /s/ca.crt -CAkey /s/ca.key \
      -set_serial 0x\$(openssl rand -hex 8) -extfile cliente.ext -out compartilhado.crt
    for x in A B; do
      openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -keyout ap-\$x.key -out ap-\$x.csr -subj /CN=$area_x
      openssl ca -batch -config /f/aparelhos.cnf -extensions folha_\$x -notext -in ap-\$x.csr -out ap-\$x.crt
    done
    openssl ca -batch -config /f/aparelhos.cnf -revoke ap-A.crt
    openssl ca -batch -config /f/aparelhos.cnf -gencrl -out crl-revoga-a.pem
    chmod 644 /f/*.crt /f/*.key /f/*.pem
  " >/dev/null 2>&1; then
  infra 'a emissão do material de teste em contêiner falhou.'
fi
chmod 644 "$tmp"/*.crt "$tmp"/*.key "$tmp"/*.pem 2>/dev/null || true

# --- helpers -----------------------------------------------------------------
# cert_args <ident>: `nenhum` ou o caminho, no contêiner, sem extensão
# (/d/backend, /f/ap-A, ...): /d = runtime/devices, /f = temporário.
cert_args() {
  [[ "$1" == nenhum ]] && return 0
  printf '%s\n' --cert "$1.crt" --key "$1.key"
}

# publicar <ident> [args do mosquitto_pub]: sem args, publica `x` num tópico de
# sondagem. Códigos: 0 = aceito; 1 = recusado pelo broker (mosquitto_pub rodou e
# a saída traz a marca de recusa: conexão perdida no handshake TLS ou CONNACK
# negado); 2 = erro de infraestrutura (docker, timeout, imagem) — NUNCA conta
# como recusa. A saída do mosquitto_pub é guardada, nunca impressa.
publicar() {
  local ident="$1"; shift
  local saida rc=0 cert
  mapfile -t cert < <(cert_args "$ident")
  [[ $# -gt 0 ]] || set -- -t sinalacs/v1/mtls/probe -m x
  saida="$(timeout 20 docker run --rm --network host \
    -v "$certs:/s:ro" -v "$devices:/d:ro" -v "$tmp:/f:ro" "$img_mqtt" \
    mosquitto_pub -h localhost -p 8883 --cafile /s/ca.crt "${cert[@]}" "$@" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  if [[ "$rc" -eq 5 || "$rc" -eq 7 ]] \
     && grep -qiE 'connection was lost|connection was refused|connection refused|not authori[sz]ed|protocol error' <<<"$saida"; then
    return 1
  fi
  return 2
}

# assinar <nome> <ident> <client id> [args do mosquitto_sub]: assinante em
# contêiner destacado, com -v (tópico + payload no log do contêiner). Só volta
# quando o broker logou a conexão daquele client id (≤ 10 s); 2 se não.
assinar() {
  local nome="$1" ident="$2" id="$3" i cert; shift 3
  mapfile -t cert < <(cert_args "$ident")
  assinantes+=("$nome")
  docker run -d --name "$nome" --network host \
    -v "$certs:/s:ro" -v "$devices:/d:ro" -v "$tmp:/f:ro" "$img_mqtt" \
    mosquitto_sub -h localhost -p 8883 --cafile /s/ca.crt "${cert[@]}" -i "$id" -v "$@" >/dev/null 2>&1 || return 2
  for ((i = 0; i < 40; i++)); do
    docker logs --since 2m "$broker" 2>&1 | grep -qF " as $id (" && return 0
    sleep 0.25
  done
  return 2
}

# assinar_reconectando <nome> <ident> <client id> <tópico>: como `assinar`, mas
# com reconexão automática — um laço `while true` que reabre o mosquitto_sub
# 0,2 s depois de cada saída e loga `saiu <código>`, como o mqtt_client do app
# com autoReconnect. Só volta quando o broker logou a conexão (≤ 10 s); 2 se não.
assinar_reconectando() {
  local nome="$1" ident="$2" id="$3" topico="$4" i
  assinantes+=("$nome")
  docker run -d --name "$nome" --network host \
    -v "$certs:/s:ro" -v "$devices:/d:ro" -v "$tmp:/f:ro" --entrypoint sh "$img_mqtt" -c \
    "while true; do mosquitto_sub -h localhost -p 8883 --cafile /s/ca.crt --cert $ident.crt --key $ident.key -i $id -v -t $topico; echo \"saiu \$?\"; sleep 0.2; done" \
    >/dev/null 2>&1 || return 2
  for ((i = 0; i < 40; i++)); do
    docker logs --since 2m "$broker" 2>&1 | grep -qF " as $id (" && return 0
    sleep 0.25
  done
  return 2
}

# saidas <contêiner>: quantas vezes o mosquitto_sub do laço saiu.
saidas() { { docker logs "$1" 2>&1 || true; } | grep -c '^saiu ' || true; }
# sem_saidas <contêiner>: 0 se a sessão do laço nunca caiu.
sem_saidas() { [[ "$(saidas "$1")" -eq 0 ]]; }
# tentou_reconectar <contêiner> <mínimo> <segundos>: 0 quando o laço já saiu ao
# menos <mínimo> vezes — a reconexão foi tentada (o zero do F não é vácuo).
tentou_reconectar() {
  local i
  for ((i = 0; i < $3 * 4; i++)); do
    [[ "$(saidas "$1")" -ge "$2" ]] && return 0
    sleep 0.25
  done
  return 1
}
# conexoes_de_a_desde <instante RFC 3339>: 0 se o broker aceitou alguma conexão
# do client id de A com o certificado de A (username = CN da microárea) desde o
# instante; 1 se nenhuma. O takeover tem o mesmo client id, mas u'backend'.
conexoes_de_a_desde() {
  docker logs --since "$1" "$broker" 2>&1 | grep -F " as $id_a (" | grep -qF "u'$area_x'"
}

# recebeu <nome> <payload> [segundos]: 0 se o payload apareceu no assinante
# dentro do prazo (padrão 5 s); 1 se não.
recebeu() {
  local i
  for ((i = 0; i < ${3:-5} * 4; i++)); do
    docker logs "$1" 2>&1 | grep -qF "$2" && return 0
    sleep 0.25
  done
  return 1
}
# ja_recebeu <nome> <payload>: sem espera. Só vale DEPOIS de um `recebeu` de um
# controle publicado mais tarde pelo mesmo caminho (entrega em ordem).
ja_recebeu() { docker logs "$1" 2>&1 | grep -qF "$2"; }

# sessao_viva <contêiner> [segundos]: 0 se o assinante continua rodando depois
# do prazo (padrão 0); 1 assim que ele sai.
sessao_viva() {
  local i estado
  for ((i = 0; i <= ${2:-0} * 5; i++)); do
    estado="$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" || return 2
    [[ "$estado" == true ]] || return 1
    [[ "$i" -lt $((${2:-0} * 5)) ]] && sleep 0.2
  done
  return 0
}

# broker_de_pe: o mesmo processo de antes (StartedAt igual) e ainda rodando.
broker_de_pe() {
  [[ "$(docker inspect -f '{{.State.Running}} {{.State.StartedAt}}' "$broker" 2>/dev/null)" == "true $inicio_broker" ]]
}

# trocar_crl <arquivo> <texto do sidecar> <segundos>: grava e espera a linha nova.
trocar_crl() {
  local antes
  antes="$(log_sidecar_conta "$2")"
  gravar_crl "$1" || return 2
  esperar_log_sidecar "$2" "$antes" "$3"
}

# trocar_crl_marcada <arquivo> <segundos>: grava e espera o marcador do sidecar
# com o sha256 do arquivo — o mesmo sinal que o backend espera antes do takeover.
trocar_crl_marcada() {
  gravar_crl "$1" || return 2
  esperar_marcador "$1" "$2"
}

crl_verifica() { # <crl em $tmp> <ca>
  local saida
  saida="$(openssl crl -in "$tmp/$1" -CAfile "$2" -noout 2>&1)" && grep -q 'verify OK' <<<"$saida"
}
proxima_atualizacao_em_dias() { # <crl em $tmp> <dias>
  local nu
  nu="$(openssl crl -in "$tmp/$1" -noout -nextupdate 2>/dev/null | cut -d= -f2-)" || return 2
  [[ -n "$nu" ]] || return 1
  (( $(date -d "$nu" +%s) - $(date +%s) >= $2 * 86400 ))
}

falhas=0
esperar() { # esperar <aceito|recusado> <nome> <comando...>
  local quer="$1" nome="$2" rc=0 got; shift 2
  "$@" || rc=$?
  case "$rc" in
    0) got=aceito ;;
    1) got=recusado ;;
    *) echo "erro: $nome — falha de infraestrutura (código $rc), não é recusa do broker." >&2; exit 4 ;;
  esac
  if [[ "$got" == "$quer" ]]; then echo "ok:    $nome ($got)"; else echo "FALHOU: $nome — esperava $quer, foi $got"; falhas=$((falhas + 1)); fi
}
grupo() { echo; echo "== Grupo $1 =="; }

# --- casos -------------------------------------------------------------------
grupo A 'sem certificado'
esperar aceito   "A) controle: a folha qa-tools da CA de aparelhos conecta" publicar /d/qa-tools
esperar recusado "A) sem certificado de cliente" publicar nenhum

grupo B 'backend'
esperar aceito   "B) backend, folha da CA de aparelhos" publicar /d/backend

grupo C 'outra CA'
esperar aceito   "C) controle: backend da CA de aparelhos" publicar /d/backend
esperar recusado "C) folha de outra CA com o mesmo CN backend" publicar /f/fora

grupo D 'certificado compartilhado antigo'
esperar aceito   "D) controle: backend da CA de aparelhos" publicar /d/backend
esperar recusado "D) CN acs-area-12 emitido agora pela CA do servidor" publicar /f/compartilhado

grupo E 'revogação de um aparelho'
esperar aceito   "E) o marcador do sidecar bate com a crl.pem atual" esperar_marcador crl-original.pem 10
esperar aceito   "E) aparelho A conecta antes da revogação" publicar /f/ap-A -t sinalacs/v1/alerts/qa/acks -m x
esperar aceito   "E) aparelho B conecta antes da revogação" publicar /f/ap-B -t sinalacs/v1/alerts/qa/acks -m x
esperar aceito   "E) sessão longa de A, com reconexão automática, aberta antes da revogação" \
  assinar_reconectando "$sufixo-sub-a" /f/ap-A "$id_a" "$topico_x"
esperar aceito   "E) assinatura longa de B aberta antes da revogação" assinar "$sufixo-sub-b" /f/ap-B "$id_b" -t "$topico_x"
esperar aceito   "E) o sidecar grava crl.loaded = sha256 da CRL que revoga A em ≤ 10 s" trocar_crl_marcada crl-revoga-a.pem 10
esperar aceito   "E) B continua aceito depois da recarga" publicar /f/ap-B -t sinalacs/v1/alerts/qa/acks -m x
esperar recusado "E) A é recusado depois da recarga" publicar /f/ap-A -t sinalacs/v1/alerts/qa/acks -m x
publicar /d/backend -t "$topico_x" -m "pos-recarga-$sufixo" || infra 'o backend não publicou o controle do Grupo E.'
esperar aceito   "E) a assinatura longa de B continua recebendo" recebeu "$sufixo-sub-b" "pos-recarga-$sufixo"

grupo F 'takeover depois do marcador, com reconexão automática'
# A ordem do backend (DeviceRevocationEffects): CRL por temporário + mv,
# marcador (Grupo E) e só então o takeover. Sem o marcador, o laço de A
# reconectaria antes de o broker reler a CRL (medido no e2e da Task 7).
esperar aceito   "F) a sessão de A sobreviveu ao SIGHUP sem cair" sem_saidas "$sufixo-sub-a"
antes_takeover="$(date -u '+%Y-%m-%dT%H:%M:%S.%NZ')"
antes_takeover_s="$(date +%s)"
esperar aceito   "F) backend conecta com o client id de A (takeover)" publicar /d/backend -i "$id_a" -t sinalacs/v1/mtls/probe -m x
esperar aceito   "F) o laço de A tenta reconectar (≥ 2 saídas em 10 s)" tentou_reconectar "$sufixo-sub-a" 2 10
resta=$(( antes_takeover_s + 10 - $(date +%s) ))
[[ "$resta" -gt 0 ]] && sleep "$resta"
esperar recusado "F) alguma conexão de A no broker em 10 s depois do takeover" conexoes_de_a_desde "$antes_takeover"
esperar recusado "F) A não reconecta" publicar /f/ap-A -i "$id_a" -t sinalacs/v1/alerts/qa/acks -m x

grupo G 'ACL por microárea'
# X = a folha qa-tools (CN = microárea do seed). Os negativos dependem da ordem
# de entrega: cada mensagem "proibida" sai ANTES do controle, e o controle só é
# lido depois de chegar — se a proibida tivesse passado, já estaria no log.
esperar aceito   "G) assinante X (próprio tópico e o de outra microárea)" \
  assinar "$sufixo-sub-x" /d/qa-tools "qa-$sufixo-x" -t "$topico_x" -t "$topico_outra"
esperar aceito   "G) assinante backend no tópico de alertas de X" \
  assinar "$sufixo-sub-back" /d/backend "qa-$sufixo-back" -t "$topico_x" -t "$topico_outra" -t 'sinalacs/v1/alerts/+/acks'
publicar /d/backend -t "$topico_outra" -m "outra-$sufixo" || infra 'o backend não publicou em outra microárea.'
publicar /d/backend -t "$topico_x" -m "propria-$sufixo" || infra 'o backend não publicou na microárea X.'
esperar aceito   "G) X recebe o alerta da própria microárea" recebeu "$sufixo-sub-x" "propria-$sufixo"
esperar aceito   "G) a mensagem de outra microárea foi publicada (backend a recebe)" recebeu "$sufixo-sub-back" "outra-$sufixo"
esperar recusado "G) X não recebe o alerta de outra microárea" ja_recebeu "$sufixo-sub-x" "outra-$sufixo"
esperar aceito   "G) X publica o ACK no tópico permitido" \
  publicar /d/qa-tools -t sinalacs/v1/alerts/qa/acks -q 1 -m "ack-$sufixo"
esperar aceito   "G) o ACK de X chega ao backend" recebeu "$sufixo-sub-back" "ack-$sufixo"
esperar aceito   "G) X conecta com -u backend (o username é ignorado, não recusado)" \
  publicar /d/qa-tools -u backend -t "$topico_x" -q 1 -m "forjado-$sufixo"
publicar /d/backend -t "$topico_x" -m "controle-$sufixo" || infra 'o backend não publicou o controle do Grupo G.'
esperar aceito   "G) o controle do backend chega depois da tentativa" recebeu "$sufixo-sub-back" "controle-$sufixo"
esperar recusado "G) o alerta forjado por X com -u backend não foi entregue" ja_recebeu "$sufixo-sub-back" "forjado-$sufixo"

grupo H 'CRL publicada pelo backend'
esperar aceito   "H) a crl.pem verifica contra a CA de aparelhos" crl_verifica crl-original.pem "$devices/ca.crt"
esperar recusado "H) a mesma crl.pem não verifica contra outra CA" crl_verifica crl-original.pem "$tmp/fora-ca.crt"
esperar aceito   "H) nextUpdate a pelo menos 7 dias" proxima_atualizacao_em_dias crl-original.pem 7

grupo I 'o sidecar não derruba o broker'
esperar aceito   "I) controle: B aceito antes das mutações" publicar /f/ap-B -t sinalacs/v1/alerts/qa/acks -m x
marcado="$(marcador_atual)"
esperar aceito   "I-i) lixo na crl.pem: o sidecar recusa" trocar_crl lixo.pem 'CRL recusada pelo sidecar' 10
sleep 5
esperar aceito   "I-i) o broker continua de pé" broker_de_pe
esperar aceito   "I-i) o marcador não muda" marcador_inalterado "$marcado"
esperar aceito   "I-i) B continua aceito" publicar /f/ap-B -t sinalacs/v1/alerts/qa/acks -m x
esperar aceito   "I-ii) CRL válida de outra CA: o sidecar recusa" trocar_crl crl-fora.pem 'CRL recusada pelo sidecar' 10
sleep 5
esperar aceito   "I-ii) o broker continua de pé" broker_de_pe
esperar aceito   "I-ii) o marcador não muda" marcador_inalterado "$marcado"
esperar aceito   "I-ii) B continua aceito" publicar /f/ap-B -t sinalacs/v1/alerts/qa/acks -m x
esperar aceito   "I-ii) backend continua aceito" publicar /d/backend

echo
[[ "$falhas" -eq 0 ]] && echo "OK — o broker identifica pelo certificado da CA de aparelhos, recarrega a CRL pelo sidecar (com o marcador crl.loaded) e aplica a ACL por microárea" \
  || { echo "$falhas falha(s)"; exit 1; }
