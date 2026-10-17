#!/usr/bin/env bash
# Confere que acs_alert_fallback_e2e.sh deixa o broker fora do alcance do
# aparelho sem pausar nada, conversa com o teste pela linha marcadora, insere o
# alerta sem passar pelo outbox, apaga o manifesto antes do down e termina nos
# asserts que só o banco responde — e que a descoberta do `flutter test` não
# alcança o teste (sufixo `_e2e`). Sem Docker e sem aparelho: lê o texto.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/acs_alert_fallback_e2e.sh
t=apps/acs/integration_test/alert_http_fallback_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'o teste tem sufixo _e2e (fora da descoberta)' "[[ -f $t ]]"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'remove o reverse do broker' "grep -qF 'reverse --remove tcp:8883' $s"
conferir 'nunca abre o reverse do broker' "! grep -qE 'reverse tcp:8883' $s"
conferir 'MQTT apontado para localhost' "grep -qF 'SINALACS_MQTT_HOST=localhost' $s"
conferir 'nada é pausado' "! grep -qF 'docker pause' $s"
conferir 'o teste pede o alerta (linha marcadora)' "grep -qF \"print('E2E_DISPARAR_ALERTA \" $t"
conferir 'o script atende o pedido' "grep -qF 'E2E_DISPARAR_ALERTA' $s"
conferir 'o insert não toca no outbox' "! grep -qiE 'insert into alert_outbox' $s"
conferir 'intervalo de produção no teste (sem alertFallbackInterval)' "! grep -qF 'alertFallbackInterval' $t"
conferir 'o manifesto sai antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -n -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'fixtures.json'"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
for marca in E2E_ALERTA_VIA_HTTP E2E_ACK_OK E2E_RESERVA_OK; do
  conferir "o teste imprime $marca" "grep -qF \"print('$marca\" $t"
  conferir "o script exige $marca" "grep -qF '$marca' $s"
done
conferir 'teto de 45 s no atraso' "grep -qF -- '-le 45000' $s"
conferir 'assert: alerta confirmado' "grep -qF \"status = 'acknowledged'\" $s"
conferir 'assert: uma linha acknowledged' "grep -qF \"result = 'acknowledged'\" $s"
conferir 'assert: nenhuma leitura auditada' "grep -qF \"= 'read'\" $s"
conferir 'assert: nada no alert_outbox' "grep -qF 'from alert_outbox' $s"

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
