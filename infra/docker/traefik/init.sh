#!/bin/sh
#
# Gera a CA de desenvolvimento do RPC e as quatro folhas assinadas por ela
# (RNF04): a que o Traefik apresenta em :443; desde a issue #78, a que o
# backend apresenta ao Traefik na 8080 interna (runtime/backend/); e, desde a
# issue #90, as duas folhas de CLIENTE do mTLS dessa 8080 — a que o Traefik
# apresenta ao backend (runtime/certs/traefik-client.*) e a que o HEALTHCHECK
# do container do backend apresenta a si mesmo (runtime/backend/healthcheck.*).
#
# CA PRÓPRIA, separada da do Mosquitto: aquela é consumida pelo broker, pelo
# asset do app ACS e pela conexão de saída do backend — três coisas que hoje
# funcionam e são validadas. Unificar as duas é uma limpeza possível, mas
# obrigaria a mexer no init.sh do broker e nos caminhos de runtime/ dele; o
# ganho não paga o risco num requisito que é aditivo.
#
# A CA é PRESERVADA entre subidas, e só o certificado do servidor é regerado a
# cada execução. O que os apps carregam como asset é a CA (copiada por
# scripts/dev/sync_dev_ca.sh): regerá-la a cada `docker compose up` invalidaria
# a cópia dentro do APK e o app passaria a falhar a validação TLS depois de um
# restart da stack, sem ninguém ter mexido em nada — o mesmo modo de falha que
# o init.sh do broker já corrigiu uma vez. Nada mais aponta para o certificado
# do servidor (os clientes confiam na CA, não na folha), então regerá-lo a cada
# subida é barato.
#
# Regerar a folha NÃO faz uma mudança de SAN chegar sozinha a um Traefik que já
# está de pé (medido): o Traefik lê o certificado no boot e não relê o arquivo, e
# o Compose não recria o serviço dependente quando só o `environment` de um
# one-shot muda — o `traefik` segue no mesmo container, servindo o fingerprint
# antigo, sem nenhuma pista para quem testa em aparelho físico. Subir a stack do
# zero funciona, porque o `depends_on: service_completed_successfully` roda o
# `traefik-init` antes do `traefik`; com a stack de pé, a folha nova só passa a
# ser servida depois de `docker compose restart traefik`.
#
# Uso: sh init.sh   (ou pelo serviço `traefik-init` do docker-compose.yml)
set -eu

# Diretório de runtime. Dentro do container é /certs — é o que o serviço
# `traefik-init` do docker-compose.yml monta a partir de
# infra/docker/traefik/runtime —, e o subdiretório `certs` é o que o Traefik
# monta em /certs. Mesma forma do runtime do Mosquitto, onde o init.sh escreve
# em runtime/certs/ e os consumidores montam essa pasta.
runtime_dir="/certs"
certs_subdir=certs
certs_dir="$runtime_dir/$certs_subdir"
mkdir -p "$certs_dir"

# Extensões de SAN. `10.0.2.2` é o host da máquina de desenvolvimento visto de
# dentro do emulador Android, e `localhost` cobre as ferramentas de QA que
# rodam na máquina. Para validar em aparelho físico na LAN:
#   RPC_CERT_SAN_EXTRA='IP:192.168.0.10' docker compose up
# Com a stack JÁ DE PÉ, acrescente um restart do Traefik: ele só relê a folha no
# boot, então sem isto continua servindo o SAN antigo (ver o cabeçalho):
#   docker compose restart traefik
san="DNS:localhost,IP:127.0.0.1,IP:10.0.2.2"
if [ -n "${RPC_CERT_SAN_EXTRA:-}" ]; then
  san="$san,${RPC_CERT_SAN_EXTRA}"
fi

ca_days=3650
server_days=825
# A folha do healthcheck é curta de propósito (#90): é regerada a cada subida,
# nada mais depende dela, e uma folha de cliente que vive pouco é uma folha de
# cliente que não vale muito se vazar do container. O Grupo E do
# tls_invariants.sh acusa quando faltam menos de 7 dias.
healthcheck_days=90

