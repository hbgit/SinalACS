#!/usr/bin/env bash
# Painel lateral do bloco 5: escuta o tópico de alertas da microárea no broker.
#
# Grave em dois painéis lado a lado:
#   painel esquerdo:  ./watch_mqtt.sh          (este script, deixe rodando)
#   painel direito:   dart run bin/red_alert_cycle.dart
#
# NOTA SOBRE O USUÁRIO: assina como `backend`, que tem leitura em
# `sinalacs/v1/#`, para poder mostrar o curinga `+` e qualquer microárea em
# quadro. Um assinante com escopo de ACS (`acs-area-12`) hoje TAMBÉM receberia o
# alerta: o aclfile foi corrigido para o UUID de microárea do seed, que é onde o
# dispatcher realmente publica. Ainda assim, o que este painel demonstra é a
# PUBLICAÇÃO — para falar de isolamento territorial em locução, mostre o ACS
# sendo negado em outra microárea.
#
# A senha vem do .env (gerada por scripts/dev/bootstrap_env.sh), não de um
# default embutido: as senhas de desenvolvimento passaram a ser por máquina.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [[ -z "${MQTT_BACKEND_PASSWORD:-}" ]]; then
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
fi

if [[ -z "${MQTT_BACKEND_PASSWORD:-}" ]]; then
  echo 'erro: MQTT_BACKEND_PASSWORD não definido e .env não encontrado.' >&2
  echo 'Rode ./scripts/dev/bootstrap_env.sh na raiz do repositório.' >&2
  exit 1
fi

echo "escutando sinalacs/v1/microareas/+/alerts  (Ctrl-C para sair)"
echo

exec docker compose exec -T mosquitto mosquitto_sub \
  -h mosquitto -p 8883 \
  --cafile /mosquitto/certs/ca.crt \
  -u backend -P "$MQTT_BACKEND_PASSWORD" \
  -t 'sinalacs/v1/microareas/+/alerts' -v
