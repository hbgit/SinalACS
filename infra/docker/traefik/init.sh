#!/bin/sh
#
# Gera a CA de desenvolvimento do RPC e o certificado do servidor que o
# Traefik apresenta em :443 (RNF04).
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

# Reaproveita a CA existente enquanto ela estiver legível e longe de vencer (30
# dias), como o init.sh do broker. Ver o cabeçalho sobre por que ela não é
# regerada a cada subida.
#
# A guarda checa existência, validade E usabilidade. Só as duas primeiras deixam
# passar um `ca.key` truncado — o arquivo existe e o `ca.crt` está longe de
# vencer —, e a falha só aparecia na hora de assinar, depois de o `server.key`
# já ter sido sobrescrito. Aqui ela sai com diagnóstico antes de tocar em
# qualquer coisa, e NÃO regera a CA de propósito: regerá-la invalidaria em
# silêncio as cópias já feitas para os apps (ver o cabeçalho). Como o serviço
# `traefik-init` é fail-closed, o resultado é o Traefik não subir — e não um
# certificado meio-gerado.
needs_ca=0
if [ ! -f "$certs_dir/ca.crt" ] || [ ! -f "$certs_dir/ca.key" ]; then
  needs_ca=1
elif ! openssl x509 -in "$certs_dir/ca.crt" -noout -checkend 2592000 >/dev/null 2>&1; then
  echo 'CA de desenvolvimento do RPC expira em menos de 30 dias; regerando.'
  needs_ca=1
elif ! openssl pkey -in "$certs_dir/ca.key" -noout >/dev/null 2>&1; then
  echo "erro: a chave da CA do RPC em $certs_dir/ca.key não é utilizável (vazia, truncada ou ilegível)." >&2
  echo "erro: nada foi regerado de propósito — regerar a CA invalidaria as cópias já feitas para os apps." >&2
  echo "erro: para forçar, apague $certs_dir/ca.crt e $certs_dir/ca.key, suba a stack de novo" >&2
  echo "erro: e rode scripts/dev/sync_dev_ca.sh para os apps confiarem na CA nova." >&2
  exit 1
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
fi

# A folha vai para arquivos temporários e só substitui o que está em uso depois
# de assinada com sucesso. Sem isto, uma falha de OpenSSL destrói o certificado
# anterior: o `openssl x509 -req` trunca o arquivo de `-out` ANTES de falhar, e a
# folha boa em uso vira um arquivo de 0 byte — foi o que aconteceu com o
# `2>/dev/null` que engolia o erro e o `set -e` abortando depois. O par
# `ca.crt`/`ca.key` de CAs diferentes cai no mesmo caminho (a chave é legível, a
# assinatura é que não casa), e também tem de sair com diagnóstico.
server_key_tmp="$certs_dir/server.key.tmp"
server_crt_tmp="$certs_dir/server.crt.tmp"
server_csr="$certs_dir/server.csr"

openssl genrsa -out "$server_key_tmp" 2048 2>/dev/null
openssl req -new -key "$server_key_tmp" \
  -subj "/C=BR/O=SinalACS Dev/CN=sinalacs-rpc" \
  -out "$server_csr"

# As duas extensões de restrição são as que o init.sh do broker declara. Sem
# elas a folha não afirma nada sobre o que ela é: sem `basicConstraints`, a
# ausência só significa "não é CA" por omissão, e sem `keyUsage` não há restrição
# nenhuma — era a única diferença entre esta folha e a do broker, que o app já
# valida (`dart:io`/BoringSSL).
ext_file="$certs_dir/server.ext"
cat > "$ext_file" <<EXT
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$san
EXT

# Aqui NÃO tem `2>/dev/null`: o erro do OpenSSL é o diagnóstico, e engoli-lo foi
# o que transformou uma falha de configuração num arquivo vazio.
if ! openssl x509 -req -in "$server_csr" \
  -CA "$certs_dir/ca.crt" -CAkey "$certs_dir/ca.key" -CAcreateserial \
  -out "$server_crt_tmp" -days "$server_days" -sha256 \
  -extfile "$ext_file"; then
  echo "erro: falha ao assinar o certificado do servidor com a CA em $certs_dir/ca.key." >&2
  echo "erro: chave ilegível ou par ca.crt/ca.key de CAs diferentes. Nada foi substituído:" >&2
  echo "erro: o certificado anterior, se existia, continua no lugar e intacto." >&2
  rm -f "$server_crt_tmp" "$server_key_tmp" "$server_csr" "$ext_file"
  exit 1
fi

mv "$server_crt_tmp" "$certs_dir/server.crt"
mv "$server_key_tmp" "$certs_dir/server.key"
rm -f "$server_csr" "$ext_file"

# 644 nos certificados e nas chaves, como o init.sh do broker faz com os dele. O
# `openssl` cria chave privada em 600 por conta própria, e 600 divergiria do
# broker sem ganho: é certificado de DESENVOLVIMENTO, num diretório que o
# .gitignore cobre, e o Traefik monta a pasta e lê como root hoje — o modo do
# arquivo não é o que protege este par. O 644 é o que evita a falha no dia em que
# alguém puser `user:` no serviço `traefik`, porque quem passar a ler como outro
# usuário precisa do bit de leitura. Num certificado de produção isto muda.
chmod 755 "$runtime_dir" "$certs_dir"
chmod 644 "$certs_dir/ca.crt" "$certs_dir/ca.key" "$certs_dir/server.crt" "$certs_dir/server.key"

echo "CA do RPC e certificado do servidor prontos em $certs_dir (SAN: $san)."
openssl x509 -in "$certs_dir/server.crt" -noout -subject -dates -ext subjectAltName