# Reaproveita a CA existente enquanto ela estiver legível e longe de vencer (30
# dias), como o init.sh do broker. Ver o cabeçalho sobre por que ela não é
# regerada a cada subida.
#
# A guarda checa existência, validade E usabilidade. Só as duas primeiras deixam
# passar um `ca.key` truncado — o arquivo existe e o `ca.crt` está longe de
# vencer —, e a falha só aparecia na hora de assinar, depois de o `server.key`
# já ter sido sobrescrito. Desde então ela sai com diagnóstico antes de tocar em
# qualquer coisa.
#
# E sai com o MESMO diagnóstico nos dois casos que recusam: uma chave
# inutilizável e uma CA a menos de 30 dias de vencer têm a mesma consequência
# para quem já copiou a CA para os apps, então não podem ter políticas opostas.
# Tinham: a expiração regerava em silêncio o que a chave truncada se recusava a
# regerar, duas linhas de distância, invalidando as mesmas cópias sem avisar.
# Agora as duas passam por `recusar_regen`. Regerar continua acontecendo — e
# avisando — só quando não há CA nenhuma para preservar.
recusar_regen() {
  echo "erro: $1" >&2
  echo "erro: nada foi regerado de propósito — regerar a CA invalidaria as cópias já feitas para os apps." >&2
  echo "erro: para forçar, apague $certs_dir/ca.crt e $certs_dir/ca.key, suba a stack de novo" >&2
  echo "erro: e rode scripts/dev/sync_dev_ca.sh para os apps confiarem na CA nova." >&2
  exit 1
}

needs_ca=0
if [ ! -f "$certs_dir/ca.crt" ] || [ ! -f "$certs_dir/ca.key" ]; then
  needs_ca=1
elif ! checkend_out="$(openssl x509 -in "$certs_dir/ca.crt" -noout -checkend 2592000 2>&1)"; then
  # A mensagem do openssl entra na nossa porque `-checkend` reprova por dois
  # motivos distintos — "Certificate will expire" para quem está a menos de 30
  # dias do fim, "Could not read certificate file" para um arquivo ilegível —,
  # e afirmar "expira em menos de 30 dias" nos dois seria inventar a causa.
  recusar_regen "a CA do RPC em $certs_dir/ca.crt não passou na checagem de 30 dias: $checkend_out"
elif ! openssl pkey -in "$certs_dir/ca.key" -noout >/dev/null 2>&1; then
  recusar_regen "a chave da CA do RPC em $certs_dir/ca.key não é utilizável (vazia, truncada ou ilegível)."
else
  # Só aqui a CA é de fato reaproveitada: as três guardas passaram. A mensagem
  # importa porque uma CA rotacionada sem aviso é o outro modo de falha silenciosa
  # deste script — quem lê "reaproveitada" sabe que as cópias nos apps continuam
  # valendo.
  echo "CA de desenvolvimento do RPC reaproveitada de $certs_dir/ca.crt."
fi

if [ "$needs_ca" -eq 1 ]; then
  echo 'Gerando CA de desenvolvimento do RPC...'
  openssl genrsa -out "$certs_dir/ca.key" 4096 2>/dev/null
  openssl req -x509 -new -nodes -key "$certs_dir/ca.key" -sha256 -days "$ca_days" \
    -subj "/C=BR/O=SinalACS Dev/CN=SinalACS Dev RPC CA" \
    -out "$certs_dir/ca.crt"
  # A CA mudou: o certificado do servidor assinado pela antiga não serve, e a
  # serial antiga não deve ser continuada.
  rm -f "$certs_dir/ca.srl" "$certs_dir/server.crt" "$certs_dir/server.key"
  # Aqui a CA foi regerada, então o remédio tem de sair: é o único caso em que
  # este script invalida as cópias dos apps de propósito. Sem esta linha, quem
  # acabou de apagar o runtime/ (o caminho de recuperação documentado) sobe a
  # stack, vê tudo verde e fica com um APK que não valida o TLS.
  echo 'A CA do RPC foi regerada: as cópias em apps/*/assets/certs/ acabaram de'
  echo 'deixar de valer. Rode ./scripts/dev/sync_dev_ca.sh antes de compilar os apps.'
fi

