#!/usr/bin/env bash
#
# As propriedades que SÃO o RNF04, medidas na stack de pé (L-08).
#
# Por que existe: a bateria do `e2e.sh` prova o caminho feliz — os apps falam com
# o backend — e nada mais. Nenhuma das três coisas que o requisito pede estava
# afirmada em lugar nenhum, então três regressões passavam verdes: republicar a
# 8080 em texto claro, baixar o `minVersion` do `dynamic/tls.yaml` e tirar o
# `tls=true` do label do router. O requisito estava registrado como atendido sem
# guarda nenhuma.
#
#   ./scripts/qa/tls_invariants.sh
#
# Espera a stack de pé (`./scripts/qa/e2e.sh --keep` a deixa assim). O grupo D não
# precisa dela, nem as asserções estáticas E4, E7 e E9; os demais exigem.
#
# Cada exigência vem com o CONTROLE POSITIVO que a impede de passar por acidente.
# "O TLS 1.2 falha" também é verdade com a stack no chão, e "nada publicado na
# 8080" também: sem o "e o 1.3 completa o handshake com a cadeia verificada" e o
# "e o https responde 200 com a CA de desenvolvimento", as duas seriam asserções
# que passam por não haver o que medir. É o mesmo defeito que a sessão do RNF04
# caçou quatro vezes — um teste que não consegue falhar no defeito para o qual
# foi escrito.
#
# Sobre a asserção da 8080: ela NÃO é um `grep 0.0.0.0:8080` na saída do
# `docker compose ps`. Essa saída tem a linha do Traefik (`0.0.0.0:8081->8080`),
# onde 8080 é a porta INTERNA do dashboard — o grep acusaria o certo pelo motivo
# errado, e passaria a não acusar nada no dia em que alguém republicasse a porta
# de verdade com outro formato. Quem responde é o Docker sobre o container do
# backend (`docker port <container> 8080`), mais a medida comportamental: a
# conexão em texto claro tem de ser recusada.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

backend_container='sinalacs-serverpod'
rpc_ca='infra/docker/traefik/runtime/certs/ca.crt'
falhas=0

ok()    { echo "  ok    — $1"; }
falha() { echo "  FALHA — $1" >&2; falhas=$((falhas + 1)); }

echo '== Grupo A: a stack de pé e o RPC respondendo por HTTPS com a CA de desenvolvimento =='
if docker inspect -f '{{.State.Health.Status}}' "$backend_container" 2>/dev/null | grep -q '^healthy$'; then
  ok "o backend ($backend_container) está healthy"
else
  falha "o backend ($backend_container) não está healthy — suba a stack (./scripts/qa/e2e.sh --keep) antes de ler os grupos B e C, que medem o RNF04 e não a pilha no chão"
fi

if [[ ! -f "$rpc_ca" ]]; then
  falha "a CA do RPC não existe em $rpc_ca — o Traefik não subiu com certificado próprio"
else
  # `curl` sem `-k`: aqui a cadeia e o nome do host TÊM de verificar contra a CA
  # de desenvolvimento. É o controle positivo de tudo o que vem depois.
  corpo="$(curl -sS --max-time 10 --cacert "$rpc_ca" https://localhost/health/check 2>&1)"
  rc=$?
  if [[ "$rc" -eq 0 ]] && printf '%s' "$corpo" | grep -q '"status"'; then
    ok 'https://localhost/health/check respondeu 200 com a cadeia verificada pela CA do RPC'
  else
    falha "https://localhost/health/check não respondeu com a CA do RPC (curl exit $rc): $corpo"
  fi
fi

echo '== Grupo B: o RPC fala TLS 1.3, e só ele =='
# O controle positivo primeiro: se o 1.3 não completar, o vermelho do 1.2 abaixo
# não significaria "o mínimo está em 1.3", significaria "não há TLS nenhum".
t13="$(openssl s_client -brief -connect localhost:443 -tls1_3 -CAfile "$rpc_ca" </dev/null 2>&1)"
if printf '%s' "$t13" | grep -q 'Protocol version: TLSv1.3' \
   && ! printf '%s' "$t13" | grep -q 'verify error'; then
  ok "TLS 1.3 completa o handshake na 443 e a cadeia verifica (Protocol version: TLSv1.3)"
else
  falha "o handshake TLS 1.3 não completou ou não verificou — sem ele, a recusa do 1.2 abaixo seria verdade por acidente: $(printf '%s' "$t13" | head -3 | tr '\n' ' ')"
fi

