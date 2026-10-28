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
# Depois do SIGHUP, grava atomicamente (temporário + mv, mesmo diretório)
# `crl.loaded` com o sha256 da crl.pem que acabou de sinalizar (Task 7a). O
# backend espera esse marcador antes de derrubar a sessão do aparelho revogado:
# derrubada antes da recarga, o app reconecta em milissegundos e o broker,
# ainda com a CRL velha, o aceita. CRL recusada não toca no marcador.
#
# Roda com `pid: "service:mosquitto"` (vê o processo do broker) e como root (o
# broker roda como o usuário mosquitto). A sessão já aberta de um aparelho
# revogado sobrevive ao SIGHUP; quem a derruba é o backend, conectando com o
# client id do aparelho (MqttSessionKicker).
set -u

crl=/mosquitto/devices/crl.pem
ca=/mosquitto/devices/ca.crt
marcador=/mosquitto/devices/crl.loaded

estado() { stat -c '%i %Y' "$crl" 2>/dev/null || echo ausente; }
agora() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
# marcar <sha256>: o marcador nunca aparece pela metade para quem o lê.
marcar() {
  printf '%s\n' "$1" >"$marcador.tmp" && chmod 644 "$marcador.tmp" && mv -f "$marcador.tmp" "$marcador"
}

# Vazio de propósito: a primeira volta trata o arquivo atual como mudança e
# sinaliza o broker. Cobre a corrida do boot — o backend republica a CRL logo
# depois de o broker carregá-la, possivelmente antes deste sidecar subir.
ultimo=''
echo "sidecar da CRL no ar ($(agora)); vigiando $crl"
while :; do
  atual="$(estado)"
  if [ "$atual" != "$ultimo" ] && [ "$atual" != ausente ]; then
    # O sha256 de ANTES da validação; só vira marcador se o arquivo não mudou
    # (mesmo inode e mtime) até depois do SIGHUP.
    sha="$(sha256sum "$crl" 2>/dev/null | cut -d' ' -f1)"
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
        if [ "$(estado)" != "$atual" ]; then
          # Trocada no meio: a próxima volta sinaliza e marca a nova.
          echo "aviso: a crl.pem mudou durante a recarga ($(agora)); marcador não gravado."
        elif ! marcar "$sha"; then
          echo "erro: não consegui gravar $marcador ($(agora))."
        fi
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