# A folha vai para arquivos temporários e só substitui o que está em uso depois
# de assinada com sucesso. Sem isto, uma falha de OpenSSL destrói o certificado
# anterior: o `openssl x509 -req` trunca o arquivo de `-out` ANTES de falhar, e a
# folha boa em uso vira um arquivo de 0 byte — foi o que aconteceu com o
# `2>/dev/null` que engolia o erro e o `set -e` abortando depois. O par
# `ca.crt`/`ca.key` de CAs diferentes cai no mesmo caminho (a chave é legível, a
# assinatura é que não casa), e também tem de sair com diagnóstico.
#
# São QUATRO folhas desde a issue #90, todas assinadas por esta CA: duas de
# SERVIDOR — a que o Traefik apresenta aos apps em :443 (`server`) e a que o
# backend apresenta ao Traefik na 8080 interna (`backend`, #78) — e duas de
# CLIENTE — a que o Traefik apresenta ao backend (`traefik-client`) e a que o
# healthcheck do container do backend apresenta (`healthcheck`). O EKU é o que
# separa as duas famílias: o BoringSSL do backend recusa uma folha `serverAuth`
# apresentada como cliente, então reaproveitar a folha errada não "funciona por
# acaso" — quebra o Traefik inteiro, sem mensagem que diga por quê
# (scripts/qa/dev_key_permissions_test.sh confere o EKU das quatro).
#
# emitir_folha <dir> <nome> <cn> <eku> <dias> <san>
#   eku:  serverAuth | clientAuth
#   dias: validade da folha
#   san:  subjectAltName; vazio omite a extensão (o OpenSSL recusa SAN vazio, e
#         uma folha de cliente não tem nome a afirmar)
emitir_folha() {
  dir="$1"; nome="$2"; cn="$3"; eku="$4"; dias="$5"; folha_san="$6"
  key_tmp="$dir/$nome.key.tmp"
  crt_tmp="$dir/$nome.crt.tmp"
  csr="$dir/$nome.csr"

  openssl genrsa -out "$key_tmp" 2048 2>/dev/null
  openssl req -new -key "$key_tmp" \
    -subj "/C=BR/O=SinalACS Dev/CN=$cn" \
    -out "$csr"

  # As duas extensões de restrição são as que o init.sh do broker declara. Sem
  # elas a folha não afirma nada sobre o que ela é: sem `basicConstraints`, a
  # ausência só significa "não é CA" por omissão, e sem `keyUsage` não há
  # restrição nenhuma — era a única diferença entre esta folha e a do broker,
  # que o app já valida (`dart:io`/BoringSSL).
  ext_file="$dir/$nome.ext"
  if [ "$eku" = clientAuth ]; then
    key_usage=digitalSignature
  else
    key_usage=digitalSignature,keyEncipherment
  fi
  {
    echo "basicConstraints=CA:FALSE"
    echo "keyUsage=$key_usage"
    echo "extendedKeyUsage=$eku"
    [ -n "$folha_san" ] && echo "subjectAltName=$folha_san"
  } > "$ext_file"

  # Aqui NÃO tem `2>/dev/null`: o erro do OpenSSL é o diagnóstico, e engoli-lo
  # foi o que transformou uma falha de configuração num arquivo vazio.
  if ! openssl x509 -req -in "$csr" \
    -CA "$certs_dir/ca.crt" -CAkey "$certs_dir/ca.key" -CAcreateserial \
    -out "$crt_tmp" -days "$dias" -sha256 \
    -extfile "$ext_file"; then
    echo "erro: falha ao assinar o certificado $nome com a CA em $certs_dir/ca.key." >&2
    echo "erro: chave ilegível ou par ca.crt/ca.key de CAs diferentes. Nada foi substituído:" >&2
    echo "erro: o certificado anterior, se existia, continua no lugar e intacto." >&2
    rm -f "$crt_tmp" "$key_tmp" "$csr" "$ext_file"
    exit 1
  fi

  mv "$crt_tmp" "$dir/$nome.crt"
  mv "$key_tmp" "$dir/$nome.key"
  rm -f "$csr" "$ext_file"
}

emitir_folha "$certs_dir" server sinalacs-rpc serverAuth "$server_days" "$san"