t12="$(openssl s_client -brief -connect localhost:443 -tls1_2 -CAfile "$rpc_ca" </dev/null 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]] || printf '%s' "$t12" | grep -q 'CONNECTION ESTABLISHED'; then
  falha 'o handshake TLS 1.2 completou — o `minVersion: VersionTLS13` do infra/docker/traefik/dynamic/tls.yaml deixou de valer'
else
  ok "TLS 1.2 é recusado ($(printf '%s' "$t12" | grep -o 'SSL alert number [0-9]*' | head -1))"
fi

echo '== Grupo C: não existe caminho em texto claro até o RPC =='
# A porta INTERNA do backend continua sendo 8080 (é o que o Traefik alcança); o
# que não pode existir é publicação no host.
publicadas="$(docker port "$backend_container" 8080 2>&1)"
if [[ $? -eq 0 ]]; then
  falha "o container do backend publica a 8080 no host: $(printf '%s' "$publicadas" | tr '\n' ' ')"
else
  ok "o container do backend não publica a 8080 no host (docker: $(printf '%s' "$publicadas" | tr -d '\n'))"
fi

# Comportamental: nada responde em texto claro. Qualquer conexão é vermelho —
# inclusive a de outro processo que ocupe a 8080 nesta máquina, porque aí o
# pressuposto desta bateria (a porta está livre) não vale mais.
curl -sS --max-time 5 -o /dev/null 'http://localhost:8080/health/check' >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  falha 'http://localhost:8080/health/check respondeu — ou é o backend em texto claro, ou outro processo ocupa a 8080 nesta máquina; nos dois casos não dá para afirmar que o caminho em claro não existe'
else
  ok 'a conexão em texto claro para a 8080 é recusada'
fi

# E o texto claro na PRÓPRIA 443, que é onde ele reaparece sem ninguém notar.
# Medido: no estado bom o Traefik responde 404 em claro ali (só o TLS casa o
# router), e com o `tls=true` do label removido ele responde 200 com o corpo do
# backend. É o caminho em claro que o RNF04 proíbe, na mesma porta em que o
# handshake TLS continua completando — ou seja, o TLS "está de pé" e o requisito
# está violado. Por isso a asserção pergunta pelo CORPO do backend e não pelo
# código HTTP de quem respondeu.
corpo443="$(curl -sS --max-time 5 'http://localhost:443/health/check' 2>/dev/null)"
if printf '%s' "$corpo443" | grep -q '"status"'; then
  falha 'um pedido em texto claro para a 443 alcançou o backend — o `tls=true` do label do router deixou de valer'
else
  ok 'a 443 não entrega o backend a um pedido em texto claro'
fi

echo '== Grupo D: a regra de https do host (não precisa da stack) =='
# A regra de recusar host em texto claro existe em três cópias, e por construção:
# `requireSecureHost` em apps/acs/lib/core/network/backend_client.dart:36 e em
# apps/patient/lib/core/network/backend_client.dart:38, mais a reescrita em
# scripts/qa/measure_latency.dart:53 (o scripts/qa/ não tem pubspec, então ali não
# há como importar package:sinalacs_acs/…). Duplicação que não se elimina por
# import, mas que pode ser presa por teste em cada uma das três: as duas dos apps
# por apps/acs/test/backend_client_test.dart e
# apps/patient/test/backend_client_otp_test.dart (a CI roda as duas nos jobs
# acs-app e patient-app), e a do script por esta linha.
#
# A pergunta aqui é a do PORQUÊ da cópia, não só "recusa": o script recusa ANTES
# de gastar amostra, com o motivo na saída de erro. Se a checagem sumir, o
# live_check ainda recusa o host (a cópia dele é a barreira real) — mas o script
# roda as 5 amostras, imprime um relatório com 0/5 e sai 1, e a causa fica
# enterrada no JSON. Medido: era exatamente esse o desfecho antes de a checagem
# existir. Por isso a asserção exige as três coisas: exit 2, NADA no stdout, e o
# motivo em HTTPS no stderr.
ml_err_file="$(mktemp)"
trap 'rm -f "$ml_err_file"' EXIT
ml_out="$(dart run scripts/qa/measure_latency.dart --host 'http://localhost:8080/' --mqtt-password ir-relevante 2>"$ml_err_file")"
rc=$?
ml_err="$(cat "$ml_err_file")"
if [[ "$rc" -eq 2 && -z "$ml_out" ]] && printf '%s' "$ml_err" | grep -q 'HTTPS'; then
  ok 'o measure_latency recusa host em texto claro antes de medir (exit 2, nada no stdout, o https nomeado no stderr)'
