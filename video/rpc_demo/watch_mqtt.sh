#!/usr/bin/env bash
# Painel lateral do bloco 5: escuta o tópico de alertas da microárea no broker.
#
# Grave em dois painéis lado a lado:
#   painel esquerdo:  ./watch_mqtt.sh          (este script, deixe rodando)
#   painel direito:   dart run bin/red_alert_cycle.dart
#
# NOTA SOBRE O USUÁRIO: assinamos como `backend`, não como um ACS. O aclfile
# (infra/docker/mosquitto/aclfile) concede leitura ao usuário `acs-area-12` no
# tópico `sinalacs/v1/microareas/area-12/alerts`, mas o dispatcher publica em
# `sinalacs/v1/microareas/<uuid-da-microárea>/alerts`. Os dois não se encontram,
# então um assinante com escopo de ACS não receberia nada hoje. Isto demonstra
# a PUBLICAÇÃO, não o isolamento territorial — não afirme o segundo na locução.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "escutando sinalacs/v1/microareas/+/alerts  (Ctrl-C para sair)"
echo

exec docker compose exec -T mosquitto mosquitto_sub \
  -h mosquitto -p 8883 \
  --cafile /mosquitto/certs/ca.crt \
  -u backend -P "${MQTT_BACKEND_PASSWORD:-development-backend-password}" \
  -t 'sinalacs/v1/microareas/+/alerts' -v