# A folha do backend fica num diretório PRÓPRIO, que é o único montado no
# container do backend: ele recebe a folha, a chave dela e a CA pública, e nunca
# enxerga `ca.key`. O SAN cobre o nome que o Traefik verifica (`serverName` do
# `dynamic/tls.yaml`), o nome do serviço no Compose e o `localhost` do
# healthcheck, que roda dentro do próprio container. Não recebe o
# RPC_CERT_SAN_EXTRA: aparelho nenhum fala com o backend direto.
backend_dir="$runtime_dir/backend"
mkdir -p "$backend_dir"
emitir_folha "$backend_dir" backend sinalacs-serverpod serverAuth "$server_days" \
  "DNS:sinalacs-serverpod,DNS:serverpod,DNS:localhost,IP:127.0.0.1"
cp "$certs_dir/ca.crt" "$backend_dir/ca.crt"

# As duas folhas de CLIENTE do mTLS da 8080 (#90). A do Traefik fica em
# runtime/certs/, que o Traefik já monta em /certs (é o `certificates` do
# serversTransport `backend-tls`). A do healthcheck fica em runtime/backend/, o
# único diretório que o container do backend monta: sem ela o `curl` do
# HEALTHCHECK seria recusado pelo próprio backend e o container nunca ficaria
# healthy. São folhas DISTINTAS, com chave, CN e validade próprias: a do
# healthcheck pode ser regerada ou removida sem tocar na do Traefik, e um dia um
# log do CN distinguiria as duas origens. Sem SAN: certificado de cliente não
# afirma nome de host.
emitir_folha "$certs_dir" traefik-client sinalacs-traefik clientAuth "$server_days" ""
emitir_folha "$backend_dir" healthcheck sinalacs-healthcheck clientAuth "$healthcheck_days" ""

# 644 nos certificados e nas chaves, como o init.sh do broker faz com os dele. O
# `openssl` cria chave privada em 600 por conta própria, e 600 divergiria do
# broker sem ganho: é certificado de DESENVOLVIMENTO, num diretório que o
# .gitignore cobre, e o Traefik monta a pasta e lê como root hoje — o modo do
# arquivo não é o que protege este par. O 644 é o que evita a falha no dia em que
# alguém puser `user:` no serviço `traefik`, porque quem passar a ler como outro
# usuário precisa do bit de leitura. Num certificado de produção isto muda. A
# `backend.key` precisa dele já hoje: o backend roda como uid 1000.
chmod 755 "$runtime_dir" "$certs_dir" "$backend_dir"
chmod 644 "$certs_dir/ca.crt" "$certs_dir/server.crt" "$certs_dir/server.key"
chmod 644 "$backend_dir/ca.crt" "$backend_dir/backend.crt" "$backend_dir/backend.key"
# A folha do healthcheck é lida pelo curl do HEALTHCHECK, como uid 1000: 644,
# pelo mesmo motivo da backend.key.
chmod 644 "$backend_dir/healthcheck.crt" "$backend_dir/healthcheck.key"
# A chave da CA só assina folhas e quem a lê é este init.sh, como root: ninguém
# mais precisa do bit de leitura (server.key segue em 644 pelo motivo acima).
# A chave de cliente do Traefik também: só o Traefik a lê, e ele roda como root
# (medido, `uid=0`). É o mesmo critério da ca.key, não uma exceção a ele.
chmod 600 "$certs_dir/ca.key" "$certs_dir/traefik-client.key"
chmod 644 "$certs_dir/traefik-client.crt"

echo "CA do RPC e certificado do servidor prontos em $certs_dir (SAN: $san)."
openssl x509 -in "$certs_dir/server.crt" -noout -subject -dates -ext subjectAltName
echo "Certificado do backend (Traefik → backend) pronto em $backend_dir."
openssl x509 -in "$backend_dir/backend.crt" -noout -subject -dates -ext subjectAltName
echo "Certificados de CLIENTE do mTLS da 8080 (#90): Traefik em $certs_dir, healthcheck em $backend_dir."
openssl x509 -in "$certs_dir/traefik-client.crt" -noout -subject -dates -ext extendedKeyUsage
openssl x509 -in "$backend_dir/healthcheck.crt" -noout -subject -dates -ext extendedKeyUsage