else
  falha "o measure_latency não recusou o host em texto claro como o esperado: exit $rc, stdout com ${#ml_out} byte(s), stderr: $ml_err"
fi

echo '== Grupo E: o Traefik fala com o backend por TLS 1.3 MÚTUO, e só por ele =='
# O trecho que o Grupo C não vê: a 8080 INTERNA, na rede do Compose. Desde a #90
# o backend EXIGE certificado de cliente assinado pela CA do RPC, recusado no
# handshake — e o processo do modelo de ameaça da issue é "qualquer container na
# rede do Compose". Por isso as sondas rodam de FORA do container do backend, num
# container efêmero nessa rede, com a imagem que a stack já construiu
# (sinalacs/server:local traz o mesmo curl do HEALTHCHECK; `--entrypoint curl`).
# `--user` com o uid do host: no runner do CI o usuário é 1001 e o $tmp (mktemp,
# 700) não seria legível pelo uid 1000 da imagem; runtime/backend/ é 644.
#
# Desenho dos grupos B e F: E2 (com certificado, TLS 1.3, 200) é o controle
# positivo de TODAS as recusas (E1, E3, E5, E6) — sem ele, um container parado
# faria todas passarem. E o Grupo A é o controle positivo DO TRAEFIK: o 200 em
# https://localhost/health/check só existe porque o Traefik apresentou a folha
# traefik-client.crt (E4/E7) — sem ela, 5xx em tudo.
#
# As recusas afirmam a AUSÊNCIA de resposta HTTP (sem `< HTTP/`, sem `"status"`,
# `HTTP 000`), nunca o código de saída do curl (35 ou 56, conforme o OpenSSL) nem
# o texto do `openssl s_client`: no TLS 1.3 o cliente conclui o lado dele antes
# de o servidor validar o certificado, e o `s_client` imprime
# `CONNECTION ESTABLISHED` MESMO recusado (medido na PoC da #90).
rpc_backend_dir='infra/docker/traefik/runtime/backend'
rpc_certs_dir='infra/docker/traefik/runtime/certs'
e_tmp="$(mktemp -d)"
trap 'rm -f "$ml_err_file"; rm -rf "$e_tmp"' EXIT
rede="$(docker inspect "$backend_container" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)"
# sonda_8080 <args do curl...>: runtime/backend em /c (CA + folha do healthcheck),
# $e_tmp em /f (o certificado "de fora", gerado abaixo).
sonda_8080() {
  docker run --rm --network "$rede" --entrypoint curl --user "$(id -u):$(id -g)" \
    -v "$PWD/$rpc_backend_dir:/c:ro" -v "$e_tmp:/f:ro" \
    sinalacs/server:local -sS -v --max-time 5 -X POST -H 'Content-Type: application/json' -d '{}' \
    -w '\nHTTP %{http_code}\n' "$@" 2>&1
}
# "recusado" = nenhuma linha HTTP chegou. `HTTP 000` é o -w do curl sem resposta.
recusado() { ! printf '%s' "$1" | grep -qE '^< HTTP/|"status"' && printf '%s' "$1" | grep -q 'HTTP 000'; }
com_cert=(--tlsv1.3 --cacert /c/ca.crt --cert /c/healthcheck.crt --key /c/healthcheck.key)
url_8080="https://${backend_container}:8080/health/check"

if [[ -z "$rede" ]] || ! docker image inspect sinalacs/server:local >/dev/null 2>&1; then
  falha "não deu para achar a rede do $backend_container ou a imagem sinalacs/server:local — suba a stack antes de ler o Grupo E"
