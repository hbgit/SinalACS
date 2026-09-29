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
# precisa dela; os outros três exigem.
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

echo
if [[ "$falhas" -eq 0 ]]; then
  echo 'OK — as propriedades do RNF04 conferem.'
else
  echo "FALHOU — $falhas asserção(ões) do RNF04 não conferem." >&2
fi
[[ "$falhas" -eq 0 ]]
