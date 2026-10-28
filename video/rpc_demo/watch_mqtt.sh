#!/usr/bin/env bash
# Painel lateral do bloco 5: escuta o tópico de alertas da microárea no broker.
#
# Grave em dois painéis lado a lado:
#   painel esquerdo:  ./watch_mqtt.sh          (este script, deixe rodando)
#   painel direito:   dart run bin/red_alert_cycle.dart
#
# NOTA SOBRE A IDENTIDADE: assina como `backend` — a folha da CA de aparelhos
# (#94) que o broker toma pelo CN, com leitura em `sinalacs/v1/#` —, para poder
# mostrar o curinga `+` e qualquer microárea em quadro. Um aparelho do ACS (CN =
# UUID da microárea) só lê o tópico da própria microárea: o que este painel
# demonstra é a PUBLICAÇÃO — para falar de isolamento territorial em locução,
# mostre o ACS sendo negado em outra microárea (Grupo G de
# scripts/qa/mtls_invariants.sh).
#
# Sem senha: o broker não tem senha desde a #94. Roda dentro do contêiner do
# broker, que monta a CA do servidor em /mosquitto/certs e a de aparelhos em
# /mosquitto/devices.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "escutando sinalacs/v1/microareas/+/alerts  (Ctrl-C para sair)"
echo

exec docker compose exec -T mosquitto mosquitto_sub \
  -h mosquitto -p 8883 \
  --cafile /mosquitto/certs/ca.crt \
  --cert /mosquitto/devices/backend.crt --key /mosquitto/devices/backend.key \
  -t 'sinalacs/v1/microareas/+/alerts' -v