else
  e1="$(sonda_8080 "http://${backend_container}:8080/health/check")"
  if printf '%s' "$e1" | grep -q '"status"'; then
    falha 'a 8080 interna atende em texto claro — o `API_TLS_*` do serviço serverpod deixou de valer'
  else
    ok 'E1 — a 8080 interna não entrega o backend a um pedido em texto claro'
  fi

  e2="$(sonda_8080 "${com_cert[@]}" "$url_8080")"
  e2_ok=0
  if printf '%s' "$e2" | grep -q '"status"' && printf '%s' "$e2" | grep -q 'TLSv1.3' && printf '%s' "$e2" | grep -q 'HTTP 200'; then
    e2_ok=1
    ok 'E2 — com certificado de cliente da CA do RPC, a 8080 interna responde 200 por TLS 1.3 (controle positivo)'
  else
    falha "E2 — a 8080 interna não respondeu ao cliente COM certificado por TLS 1.3: $(printf '%s' "$e2" | grep -E '^\* |status|HTTP ' | tail -3 | tr '\n' ' ')"
  fi

  e3="$(sonda_8080 --tlsv1.2 --tls-max 1.2 --cacert /c/ca.crt --cert /c/healthcheck.crt --key /c/healthcheck.key "$url_8080")"
  if printf '%s' "$e3" | grep -q '"status"'; then
    falha 'E3 — a 8080 interna aceitou TLS 1.2 (com certificado válido) — o `minimumTlsProtocolVersion` do ApiTlsConfig deixou de valer'
  else
    ok 'E3 — a 8080 interna recusa TLS 1.2 mesmo com certificado válido'
  fi

  # Certificado "de fora": CA própria e uma folha dela com o MESMO CN do Traefik,
  # de propósito — a recusa tem de vir da cadeia, não do nome.
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$e_tmp/fora-ca.key" -out "$e_tmp/fora-ca.crt" \
    -subj '/CN=ca-de-fora' >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout "$e_tmp/fora.key" -out "$e_tmp/fora.csr" -subj '/CN=sinalacs-traefik' >/dev/null 2>&1
  printf 'extendedKeyUsage=clientAuth\n' >"$e_tmp/fora.ext"
  openssl x509 -req -days 2 -in "$e_tmp/fora.csr" -CA "$e_tmp/fora-ca.crt" -CAkey "$e_tmp/fora-ca.key" \
    -CAcreateserial -extfile "$e_tmp/fora.ext" -out "$e_tmp/fora.crt" >/dev/null 2>&1
  chmod 755 "$e_tmp"; chmod 644 "$e_tmp"/*
  # A geração do certificado "de fora" tem de ser conferida: se ela falhar (ou o
  # bind-mount de $e_tmp chegar vazio, daemon remoto/rootless), o curl sai com 58
  # ("could not load client certificate"), a saída tem `HTTP 000` e E6 passaria
  # SEM ter apresentado certificado nenhum — falso verde na asserção que diz "o
  # contexto confia só na CA do RPC" (revisão final da #90).
  fora_ok=1
  [[ -s "$e_tmp/fora.crt" && -s "$e_tmp/fora.key" ]] || fora_ok=0

  if [[ "$e2_ok" -eq 0 ]]; then
    falha 'E5/E6 — sem o controle positivo E2, a recusa seria verdade por acidente (stack no chão recusa tudo)'
  elif [[ "$fora_ok" -eq 0 ]]; then
    falha "E6 — não deu para gerar o certificado de outra CA em $e_tmp (openssl falhou); sem ele a sonda não prova nada"
  else
    e5="$(sonda_8080 --tlsv1.3 --cacert /c/ca.crt "$url_8080")"
    if recusado "$e5"; then
      ok 'E5 — SEM certificado de cliente, a 8080 interna recusa no handshake (nenhuma linha HTTP) — o caso negativo da #90'
    else
      falha "E5 — a 8080 interna atendeu um cliente SEM certificado — o requireClientCertificate do mtls_api_server.dart ou a API_TLS_CLIENT_CA_PATH deixaram de valer: $(printf '%s' "$e5" | grep -E '^< HTTP|status|HTTP ' | tail -2 | tr '\n' ' ')"
    fi

    e6="$(sonda_8080 --tlsv1.3 --cacert /c/ca.crt --cert /f/fora.crt --key /f/fora.key "$url_8080")"
    if printf '%s' "$e6" | grep -q 'curl: (58)'; then
      falha "E6 — o curl não conseguiu carregar o certificado de outra CA (curl: (58)); a sonda não apresentou certificado e não prova nada: $(printf '%s' "$e6" | grep 'curl: (58)' | head -1)"
    elif recusado "$e6"; then
      ok 'E6 — certificado de OUTRA CA (mesmo CN do Traefik) é recusado no handshake'
    else
      falha "E6 — a 8080 interna aceitou certificado de outra CA — o contexto confia em mais do que a CA do RPC: $(printf '%s' "$e6" | grep -E 'status|HTTP ' | tail -2 | tr '\n' ' ')"
    fi

    # E8 — o bloqueio não pode virar DoS: handshakes recusados chegam ao stream do
    # listener como erro; 20 recusas seguidas e, depois, o cliente legítimo ainda
    # recebe 200, sem reinício do processo.
    for _ in $(seq 1 10); do
      sonda_8080 --tlsv1.3 --cacert /c/ca.crt "$url_8080" >/dev/null 2>&1
      sonda_8080 --tlsv1.3 --cacert /c/ca.crt --cert /f/fora.crt --key /f/fora.key "$url_8080" >/dev/null 2>&1
    done
    e8="$(sonda_8080 "${com_cert[@]}" "$url_8080")"
    reinicios="$(docker inspect -f '{{.RestartCount}}' "$backend_container" 2>/dev/null)"
    if printf '%s' "$e8" | grep -q '"status"' && printf '%s' "$e8" | grep -q 'HTTP 200' && [[ "$reinicios" == 0 ]]; then
      ok 'E8 — 20 handshakes recusados seguidos não derrubam o listener: o cliente com certificado ainda recebe 200 e RestartCount=0'
    else
      falha "E8 — handshakes recusados derrubaram o listener da 8080 (RestartCount=$reinicios) — o handleError do SecureServerSocketAsServerSocket ou o tratamento do SDK deixaram de valer: $(printf '%s' "$e8" | grep -E 'status|HTTP ' | tail -2 | tr '\n' ' ')"
    fi
  fi
fi

# E4 — estática, não precisa da stack: o Traefik só autentica o backend se
# verificar a cadeia, e só é autenticado por ele se apresentar a folha. Um
# `insecureSkipVerify` deixaria as sondas acima verdes — o trecho continua
# cifrado — com o backend sem autenticação nenhuma. Só linhas de configuração:
# o comentário do dynamic/tls.yaml cita a palavra.
transporte="$(awk '/^    backend-tls:/{f=1;next} f&&/^    [^ ]/{f=0} f' infra/docker/traefik/dynamic/tls.yaml)"
if grep -rniE '^[^#]*insecureSkipVerify' infra/docker/traefik/dynamic docker-compose.yml >/dev/null 2>&1; then
  falha 'E4 — há `insecureSkipVerify` na configuração do Traefik — o trecho até o backend deixou de verificar a cadeia'
elif ! grep -q 'loadbalancer.server.scheme=https' docker-compose.yml \
     || ! grep -q 'loadbalancer.serverstransport=backend-tls@file' docker-compose.yml; then
  falha 'E4 — o router sinalacs não usa `server.scheme=https` com `serverstransport=backend-tls@file` no docker-compose.yml'
elif ! printf '%s' "$transporte" | grep -q 'serverName: sinalacs-serverpod' \
     || ! printf '%s' "$transporte" | grep -q '/certs/ca.crt'; then
  falha 'E4 — o transporte backend-tls perdeu `serverName`/`rootCAs` — o Traefik deixou de autenticar o backend'
elif ! printf '%s' "$transporte" | grep -q 'certFile: /certs/traefik-client.crt' \
     || ! printf '%s' "$transporte" | grep -q 'keyFile: /certs/traefik-client.key'; then
  falha 'E4 — o transporte backend-tls não apresenta `certificates` (traefik-client.crt/key) — o Traefik não se autentica no backend (#90)'
elif ! grep -qE '^\s+API_TLS_CLIENT_CA_PATH:' docker-compose.yml; then
  falha 'E4 — o serviço serverpod não define API_TLS_CLIENT_CA_PATH — o backend não exige certificado de cliente (#90)'
else
  ok 'E4 — o Traefik disca o backend por https pelo transporte backend-tls (serverName, rootCAs, certificates), sem insecureSkipVerify, e o backend exige a CA'
fi

# E7 — nos arquivos gerados: a folha que o Traefik apresenta é um certificado de
# CLIENTE desta CA. Uma folha serverAuth reaproveitada é recusada pelo BoringSSL
# do backend e o Traefik devolve 5xx em tudo, sem dizer por quê.
if [[ ! -f "$rpc_certs_dir/traefik-client.crt" ]]; then
  falha "E7 — $rpc_certs_dir/traefik-client.crt não existe — o traefik-init da #90 não rodou"
elif ! openssl x509 -in "$rpc_certs_dir/traefik-client.crt" -noout -ext extendedKeyUsage 2>/dev/null | grep -q 'TLS Web Client Authentication'; then
  falha 'E7 — traefik-client.crt não tem EKU clientAuth'
elif ! openssl verify -CAfile "$rpc_ca" "$rpc_certs_dir/traefik-client.crt" >/dev/null 2>&1; then
  falha 'E7 — traefik-client.crt não é assinado pela CA do RPC'
else
  ok 'E7 — traefik-client.crt é certificado de cliente (clientAuth) assinado pela CA do RPC'
fi

# E9 — a folha do healthcheck é curta (90 dias, #90) e distinta da do Traefik.
# Vencida, o backend recusa o próprio healthcheck, o container fica unhealthy e
# o Traefik o tira da rota — sem mensagem que diga por quê.
hc="$rpc_backend_dir/healthcheck.crt"
if [[ ! -f "$hc" ]]; then
  falha "E9 — $hc não existe — o traefik-init da #90 não rodou"
elif ! openssl x509 -in "$hc" -noout -checkend 604800 >/dev/null 2>&1; then
  falha 'E9 — a folha do healthcheck vence em menos de 7 dias: `docker compose up -d --force-recreate traefik-init serverpod` a regera; sem isso o backend fica unhealthy sem dizer por quê'
elif [[ "$(openssl x509 -in "$hc" -noout -serial 2>/dev/null)" == "$(openssl x509 -in "$rpc_certs_dir/traefik-client.crt" -noout -serial 2>/dev/null)" ]]; then
  falha 'E9 — a folha do healthcheck é a mesma do Traefik — têm de ser distintas (CN, chave e validade próprias)'
else
  ok 'E9 — a folha do healthcheck vale por mais de 7 dias e é distinta da do Traefik'
fi

echo '== Grupo F: o broker MQTT fala TLS 1.3, e só ele =='
# O broker exige certificado de cliente (`require_certificate true`), então as
# sondas apresentam o do backend: sem ele o handshake cai em QUALQUER versão, e a
# recusa do 1.2 seria verdade por acidente. Mesmo desenho do Grupo B: o 1.3
# completando é o controle positivo do 1.2 recusado.
mqtt_certs='infra/docker/mosquitto/runtime/certs'
mqtt_ok=1
for f in ca.crt backend.crt backend.key; do
  if [[ ! -f "$mqtt_certs/$f" ]]; then
    falha "$mqtt_certs/$f não existe — o mosquitto-init não gerou os certificados do broker"
    mqtt_ok=0
  fi
done
if [[ "$mqtt_ok" -eq 1 ]]; then
  mqtt_tls=(-connect localhost:8883 -CAfile "$mqtt_certs/ca.crt" -cert "$mqtt_certs/backend.crt" -key "$mqtt_certs/backend.key")
  m13="$(openssl s_client -brief -tls1_3 "${mqtt_tls[@]}" </dev/null 2>&1)"
  if printf '%s' "$m13" | grep -q 'Protocol version: TLSv1.3' \
     && ! printf '%s' "$m13" | grep -q 'verify error'; then
    ok 'TLS 1.3 completa o handshake na 8883 com certificado de cliente e a cadeia verifica'
  else
    falha "o handshake TLS 1.3 na 8883 não completou ou não verificou: $(printf '%s' "$m13" | head -3 | tr '\n' ' ')"
  fi

  m12="$(openssl s_client -brief -tls1_2 "${mqtt_tls[@]}" </dev/null 2>&1)"
  rc=$?
  if [[ "$rc" -eq 0 ]] || printf '%s' "$m12" | grep -q 'CONNECTION ESTABLISHED'; then
    falha 'o handshake TLS 1.2 completou na 8883 — o `tls_version tlsv1.3` do infra/docker/mosquitto/mosquitto.conf deixou de valer'
  else
    ok "TLS 1.2 é recusado na 8883 ($(printf '%s' "$m12" | grep -o 'SSL alert number [0-9]*' | head -1))"
  fi
fi

# E o cliente MQTT do próprio backend continua conectado: um broker só-1.3 que o
# backend não alcança deixaria o RPC verde e os alertas vermelhos sem entrega.
# Espera até 60 s porque, logo depois de um restart do broker, a reconexão do
# despachante ainda está no backoff.
mqtt_corpo=''
for _ in $(seq 1 20); do
  mqtt_corpo="$(curl -sS --max-time 5 --cacert "$rpc_ca" https://localhost/health/check 2>&1)"
  printf '%s' "$mqtt_corpo" | grep -q '"mqttConnected":true' && break
  sleep 3
done
if printf '%s' "$mqtt_corpo" | grep -q '"mqttConnected":true'; then
  ok 'o backend está conectado ao broker (mqttConnected: true)'
else
  falha "o backend não está conectado ao broker depois de 60 s: $mqtt_corpo"
fi

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — as propriedades do RNF04 conferem.'
else
  echo "FALHOU — $falhas asserção(ões) do RNF04 não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
