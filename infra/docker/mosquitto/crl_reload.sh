#!/bin/sh
#
# Sidecar do broker (#94): recarrega a CRL de aparelhos no Mosquitto.
#
# Por que existe (medido no Mosquitto 2.1.2, scripts/qa/spikes/mosquitto_crl_spike.sh):
#   · o broker só lê o `crlfile` no load ou no SIGHUP — regravar crl.pem sem
#     sinal não revoga ninguém;
#   · o $CONTROL não tem reload e o mosquitto_signal é só um `kill`;
#   · uma CRL vazia ou inválida + SIGHUP TERMINA o broker.
# Então: a cada 2 s compara inode e mtime da crl.pem (o backend a regrava por
# temporário + rename, então toda troca muda o inode); mudou, valida com
# `openssl crl -CAfile` — sintaxe E assinatura da CA de aparelhos (uma CRL
# válida de outra CA também é recusada) — e só então manda SIGHUP ao broker.
# Inválida: loga e NÃO sinaliza; o broker segue com a CRL que já tinha.
#
# Roda com `pid: "service:mosquitto"` (vê o processo do broker) e como root (o
# broker roda como o usuário mosquitto). A sessão já aberta de um aparelho
# revogado sobrevive ao SIGHUP; quem a derruba é o backend, conectando com o
# client id do aparelho (MqttSessionKicker).
set -u

crl=/mosquitto/devices/crl.pem
ca=/mosquitto/devices/ca.crt

estado() { stat -c '%i %Y' "$crl" 2>/dev/null || echo ausente; }
agora() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Vazio de propósito: a primeira volta trata o arquivo atual como mudança e
# sinaliza o broker. Cobre a corrida do boot — o backend republica a CRL logo
# depois de o broker carregá-la, possivelmente antes deste sidecar subir.
ultimo=''
echo "sidecar da CRL no ar ($(agora)); vigiando $crl"
while :; do
  atual="$(estado)"
  if [ "$atual" != "$ultimo" ] && [ "$atual" != ausente ]; then
    if saida="$(openssl crl -in "$crl" -CAfile "$ca" -noout 2>&1)" \
       && printf '%s' "$saida" | grep -q 'verify OK'; then
      pid="$(pidof mosquitto || true)"
      if [ -z "$pid" ]; then
        # Broker ainda não subiu (ou caiu): tenta de novo na próxima volta,
        # sem marcar o estado como tratado.
        echo "aviso: CRL válida, mas o processo mosquitto não foi encontrado ($(agora)); tento de novo."
      elif kill -HUP "$pid"; then
        echo "CRL recarregada ($(agora))"
        ultimo="$atual"
      else
        echo "erro: kill -HUP $pid falhou ($(agora)); tento de novo."
      fi
    else
      echo "CRL recusada pelo sidecar, não recarregada ($(agora)): $(printf '%s' "$saida" | head -1)"
      ultimo="$atual"
    fi
  fi
  sleep 2
done
